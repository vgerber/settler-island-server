use std::sync::Arc;
use std::time::{Duration, Instant};

use axum::extract::ws::{Message, WebSocket};
use futures_util::stream::{SplitSink, SplitStream};
use futures_util::{SinkExt, StreamExt};
use serde::Deserialize;
use settler_island_protocol::{
    ClientMessage, Difficulty, ErrorCode, ServerMessage, User, UserId, DEFAULT_POINTS_TO_WIN,
    MAX_LOBBIES_PER_PAGE, MAX_LOBBY_NAME_CHARS, MAX_MESSAGE_BYTES, MAX_POINTS_TO_WIN, MAX_SEATS,
    MIN_POINTS_TO_WIN, MIN_SEATS,
};
use tokio::sync::{mpsc, Notify};
use tracing::{debug, error};

use crate::config::Config;
use crate::identity::{Identity, IdentityStore};
use crate::lobby::{LobbyCommand, LobbyHandle, LobbyRequest};
use crate::names::clean_name;
use crate::outbox::{Outbox, OUTBOX_CAPACITY};
use crate::password;
use crate::registry::{NewLobby, RegistryHandle};

/// The unvalidated settings of a `CreateLobby` request.
struct LobbyOptions {
    seats: u8,
    points_to_win: Option<u8>,
    bot_difficulty: Option<Difficulty>,
}

/// Counts messages in fixed one-second windows.
#[derive(Debug)]
struct RateLimiter {
    limit: u32,
    window_start: Instant,
    count: u32,
}

impl RateLimiter {
    fn new(limit: u32, now: Instant) -> RateLimiter {
        RateLimiter {
            limit,
            window_start: now,
            count: 0,
        }
    }

    fn allow(&mut self, now: Instant) -> bool {
        if now.duration_since(self.window_start) >= Duration::from_secs(1) {
            self.window_start = now;
            self.count = 0;
        }
        self.count += 1;
        self.count <= self.limit
    }
}

/// Recovers the request id of a message that failed to parse, so the error still reaches the right request.
#[derive(Deserialize)]
struct RequestIdProbe {
    request_id: u32,
}

struct Connection<I> {
    outbox: Outbox,
    registry: RegistryHandle,
    identity: Arc<Identity<I>>,
    user: Option<User>,
    lobby: Option<LobbyHandle>,
    limiter: RateLimiter,
}

/// Runs one client until it disconnects, idles out or falls behind.
pub(crate) async fn run<I: IdentityStore>(
    socket: WebSocket,
    registry: RegistryHandle,
    identity: Arc<Identity<I>>,
    config: Arc<Config>,
) {
    let (sink, stream) = socket.split();
    let (sender, receiver) = mpsc::channel(OUTBOX_CAPACITY);
    let kick = Arc::new(Notify::new());
    let writer = tokio::spawn(write_loop(sink, receiver));
    let mut connection = Connection {
        outbox: Outbox::new(sender, kick.clone()),
        registry,
        identity,
        user: None,
        lobby: None,
        limiter: RateLimiter::new(config.messages_per_second, Instant::now()),
    };
    connection
        .read_loop(stream, &kick, config.idle_timeout)
        .await;
    if let (Some(lobby), Some(user)) = (connection.lobby.take(), &connection.user) {
        lobby
            .leave(user.id.clone(), connection.outbox.clone())
            .await;
    }
    writer.abort();
}

async fn write_loop(
    mut sink: SplitSink<WebSocket, Message>,
    mut receiver: mpsc::Receiver<ServerMessage>,
) {
    while let Some(message) = receiver.recv().await {
        let text = match serde_json::to_string(&message) {
            Ok(text) => text,
            Err(error) => {
                error!(%error, "serializing a server message failed");
                continue;
            }
        };
        if sink.send(Message::Text(text.into())).await.is_err() {
            break;
        }
    }
}

impl<I: IdentityStore> Connection<I> {
    async fn read_loop(
        &mut self,
        mut stream: SplitStream<WebSocket>,
        kick: &Notify,
        idle_timeout: Duration,
    ) {
        loop {
            let next = tokio::select! {
                () = kick.notified() => return,
                next = tokio::time::timeout(idle_timeout, stream.next()) => next,
            };
            let Ok(Some(Ok(message))) = next else {
                debug!("connection closed or idle");
                return;
            };
            match message {
                Message::Text(text) => self.on_message(text.as_bytes()).await,
                Message::Binary(bytes) => self.on_message(&bytes).await,
                Message::Close(_) => return,
                // Pings count as activity; axum answers them itself.
                Message::Ping(_) | Message::Pong(_) => {}
            }
        }
    }

