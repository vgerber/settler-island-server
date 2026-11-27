#![allow(dead_code)] // Each test binary uses a different subset of these helpers.

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use settler_island_bot::Bot;
use settler_island_game::{Action, Game, Phase, PlayerView, RecordEntry, Seat};
use settler_island_protocol::{
    ClientMessage, Difficulty, ErrorCode, GuestSession, GuestSessionRequest, LobbyDetails, LobbyId,
    ServerMessage, User,
};
use settler_island_server::{
    Config, GameId, GameStore, IdentityStore, MemoryIdentityStore, MemoryStore, SessionSecret,
    StoreError, StoredGame,
};
use sqlx::postgres::PgConnectOptions;
use sqlx::{ConnectOptions, Executor};
use tokio::net::{TcpListener, TcpSocket, TcpStream};
use tokio::runtime::Runtime;
use tokio_tungstenite::tungstenite::{self, Message};
use tokio_tungstenite::{client_async, connect_async, MaybeTlsStream, WebSocketStream};

/// Long enough for a debug build under load, short enough that a deadlock fails the test.
pub const RECEIVE_TIMEOUT: Duration = Duration::from_secs(5);

pub const TEST_SESSION_SECRET: &[u8; 32] = b"settler-island-test-secret-32-by";

pub fn test_config() -> Config {
    Config {
        bind: SocketAddr::from(([127, 0, 0, 1], 0)),
        bot_delay: Duration::ZERO,
        // Scripted humans answer at once or not at all; a long wait would only slow the tests.
        trade_answer_time: Duration::from_millis(200),
        // Tests open many sessions from one address; the limiter has its own test.
        session_burst: 10_000,
        session_requests_per_minute: 600_000,
        ..Config::new(SessionSecret::new(TEST_SESSION_SECRET.to_vec()).unwrap())
    }
}

pub async fn start(config: Config) -> SocketAddr {
    start_with(
        config,
        MemoryStore::default(),
        MemoryIdentityStore::default(),
    )
    .await
}

/// Serves on the current runtime until it is dropped; the stores' running games are restored first.
pub async fn start_with(
    config: Config,
    store: impl GameStore,
    identities: impl IdentityStore,
) -> SocketAddr {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let router = settler_island_server::router(config, store, identities)
        .await
        .unwrap();
    tokio::spawn(async move {
        axum::serve(
            listener,
            router.into_make_service_with_connect_info::<SocketAddr>(),
        )
        .await
        .unwrap()
    });
    address
}

/// A runtime of its own for one server, so dropping it stops that server mid-flight like a crash.
pub fn server_runtime() -> Runtime {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .unwrap()
}

/// A memory store the test can read and hand to a second server after a restart.
#[derive(Clone, Default)]
pub struct SharedStore(pub Arc<MemoryStore>);

impl GameStore for SharedStore {
    async fn create_game(
        &self,
        game: settler_island_server::NewGame,
    ) -> Result<GameId, StoreError> {
        self.0.create_game(game).await
    }

    async fn append_action(
        &self,
        game: GameId,
        action: RecordEntry,
        snapshot: Option<Game>,
    ) -> Result<(), StoreError> {
        self.0.append_action(game, action, snapshot).await
    }

    async fn load_running(&self) -> Result<Vec<StoredGame>, StoreError> {
        self.0.load_running().await
    }

    async fn finish(&self, game: GameId, winner: Seat) -> Result<(), StoreError> {
        self.0.finish(game, winner).await
    }

    async fn abandon(&self, game: GameId) -> Result<(), StoreError> {
        self.0.abandon(game).await
    }

    async fn set_attended(&self, game: GameId, attended: bool) -> Result<(), StoreError> {
        self.0.set_attended(game, attended).await
    }
}

/// A fresh, empty database on the server in `SETTLER_TEST_DATABASE_URL`, so tests run in parallel;
/// dropped again when the guard goes out of scope.
pub struct TestDatabase {
    admin: PgConnectOptions,
    name: String,
}

impl TestDatabase {
    pub fn options(&self) -> PgConnectOptions {
        self.admin.clone().database(&self.name)
    }
}

impl Drop for TestDatabase {
    fn drop(&mut self) {
        let admin = self.admin.clone();
        let statement = format!("DROP DATABASE IF EXISTS {} WITH (FORCE)", self.name);
        // Drop cannot await and the test's runtime may be gone or busy, so a thread with its own runtime does it.
        let dropped = std::thread::spawn(move || {
            let runtime = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .unwrap();
            runtime.block_on(async {
                let mut connection = admin.connect().await.unwrap();
                connection.execute(statement.as_str()).await.unwrap();
            });
        })
        .join();
        if dropped.is_err() && !std::thread::panicking() {
            panic!("could not drop the test database {}", self.name);
        }
    }
}

