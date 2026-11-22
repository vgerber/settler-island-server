use std::collections::BTreeMap;
use std::sync::Arc;

use settler_island_protocol::{ErrorCode, LobbyId, LobbySummary, User};
use tokio::sync::{mpsc, oneshot};

use crate::config::Config;
use crate::lobby::{self, LobbyHandle, LobbyNotice, LobbySetup};
use crate::outbox::Outbox;
use crate::store::GameStore;

const COMMAND_QUEUE: usize = 256;

pub(crate) struct NewLobby {
    pub name: String,
    pub owner: User,
    pub outbox: Outbox,
    pub request_id: u32,
    pub password_hash: Option<String>,
    pub seats: u8,
}

#[derive(Debug, Clone)]
pub(crate) struct LobbyEntry {
    pub handle: LobbyHandle,
    pub password_hash: Option<Arc<str>>,
}

pub(crate) struct LobbyPage {
    pub total: u32,
    pub lobbies: Vec<LobbySummary>,
}

enum RegistryCommand {
    Create {
        lobby: NewLobby,
        reply: oneshot::Sender<LobbyHandle>,
    },
    Find {
        lobby: LobbyId,
        reply: oneshot::Sender<Option<LobbyEntry>>,
    },
    List {
        page: u32,
        per_page: u32,
        reply: oneshot::Sender<LobbyPage>,
    },
}

/// Cheap to clone; every connection holds one.
#[derive(Debug, Clone)]
pub(crate) struct RegistryHandle {
    sender: mpsc::Sender<RegistryCommand>,
}

impl RegistryHandle {
    pub(crate) async fn create(&self, lobby: NewLobby) -> Result<LobbyHandle, ErrorCode> {
        self.call(|reply| RegistryCommand::Create { lobby, reply })
            .await
    }

    pub(crate) async fn find(&self, lobby: LobbyId) -> Result<Option<LobbyEntry>, ErrorCode> {
        self.call(|reply| RegistryCommand::Find { lobby, reply })
            .await
    }

    pub(crate) async fn list(&self, page: u32, per_page: u32) -> Result<LobbyPage, ErrorCode> {
        self.call(|reply| RegistryCommand::List {
            page,
            per_page,
            reply,
        })
        .await
    }

    async fn call<T>(
        &self,
        command: impl FnOnce(oneshot::Sender<T>) -> RegistryCommand,
    ) -> Result<T, ErrorCode> {
        let (reply, answer) = oneshot::channel();
        self.sender
            .send(command(reply))
            .await
            .map_err(|_| ErrorCode::Internal)?;
        answer.await.map_err(|_| ErrorCode::Internal)
    }
}

struct Listing {
    entry: LobbyEntry,
    summary: LobbySummary,
}

struct Registry<S> {
    lobbies: BTreeMap<LobbyId, Listing>,
    next_id: u32,
    store: Arc<S>,
    config: Arc<Config>,
    notices: mpsc::UnboundedSender<LobbyNotice>,
}

pub(crate) fn spawn<S: GameStore>(store: Arc<S>, config: Arc<Config>) -> RegistryHandle {
    let (sender, commands) = mpsc::channel(COMMAND_QUEUE);
    let (notices, notice_receiver) = mpsc::unbounded_channel();
    let registry = Registry {
        lobbies: BTreeMap::new(),
        next_id: 0,
        store,
        config,
        notices,
    };
    tokio::spawn(registry.run(commands, notice_receiver));
    RegistryHandle { sender }
}

impl<S: GameStore> Registry<S> {
    async fn run(
        mut self,
        mut commands: mpsc::Receiver<RegistryCommand>,
        mut notices: mpsc::UnboundedReceiver<LobbyNotice>,
    ) {
        loop {
            tokio::select! {
                command = commands.recv() => match command {
                    Some(command) => self.handle(command),
                    None => break,
                },
                Some(notice) = notices.recv() => self.note(notice),
            }
        }
    }

    // Replies are ignored throughout: a requester that went away needs no answer.
    fn handle(&mut self, command: RegistryCommand) {
        match command {
            RegistryCommand::Create { lobby, reply } => {
                let handle = self.create(lobby);
                let _ = reply.send(handle);
            }
            RegistryCommand::Find { lobby, reply } => {
                let entry = self
                    .lobbies
                    .get(&lobby)
                    .map(|listing| listing.entry.clone());
                let _ = reply.send(entry);
            }
            RegistryCommand::List {
                page,
                per_page,
                reply,
            } => {
                let _ = reply.send(self.page(page, per_page));
            }
        }
    }

    fn note(&mut self, notice: LobbyNotice) {
        match notice {
            LobbyNotice::Updated(summary) => {
                if let Some(listing) = self.lobbies.get_mut(&summary.id) {
                    listing.summary = summary;
                }
            }
            LobbyNotice::Closed(id) => {
                self.lobbies.remove(&id);
            }
        }
    }

    fn create(&mut self, lobby: NewLobby) -> LobbyHandle {
        self.next_id += 1;
        let id = LobbyId(self.next_id);
        let setup = LobbySetup {
            id,
            name: lobby.name,
            owner: lobby.owner,
            outbox: lobby.outbox,
            request_id: lobby.request_id,
            has_password: lobby.password_hash.is_some(),
            seats: lobby.seats,
        };
        let (handle, summary) = lobby::spawn(
            setup,
            self.store.clone(),
            self.config.clone(),
            self.notices.clone(),
        );
        let entry = LobbyEntry {
            handle: handle.clone(),
            password_hash: lobby.password_hash.map(Arc::from),
        };
        self.lobbies.insert(id, Listing { entry, summary });
        handle
    }

    fn page(&self, page: u32, per_page: u32) -> LobbyPage {
        let skip = (page as usize).saturating_mul(per_page as usize);
        LobbyPage {
            total: self.lobbies.len() as u32,
            lobbies: self
                .lobbies
                .values()
                .skip(skip)
                .take(per_page as usize)
                .map(|listing| listing.summary.clone())
                .collect(),
        }
    }
}
