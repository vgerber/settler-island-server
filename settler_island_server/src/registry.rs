use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::Arc;

use settler_island_protocol::{
    AwayPolicy, Difficulty, ErrorCode, LobbyId, LobbySummary, ServerLimit, User, UserId,
};
use tokio::sync::{mpsc, oneshot};
use tracing::error;

use crate::config::Config;
use crate::lobby::{self, LobbyHandle, LobbyNotice, LobbySetup, SeatCount};
use crate::metrics::Metrics;
use crate::outbox::Outbox;
use crate::store::{GameStore, SeatPlayer, StoredGame};

const COMMAND_QUEUE: usize = 256;

pub(crate) struct NewLobby {
    pub name: String,
    pub owner: User,
    pub outbox: Outbox,
    pub request_id: u32,
    pub password_hash: Option<String>,
    pub seats: SeatCount,
    pub points_to_win: u8,
    pub bot_difficulty: Difficulty,
    pub away_policy: AwayPolicy,
}

#[derive(Debug, Clone)]
pub(crate) struct LobbyEntry {
    pub handle: LobbyHandle,
    pub password_hash: Option<Arc<str>>,
}

/// A lobby a user may join; `claimed` when this join made it the user's lobby, so a failed join releases it.
pub(crate) struct Claim {
    pub entry: LobbyEntry,
    pub claimed: bool,
}

pub(crate) struct LobbyPage {
    pub total: u32,
    pub lobbies: Vec<LobbySummary>,
}

enum RegistryCommand {
    Create {
        lobby: NewLobby,
        reply: oneshot::Sender<Result<LobbyHandle, ErrorCode>>,
    },
    /// Finds a lobby for `user` to join, refusing while the user belongs to another one.
    Claim {
        lobby: LobbyId,
        user: UserId,
        reply: oneshot::Sender<Result<Claim, ErrorCode>>,
    },
    Release {
        lobby: LobbyId,
        user: UserId,
    },
    /// The lobby whose running game seats `user`, if any.
    RunningLobby {
        user: UserId,
        reply: oneshot::Sender<Option<LobbyId>>,
    },
    /// Started lobbies without members are left out unless `viewer` holds a seat in them.
    List {
        viewer: UserId,
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
            .await?
    }

    pub(crate) async fn claim(&self, lobby: LobbyId, user: UserId) -> Result<Claim, ErrorCode> {
        self.call(|reply| RegistryCommand::Claim { lobby, user, reply })
            .await?
    }

    /// Undoes a claim whose join failed.
    pub(crate) async fn release(&self, lobby: LobbyId, user: UserId) {
        // Only fails during shutdown, when memberships no longer matter.
        let _ = self
            .sender
            .send(RegistryCommand::Release { lobby, user })
            .await;
    }

    pub(crate) async fn running_lobby(&self, user: UserId) -> Result<Option<LobbyId>, ErrorCode> {
        self.call(|reply| RegistryCommand::RunningLobby { user, reply })
            .await
    }