/// `None` (after a skip notice) when `SETTLER_TEST_DATABASE_URL` is unset.
pub async fn test_database() -> Option<TestDatabase> {
    let Ok(url) = std::env::var("SETTLER_TEST_DATABASE_URL") else {
        let test = std::thread::current()
            .name()
            .unwrap_or("a test")
            .to_string();
        eprintln!("skipping {test}: SETTLER_TEST_DATABASE_URL is unset");
        return None;
    };
    let admin: PgConnectOptions = url.parse().unwrap();
    let name = format!("settler_test_{}", uuid::Uuid::new_v4().simple());
    let mut connection = admin.connect().await.unwrap();
    connection
        .execute(format!("CREATE DATABASE {name}").as_str())
        .await
        .unwrap();
    Some(TestDatabase { admin, name })
}

/// Polls `check` until it returns a value; panics after `RECEIVE_TIMEOUT`. For state that settles on its own,
/// where a fixed sleep is either too slow or flaky.
pub async fn eventually<Value, Check, Pending>(what: &str, mut check: Check) -> Value
where
    Check: FnMut() -> Pending,
    Pending: std::future::Future<Output = Option<Value>>,
{
    let deadline = tokio::time::Instant::now() + RECEIVE_TIMEOUT;
    loop {
        if let Some(value) = check().await {
            return value;
        }
        assert!(
            tokio::time::Instant::now() < deadline,
            "timed out waiting for {what}"
        );
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

pub async fn guest_session(address: SocketAddr, name: &str) -> GuestSession {
    let request = GuestSessionRequest {
        name: name.to_string(),
    };
    reqwest::Client::new()
        .post(format!("http://{address}/api/v1/sessions/guest"))
        .json(&request)
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap()
}

pub struct Client {
    socket: WebSocketStream<MaybeTlsStream<TcpStream>>,
    next_request: u32,
}

pub fn echoed_request_id(message: &ServerMessage) -> Option<u32> {
    match message {
        ServerMessage::Welcome { request_id, .. }
        | ServerMessage::Lobbies { request_id, .. }
        | ServerMessage::LobbyLeft { request_id }
        | ServerMessage::Record { request_id, .. } => Some(*request_id),
        ServerMessage::LobbyState { request_id, .. }
        | ServerMessage::GameStarted { request_id, .. }
        | ServerMessage::GameUpdate { request_id, .. }
        | ServerMessage::Error { request_id, .. } => *request_id,
    }
}

impl Client {
    pub async fn connect(address: SocketAddr) -> Client {
        Client::try_connect(address).await.unwrap()
    }

    /// The handshake result, so a test can inspect a refused upgrade.
    pub async fn try_connect(address: SocketAddr) -> Result<Client, tungstenite::Error> {
        let url = format!("ws://{address}/api/v1/ws");
        let (socket, _) = connect_async(url).await?;
        Ok(Client {
            socket,
            next_request: 0,
        })
    }

    /// A connection whose kernel receive buffer is `bytes`, so a client that stops reading backs up
    /// into the server after kilobytes instead of megabytes.
    pub async fn connect_with_receive_buffer(address: SocketAddr, bytes: u32) -> Client {
        let tcp = TcpSocket::new_v4().unwrap();
        tcp.set_recv_buffer_size(bytes).unwrap();
        let stream = tcp.connect(address).await.unwrap();
        let url = format!("ws://{address}/api/v1/ws");
        let (socket, _) = client_async(url, MaybeTlsStream::Plain(stream))
            .await
            .unwrap();
        Client {
            socket,
            next_request: 0,
        }
    }

    /// A new guest session on a new connection.
    pub async fn welcomed(address: SocketAddr, name: &str) -> (Client, User) {
        let session = guest_session(address, name).await;
        Client::authenticated(address, &session.token).await
    }

    pub async fn authenticated(address: SocketAddr, token: &str) -> (Client, User) {
        let mut client = Client::connect(address).await;
        let reply = client.authenticate(token).await;
        let ServerMessage::Welcome { user, .. } = reply else {
            panic!("expected Welcome, got {reply:?}");
        };
        (client, user)
    }

    pub async fn authenticate(&mut self, token: &str) -> ServerMessage {
        let token = token.to_string();
        self.request(|request_id| ClientMessage::Authenticate { request_id, token })
            .await
    }

    pub async fn send(&mut self, build: impl FnOnce(u32) -> ClientMessage) -> u32 {
        self.next_request += 1;
        let request_id = self.next_request;
        let text = serde_json::to_string(&build(request_id)).unwrap();
        self.send_raw(text).await;
        request_id
    }

    pub async fn send_raw(&mut self, text: String) {
        self.socket.send(Message::text(text)).await.unwrap();
    }

    /// Like `send_raw`, but the server may drop the socket while the frame is still being written.
    pub async fn send_raw_unchecked(&mut self, text: String) {
        // A reset during the write is the outcome the caller provokes; it checks the close afterwards.
        let _ = self.socket.send(Message::text(text)).await;
    }

    /// Sends one message per millisecond and never reads; the count sent before a send failed,
    /// or `None` when all `limit` went through.
    pub async fn send_unread_until_closed(
        &mut self,
        limit: usize,
        build: impl Fn(u32) -> ClientMessage,
    ) -> Option<usize> {
        for sent in 0..limit {
            self.next_request += 1;
            let text = serde_json::to_string(&build(self.next_request)).unwrap();
            if self.socket.send(Message::text(text)).await.is_err() {
                return Some(sent);
            }
            tokio::time::sleep(Duration::from_millis(1)).await;
        }
        None
    }

    /// The next server message; panics on timeout or close so a stuck server fails the test.
    pub async fn receive(&mut self) -> ServerMessage {
        loop {
            let next = tokio::time::timeout(RECEIVE_TIMEOUT, self.socket.next())
                .await
                .expect("timed out waiting for the server")
                .expect("connection closed")
                .expect("websocket error");
            if let Message::Text(text) = next {
                return serde_json::from_str(text.as_str()).unwrap();
            }
        }
    }

    /// `true` when the server closes the connection within the timeout.
    pub async fn closed_by_server(&mut self) -> bool {
        loop {
            match tokio::time::timeout(RECEIVE_TIMEOUT, self.socket.next()).await {
                Err(_) => return false,
                Ok(None | Some(Err(_)) | Some(Ok(Message::Close(_)))) => return true,
                Ok(Some(Ok(_))) => continue,
            }
        }
    }

    /// Sends a WebSocket ping every 50 ms; true when the server closes the socket within `within`.
    pub async fn ping_until_closed(&mut self, within: Duration) -> bool {
        let deadline = tokio::time::Instant::now() + within;
        let mut interval = tokio::time::interval(Duration::from_millis(50));
        while tokio::time::Instant::now() < deadline {
            tokio::select! {
                _ = interval.tick() => {
                    if self.socket.send(Message::Ping(Vec::new().into())).await.is_err() {
                        return true;
                    }
                }
                next = self.socket.next() => match next {
                    None | Some(Err(_)) | Some(Ok(Message::Close(_))) => return true,
                    Some(Ok(_)) => {}
                },
            }
        }
        false
    }

    pub async fn send_pings(&mut self, count: usize) {
        for _ in 0..count {
            self.socket
                .send(Message::Ping(Vec::new().into()))
                .await
                .unwrap();
        }
    }

    /// Skips broadcasts until the message that echoes `request_id`.
    pub async fn reply(&mut self, request_id: u32) -> ServerMessage {
        loop {
            let message = self.receive().await;
            if echoed_request_id(&message) == Some(request_id) {
                return message;
            }
        }
    }

    pub async fn request(&mut self, build: impl FnOnce(u32) -> ClientMessage) -> ServerMessage {
        let request_id = self.send(build).await;
        self.reply(request_id).await
    }

    pub async fn expect_error(&mut self, build: impl FnOnce(u32) -> ClientMessage) -> ErrorCode {
        match self.request(build).await {
            ServerMessage::Error { code, .. } => code,
            other => panic!("expected an error, got {other:?}"),
        }
    }

    pub async fn expect_lobby(&mut self, build: impl FnOnce(u32) -> ClientMessage) -> LobbyDetails {
        match self.request(build).await {
            ServerMessage::LobbyState { lobby, .. } => lobby,
            other => panic!("expected LobbyState, got {other:?}"),
        }
    }

    /// The next lobby broadcast, skipping anything else.
    pub async fn next_lobby_state(&mut self) -> LobbyDetails {
        loop {
            if let ServerMessage::LobbyState { lobby, .. } = self.receive().await {
                return lobby;
            }
        }
    }

    pub async fn create_lobby(&mut self, name: &str, seats: u8, password: Option<&str>) -> LobbyId {
        self.create_lobby_to(name, seats, password, None).await
    }

    pub async fn create_lobby_to(
        &mut self,
        name: &str,
        seats: u8,
        password: Option<&str>,
        points_to_win: Option<u8>,
    ) -> LobbyId {
        let name = name.to_string();
        let password = password.map(str::to_string);
        let lobby = self
            .expect_lobby(|request_id| ClientMessage::CreateLobby {
                request_id,
                name,
                password,
                seats,
                points_to_win,
                bot_difficulty: None,
                away_policy: None,
            })
            .await;
        lobby.info.id
    }

    /// Joins and returns the lobby, or the refusal.
    pub async fn try_join(
        &mut self,
        lobby: LobbyId,
        password: Option<&str>,
    ) -> Result<LobbyDetails, ErrorCode> {
        let password = password.map(str::to_string);
        let reply = self
            .request(|request_id| ClientMessage::JoinLobby {
                request_id,
                lobby,
                password,
            })
            .await;
        match reply {
            ServerMessage::LobbyState { lobby, .. } => Ok(lobby),
            ServerMessage::Error { code, .. } => Err(code),
            other => panic!("expected LobbyState or Error, got {other:?}"),
        }
    }

    /// The next `GameStarted` (a start or a `GetState` answer), skipping anything else.
    pub async fn next_game_started(&mut self) -> Dealt {
        loop {
            if let ServerMessage::GameStarted {
                seat,
                view,
                legal_actions,
                ..
            } = self.receive().await
            {
                return Dealt {
                    seat,
                    view,
                    legal_actions,
                };
            }
        }
    }

    /// The next `GameUpdate`, skipping anything else.
    pub async fn next_game_update(&mut self) -> (PlayerView, Vec<Action>) {
        loop {
            if let ServerMessage::GameUpdate {
                view,
                legal_actions,
                ..
            } = self.receive().await
            {
                return (view, legal_actions);
            }
        }
    }

    /// Creates a lobby of `seats`, fills the other seats with bots of `difficulty`, starts it and waits for the deal.
    pub async fn start_with_bots(
        &mut self,
        name: &str,
        seats: u8,
        points_to_win: Option<u8>,
        difficulty: Difficulty,
    ) -> (LobbyId, Dealt) {
        let lobby = self.create_lobby_to(name, seats, None, points_to_win).await;
        for _ in 1..seats {
            self.expect_lobby(|request_id| ClientMessage::AddBot {
                request_id,
                difficulty,
            })
            .await;
        }
        let started = self
            .request(|request_id| ClientMessage::StartGame { request_id })
            .await;
        let ServerMessage::LobbyState { .. } = started else {
            panic!("expected LobbyState, got {started:?}");
        };
        (lobby, self.next_game_started().await)
    }
}

/// What a seat got when the game started.
pub struct Dealt {
    pub seat: Seat,
    pub view: PlayerView,
    pub legal_actions: Vec<Action>,
}

/// A seat's latest view while a bot plays it.
pub struct Play {
    pub view: PlayerView,
    pub legal: Vec<Action>,
    /// Game updates received so far.
    pub updates: usize,
    outstanding: Option<u32>,
}

impl Play {
    pub fn new(view: PlayerView, legal: Vec<Action>) -> Play {
        Play {
            view,
            legal,
            updates: 0,
            outstanding: None,
        }
    }

    /// The seat may act and has nothing in flight.
    pub fn to_move(&self) -> bool {
        self.outstanding.is_none() && !self.legal.is_empty()
    }

    pub fn finished(&self) -> bool {
        matches!(self.view.phase, Phase::Finished { .. })
    }
}

/// Plays the seat with `bot` until `stop` says so; `stop` is asked before every move. Lobby broadcasts are ignored and
/// a move that bots overtook is dropped (the next update brings a fresh list); anything else fails the test.
pub async fn play_as(
    client: &mut Client,
    bot: &mut dyn Bot,
    play: &mut Play,
    mut stop: impl FnMut(&Play) -> bool,
) {
    while !stop(play) {
        if play.to_move() {
            let action = bot.choose(&play.view, &play.legal);
            play.outstanding = Some(
                client
                    .send(|request_id| ClientMessage::Act { request_id, action })
                    .await,
            );
        }
        match client.receive().await {
            ServerMessage::GameUpdate {
                request_id,
                view,
                legal_actions,
                ..
            } => {
                if request_id.is_some() && request_id == play.outstanding {
                    play.outstanding = None;
                }
                play.view = view;
                play.legal = legal_actions;
                play.updates += 1;
            }
            ServerMessage::Error {
                request_id,
                code: ErrorCode::Game { .. },
                ..
            } if request_id.is_some() && request_id == play.outstanding => play.outstanding = None,
            ServerMessage::LobbyState { .. } => {}
            other => panic!("unexpected message during play: {other:?}"),
        }
    }
}
