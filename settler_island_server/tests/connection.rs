mod common;

use std::time::Duration;

use common::{start, test_config, Client};
use settler_island_protocol::{ClientMessage, ErrorCode, LobbyId, ServerMessage};
use settler_island_server::Config;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

fn list(request_id: u32) -> ClientMessage {
    ClientMessage::ListLobbies {
        request_id,
        page: 0,
        per_page: 50,
    }
}

async fn error_after_raw(client: &mut Client, text: String) -> (Option<u32>, ErrorCode) {
    client.send_raw(text).await;
    match client.receive().await {
        ServerMessage::Error {
            request_id, code, ..
        } => (request_id, code),
        other => panic!("expected an error, got {other:?}"),
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn forged_and_oversized_messages_get_errors_and_the_connection_stays_usable() {
    let address = start(test_config()).await;
    let (mut client, _) = Client::welcomed(address, "Mallory").await;

    let garbage = error_after_raw(&mut client, "{not json".to_string()).await;
    assert_eq!(garbage, (None, ErrorCode::InvalidMessage));
    let unknown = r#"{"type":"Teleport","request_id":9}"#.to_string();
    let unknown = error_after_raw(&mut client, unknown).await;
    assert_eq!(unknown, (Some(9), ErrorCode::InvalidMessage));
    let bad_action = r#"{"type":"Act","request_id":10,"action":{"type":"WinNow"}}"#.to_string();
    let bad_action = error_after_raw(&mut client, bad_action).await;
    assert_eq!(bad_action, (Some(10), ErrorCode::InvalidMessage));
    let oversized = format!(
        r#"{{"type":"Authenticate","request_id":11,"token":"{}"}}"#,
        "x".repeat(70 * 1024)
    );
    let oversized = error_after_raw(&mut client, oversized).await;
    assert_eq!(oversized, (None, ErrorCode::MessageTooLarge));
    let act = |request_id| ClientMessage::Act {
        request_id,
        action: settler_island_protocol::Action::RollDice,
    };
    assert_eq!(client.expect_error(act).await, ErrorCode::NotInLobby);
    let join = |request_id| ClientMessage::JoinLobby {
        request_id,
        lobby: LobbyId(4242),
        password: None,
    };
    assert_eq!(client.expect_error(join).await, ErrorCode::LobbyNotFound);

    assert!(matches!(
        client.request(list).await,
        ServerMessage::Lobbies { .. }
    ));
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn bursts_above_the_rate_limit_are_refused_until_the_next_second() {
    let address = start(test_config()).await;
    let (mut client, _) = Client::welcomed(address, "Spammer").await;
    tokio::time::sleep(Duration::from_millis(1100)).await;

    let burst = 30;
    for _ in 0..burst {
        client.send(list).await;
    }
    let mut answered = 0;
    let mut limited = 0;
    for _ in 0..burst {
        match client.receive().await {
            ServerMessage::Lobbies { .. } => answered += 1,
            ServerMessage::Error {
                code: ErrorCode::RateLimited,
                ..
            } => limited += 1,
            other => panic!("unexpected {other:?}"),
        }
    }
    assert!(answered >= 20, "the first 20 per second are served");
    assert!(limited >= 1, "the excess is refused");

    tokio::time::sleep(Duration::from_millis(1100)).await;
    assert!(matches!(
        client.request(list).await,
        ServerMessage::Lobbies { .. }
    ));
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn an_idle_connection_is_closed() {
    let config = Config {
        idle_timeout: Duration::from_millis(300),
        ..test_config()
    };
    let address = start(config).await;
    let mut client = Client::connect(address).await;

    assert!(client.closed_by_server().await);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn health_answers_ok() {
    let address = start(test_config()).await;
    let mut stream = TcpStream::connect(address).await.unwrap();
    let request = "GET /api/v1/health HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n";
    stream.write_all(request.as_bytes()).await.unwrap();
    let mut response = String::new();
    stream.read_to_string(&mut response).await.unwrap();

    assert!(response.starts_with("HTTP/1.1 200"), "{response}");
    assert!(response.ends_with(r#"{"status":"ok"}"#), "{response}");
}

/// Many clients creating, joining, leaving, listing and dropping at once must neither hang nor leak lobbies.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn concurrent_lobby_traffic_neither_deadlocks_nor_leaks() {
    let config = Config {
        messages_per_second: 10_000,
        ..test_config()
    };
    let address = start(config).await;
    let clients = 12;
    let rounds = 15;
    let mut tasks = Vec::new();
    for index in 0..clients {
        tasks.push(tokio::spawn(churn(address, index, rounds)));
    }
    let all = async {
        for task in tasks {
            task.await.unwrap();
        }
    };
    tokio::time::timeout(Duration::from_secs(30), all)
        .await
        .expect("concurrent clients hung");

    let (mut observer, _) = Client::welcomed(address, "Observer").await;
    // Disconnect cleanup runs after the socket closes; give it a moment.
    for _ in 0..50 {
        let ServerMessage::Lobbies { total, .. } = observer.request(list).await else {
            panic!("expected Lobbies");
        };
        if total == 0 {
            return;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    panic!("lobbies outlived all their members");
}

async fn churn(address: std::net::SocketAddr, index: u32, rounds: u32) {
    let (mut client, _) = Client::welcomed(address, &format!("Churn{index}")).await;
    for round in 0..rounds {
        let ServerMessage::Lobbies { lobbies, .. } = client.request(list).await else {
            panic!("expected Lobbies");
        };
        let target = lobbies
            .iter()
            .filter(|lobby| !lobby.started && lobby.open_seats > 0)
            .nth((index + round) as usize % 3)
            .map(|lobby| lobby.id);
        let joined = match target {
            Some(lobby) => matches!(
                client.join(lobby, None).await,
                ServerMessage::LobbyState { .. }
            ),
            None => false,
        };
        if !joined {
            client
                .create_lobby(&format!("L{index}-{round}"), 3, None)
                .await;
        }
        if (index + round).is_multiple_of(5) {
            client
                .send(|request_id| ClientMessage::AddBot {
                    request_id,
                    difficulty: settler_island_protocol::Difficulty::Random,
                })
                .await;
        }
        let left = client
            .request(|request_id| ClientMessage::LeaveLobby { request_id })
            .await;
        assert!(matches!(left, ServerMessage::LobbyLeft { .. }), "{left:?}");
    }
    if index.is_multiple_of(2) {
        client
            .create_lobby(&format!("Dropped{index}"), 4, None)
            .await;
    }
}