    async fn on_message(&mut self, bytes: &[u8]) {
        if !self.limiter.allow(Instant::now()) {
            self.send_error(None, ErrorCode::RateLimited);
            return;
        }
        if bytes.len() > MAX_MESSAGE_BYTES {
            self.send_error(None, ErrorCode::MessageTooLarge);
            return;
        }
        let message: ClientMessage = match serde_json::from_slice(bytes) {
            Ok(message) => message,
            Err(_) => {
                let probe = serde_json::from_slice::<RequestIdProbe>(bytes).ok();
                self.send_error(
                    probe.map(|probe| probe.request_id),
                    ErrorCode::InvalidMessage,
                );
                return;
            }
        };
        let request_id = message.request_id();
        if let Err(code) = self.dispatch(message).await {
            self.send_error(Some(request_id), code);
        }
    }

    fn send_error(&self, request_id: Option<u32>, code: ErrorCode) {
        self.outbox.send(ServerMessage::Error {
            request_id,
            code,
            message: code.description(),
        });
    }

    async fn dispatch(&mut self, message: ClientMessage) -> Result<(), ErrorCode> {
        if let ClientMessage::Authenticate { request_id, token } = message {
            return self.authenticate(request_id, &token).await;
        }
        let user = self.user.clone().ok_or(ErrorCode::NotWelcomed)?;
        match message {
            ClientMessage::Authenticate { .. } => Err(ErrorCode::AlreadyWelcomed),
            ClientMessage::ListLobbies {
                request_id,
                page,
                per_page,
            } => self.list(request_id, page, per_page).await,
            ClientMessage::CreateLobby {
                request_id,
                name,
                password,
                seats,
                points_to_win,
                bot_difficulty,
            } => {
                let options = LobbyOptions {
                    seats,
                    points_to_win,
                    bot_difficulty,
                };
                self.create(user, request_id, &name, password, options)
                    .await
            }
            ClientMessage::JoinLobby {
                request_id,
                lobby,
                password,
            } => {
                let entry = self
                    .registry
                    .find(lobby)
                    .await?
                    .ok_or(ErrorCode::LobbyNotFound)?;
                self.join(user, request_id, entry, password).await
            }
            ClientMessage::LeaveLobby { request_id } => self.leave(user.id, request_id).await,
            ClientMessage::AddBot {
                request_id,
                difficulty,
            } => {
                self.forward(user.id, request_id, LobbyRequest::AddBot { difficulty })
                    .await
            }
            ClientMessage::RemoveBot { request_id, seat } => {
                self.forward(user.id, request_id, LobbyRequest::RemoveBot { seat })
                    .await
            }
            ClientMessage::StartGame { request_id } => {
                self.forward(user.id, request_id, LobbyRequest::StartGame)
                    .await
            }
            ClientMessage::Act { request_id, action } => {
                self.forward(user.id, request_id, LobbyRequest::Act { action })
                    .await
            }
            ClientMessage::GetState { request_id } => {
                self.forward(user.id, request_id, LobbyRequest::GetState)
                    .await
            }
            ClientMessage::GetRecord { request_id } => {
                self.forward(user.id, request_id, LobbyRequest::GetRecord)
                    .await
            }
        }
    }

    async fn authenticate(&mut self, request_id: u32, token: &str) -> Result<(), ErrorCode> {
        if self.user.is_some() {
            return Err(ErrorCode::AlreadyWelcomed);
        }
        let user = self.identity.authenticate(token).await?;
        self.user = Some(user.clone());
        self.outbox
            .send(ServerMessage::Welcome { request_id, user });
        Ok(())
    }

    async fn list(&self, request_id: u32, page: u32, per_page: u32) -> Result<(), ErrorCode> {
        if !(1..=MAX_LOBBIES_PER_PAGE).contains(&per_page) {
            return Err(ErrorCode::InvalidPage);
        }
        let listing = self.registry.list(page, per_page).await?;
        self.outbox.send(ServerMessage::Lobbies {
            request_id,
            page,
            total: listing.total,
            lobbies: listing.lobbies,
        });
        Ok(())
    }

