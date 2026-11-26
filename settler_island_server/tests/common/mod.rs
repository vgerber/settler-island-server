#![allow(dead_code)] // Each test binary uses a different subset of these helpers.

use std::net::SocketAddr;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use settler_island_protocol::{
    ClientMessage, ErrorCode, GuestSession, GuestSessionRequest, LobbyDetails, LobbyId,
    ServerMessage, User,
};
use settler_island_server::{
    Config, GameStore, IdentityStore, MemoryIdentityStore, MemoryStore, SessionSecret,
};
use sqlx::postgres::PgConnectOptions;
use sqlx::{ConnectOptions, Executor};
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::{connect_async, MaybeTlsStream, WebSocketStream};

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

/// A fresh, empty database on the server in `SETTLER_TEST_DATABASE_URL`, so tests run in parallel;
/// `None` (after a skip notice) when the variable is unset.
pub async fn test_database(test: &str) -> Option<PgConnectOptions> {
    let Ok(url) = std::env::var("SETTLER_TEST_DATABASE_URL") else {
        eprintln!("skipping {test}: SETTLER_TEST_DATABASE_URL is unset");
        return None;
    };
    let options: PgConnectOptions = url.parse().unwrap();
    let name = format!("settler_test_{}", uuid::Uuid::new_v4().simple());
    let mut admin = options.connect().await.unwrap();
    admin
        .execute(format!("CREATE DATABASE {name}").as_str())
        .await
        .unwrap();
    Some(options.database(&name))
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
        let url = format!("ws://{address}/api/v1/ws");
        let (socket, _) = connect_async(url).await.unwrap();
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
        let name = name.to_string();
        let password = password.map(str::to_string);
        let lobby = self
            .expect_lobby(|request_id| ClientMessage::CreateLobby {
                request_id,
                name,
                password,
                seats,
                points_to_win: None,
                bot_difficulty: None,
            })
            .await;
        lobby.id
    }

    pub async fn join(&mut self, lobby: LobbyId, password: Option<&str>) -> ServerMessage {
        let password = password.map(str::to_string);
        self.request(|request_id| ClientMessage::JoinLobby {
            request_id,
            lobby,
            password,
        })
        .await
    }
}