    pub(crate) async fn list(
        &self,
        viewer: UserId,
        page: u32,
        per_page: u32,
    ) -> Result<LobbyPage, ErrorCode> {
        self.call(|reply| RegistryCommand::List {
            viewer,
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
    /// The one lobby each user belongs to, across all of the user's connections.
    memberships: HashMap<UserId, LobbyId>,
    /// The users who hold a seat in each lobby's running game, connected or not.
    seated: BTreeMap<LobbyId, Vec<UserId>>,
    next_id: u32,
    store: Arc<S>,
    config: Arc<Config>,
    metrics: Arc<Metrics>,
    notices: mpsc::UnboundedSender<LobbyNotice>,
}

/// Starts the registry with the lobbies of the games that were running when the server stopped.
pub(crate) fn spawn<S: GameStore>(
    store: Arc<S>,
    config: Arc<Config>,
    metrics: Arc<Metrics>,
    running: Vec<StoredGame>,
) -> RegistryHandle {
    let (sender, commands) = mpsc::channel(COMMAND_QUEUE);
    let (notices, notice_receiver) = mpsc::unbounded_channel();
    let mut registry = Registry {
        lobbies: BTreeMap::new(),
        memberships: HashMap::new(),
        seated: BTreeMap::new(),
        next_id: 0,
        store,
        config,
        metrics,
        notices,
    };
    for stored in running {
        registry.restore(&stored);
    }
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
                // Notices first: a membership change a lobby reported must count before the next request.
                biased;
                Some(notice) = notices.recv() => self.note(notice),
                command = commands.recv() => match command {
                    Some(command) => self.handle(command),
                    None => break,
                },
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
            RegistryCommand::Claim { lobby, user, reply } => {
                let _ = reply.send(self.claim(lobby, user));
            }
            RegistryCommand::Release { lobby, user } => self.leave(lobby, &user),
            RegistryCommand::RunningLobby { user, reply } => {
                let _ = reply.send(self.running_lobby(&user));
            }
            RegistryCommand::List {
                viewer,
                page,
                per_page,
                reply,
            } => {
                let _ = reply.send(self.page(&viewer, page, per_page));
            }
        }
    }

    fn note(&mut self, notice: LobbyNotice) {
        match notice {
            LobbyNotice::Updated(summary) => {
                if let Some(listing) = self.lobbies.get_mut(&summary.info.id) {
                    listing.summary = summary;
                }
            }
            LobbyNotice::Closed(id) => self.unlist_lobby(id),
            LobbyNotice::Seated { lobby, users } => {
                self.seated.insert(lobby, users);
            }
            LobbyNotice::Joined { lobby, user } => {
                self.memberships.insert(user, lobby);
            }
            LobbyNotice::Left { lobby, user } => self.leave(lobby, &user),
            LobbyNotice::Starting {
                lobby,
                users,
                reply,
            } => {
                // A lobby that went away while asking starts nothing.
                let _ = reply.send(self.admit_game(lobby, users));
            }
        }
    }

    /// Seats `users` in the lobby's new game unless a cap is reached. The seats count at once, so starts racing each
    /// other cannot pass a cap together.
    fn admit_game(&mut self, lobby: LobbyId, users: Vec<UserId>) -> Result<(), ErrorCode> {
        let running = self.seated.values().filter(|seated| !seated.is_empty());
        if running.count() >= self.config.max_running_games {
            return Err(ErrorCode::LimitReached {
                limit: ServerLimit::RunningGames,
            });
        }
        let at_cap = |user: &UserId| self.games_of(user) >= self.config.max_games_per_user;
        if users.iter().any(at_cap) {
            return Err(ErrorCode::LimitReached {
                limit: ServerLimit::GamesPerUser,
            });
        }
        self.seated.insert(lobby, users);
        Ok(())
    }

    /// Running games in which `user` holds a seat, connected or not.
    fn games_of(&self, user: &UserId) -> usize {
        self.seated
            .values()
            .filter(|users| users.contains(user))
            .count()
    }

    fn running_lobby(&self, user: &UserId) -> Option<LobbyId> {
        self.seated
            .iter()
            .find(|(_, users)| users.contains(user))
            .map(|(lobby, _)| *lobby)
    }

    fn leave(&mut self, lobby: LobbyId, user: &UserId) {
        if self.memberships.get(user) == Some(&lobby) {
            self.memberships.remove(user);
        }
    }

    fn claim(&mut self, lobby: LobbyId, user: UserId) -> Result<Claim, ErrorCode> {
        let claimed = match self.memberships.get(&user) {
            Some(current) if *current != lobby => return Err(ErrorCode::AlreadyInLobby),
            Some(_) => false,
            None => true,
        };
        let entry = self
            .lobbies
            .get(&lobby)
            .map(|listing| listing.entry.clone())
            .ok_or(ErrorCode::LobbyNotFound)?;
        if claimed {
            self.memberships.insert(user, lobby);
        }
        Ok(Claim { entry, claimed })
    }

    fn restore(&mut self, stored: &StoredGame) {
        let (game, record) = match stored.rebuild() {
            Ok(rebuilt) => rebuilt,
            Err(error) => {
                error!(game = stored.id.0, %error, "a stored game does not replay, it stays unrestored");
                return;
            }
        };
        let restored = lobby::restore(
            stored,
            game,
            record,
            self.store.clone(),
            self.config.clone(),
            self.metrics.clone(),
            self.notices.clone(),
        );
        let Some((handle, summary)) = restored else {
            error!(
                game = stored.id.0,
                "a stored game has no human seat, it stays unrestored"
            );
            return;
        };
        let id = stored.game.lobby;
        // New lobbies count on from the highest restored id, so ids stay unique.
        self.next_id = self.next_id.max(id.0);
        let humans = stored.game.seats.iter().filter_map(|player| match player {
            SeatPlayer::Human(user) => Some(user.id.clone()),
            SeatPlayer::Bot(_) => None,
        });
        self.seated.insert(id, humans.collect());
        let entry = LobbyEntry {
            handle,
            password_hash: None,
        };
        self.list_lobby(id, Listing { entry, summary });
    }

    fn create(&mut self, lobby: NewLobby) -> Result<LobbyHandle, ErrorCode> {
        if self.memberships.contains_key(&lobby.owner.id) {
            return Err(ErrorCode::AlreadyInLobby);
        }
        self.next_id += 1;
        let id = LobbyId(self.next_id);
        let owner = lobby.owner.id.clone();
        let setup = LobbySetup {
            id,
            name: lobby.name,
            owner: lobby.owner,
            outbox: lobby.outbox,
            request_id: lobby.request_id,
            has_password: lobby.password_hash.is_some(),
            seats: lobby.seats,
            points_to_win: lobby.points_to_win,
            bot_difficulty: lobby.bot_difficulty,
            away_policy: lobby.away_policy,
        };
        let (handle, summary) = lobby::spawn(
            setup,
            self.store.clone(),
            self.config.clone(),
            self.metrics.clone(),
            self.notices.clone(),
        );
        let entry = LobbyEntry {
            handle: handle.clone(),
            password_hash: lobby.password_hash.map(Arc::from),
        };
        self.list_lobby(id, Listing { entry, summary });
        self.memberships.insert(owner, id);
        Ok(handle)
    }

    fn list_lobby(&mut self, id: LobbyId, listing: Listing) {
        self.lobbies.insert(id, listing);
        self.count_lobbies();
    }

    /// Forgets a closed lobby with its members and seats.
    fn unlist_lobby(&mut self, id: LobbyId) {
        self.lobbies.remove(&id);
        self.count_lobbies();
        self.memberships.retain(|_, lobby| *lobby != id);
        self.seated.remove(&id);
    }

    fn count_lobbies(&self) {
        // The map holds far fewer lobbies than i64::MAX.
        self.metrics
            .lobbies
            .set(i64::try_from(self.lobbies.len()).unwrap_or(i64::MAX));
    }

    fn page(&self, viewer: &UserId, page: u32, per_page: u32) -> LobbyPage {
        let attended: HashSet<LobbyId> = self.memberships.values().copied().collect();
        let visible: Vec<&Listing> = self
            .lobbies
            .iter()
            .filter(|(id, listing)| {
                !listing.summary.info.started
                    || attended.contains(id)
                    || self
                        .seated
                        .get(id)
                        .is_some_and(|users| users.contains(viewer))
            })
            .map(|(_, listing)| listing)
            .collect();
        let skip = (page as usize).saturating_mul(per_page as usize);
        LobbyPage {
            total: visible.len() as u32,
            lobbies: visible
                .into_iter()
                .skip(skip)
                .take(per_page as usize)
                .map(|listing| listing.summary.clone())
                .collect(),
        }
    }
}