    async fn create(
        &mut self,
        owner: User,
        request_id: u32,
        name: &str,
        password: Option<String>,
        options: LobbyOptions,
    ) -> Result<(), ErrorCode> {
        if self.lobby.is_some() {
            return Err(ErrorCode::AlreadyInLobby);
        }
        let name = clean_name(name, MAX_LOBBY_NAME_CHARS).ok_or(ErrorCode::InvalidLobbyName)?;
        if !(MIN_SEATS..=MAX_SEATS).contains(&options.seats) {
            return Err(ErrorCode::InvalidSeatCount);
        }
        let points_to_win = options.points_to_win.unwrap_or(DEFAULT_POINTS_TO_WIN);
        if !(MIN_POINTS_TO_WIN..=MAX_POINTS_TO_WIN).contains(&points_to_win) {
            return Err(ErrorCode::InvalidPointsToWin);
        }
        let password_hash = match password.filter(|password| !password.is_empty()) {
            Some(password) => Some(hash_password(password).await?),
            None => None,
        };
        let lobby = NewLobby {
            name,
            owner,
            outbox: self.outbox.clone(),
            request_id,
            password_hash,
            seats: options.seats,
            points_to_win,
            bot_difficulty: options.bot_difficulty.unwrap_or(Difficulty::Heuristic),
        };
        self.lobby = Some(self.registry.create(lobby).await?);
        Ok(())
    }

    async fn join(
        &mut self,
        user: User,
        request_id: u32,
        entry: crate::registry::LobbyEntry,
        password: Option<String>,
    ) -> Result<(), ErrorCode> {
        if self.lobby.is_some() {
            return Err(ErrorCode::AlreadyInLobby);
        }
        if let Some(hash) = entry.password_hash {
            let password = password.unwrap_or_default();
            let matches = tokio::task::spawn_blocking(move || password::verify(&hash, &password))
                .await
                .map_err(|_| ErrorCode::Internal)?;
            if !matches {
                return Err(ErrorCode::WrongPassword);
            }
        }
        let outbox = self.outbox.clone();
        entry
            .handle
            .call(|reply| LobbyCommand::Join {
                user,
                outbox,
                request_id,
                reply,
            })
            .await
            .map_err(|code| match code {
                // The lobby closed between lookup and join.
                ErrorCode::NotInLobby => ErrorCode::LobbyNotFound,
                other => other,
            })?;
        self.lobby = Some(entry.handle);
        Ok(())
    }

    async fn leave(&mut self, user: UserId, request_id: u32) -> Result<(), ErrorCode> {
        let lobby = self.lobby.take().ok_or(ErrorCode::NotInLobby)?;
        lobby
            .call(|reply| LobbyCommand::Leave {
                user,
                outbox: self.outbox.clone(),
                reply: Some(reply),
            })
            .await?;
        self.outbox.send(ServerMessage::LobbyLeft { request_id });
        Ok(())
    }

    async fn forward(
        &mut self,
        user: UserId,
        request_id: u32,
        request: LobbyRequest,
    ) -> Result<(), ErrorCode> {
        let lobby = self.lobby.as_ref().ok_or(ErrorCode::NotInLobby)?;
        let result = lobby
            .call(|reply| LobbyCommand::Request {
                user,
                request_id,
                request,
                reply,
            })
            .await;
        if result == Err(ErrorCode::NotInLobby) {
            self.lobby = None;
        }
        result
    }
}

async fn hash_password(password: String) -> Result<String, ErrorCode> {
    let hashed = tokio::task::spawn_blocking(move || password::hash(&password))
        .await
        .map_err(|_| ErrorCode::Internal)?;
    hashed.map_err(|error| {
        error!(%error, "hashing a lobby password failed");
        ErrorCode::Internal
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rate_limiter_allows_the_limit_per_second_then_resets() {
        let start = Instant::now();
        let mut limiter = RateLimiter::new(3, start);

        assert!((0..3).all(|_| limiter.allow(start)));
        assert!(!limiter.allow(start + Duration::from_millis(999)));
        assert!(limiter.allow(start + Duration::from_secs(1)));
    }
}
