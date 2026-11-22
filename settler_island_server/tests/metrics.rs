mod common;

use std::net::SocketAddr;
use std::time::Duration;

use common::{start, test_config, Client};
use settler_island_protocol::{ClientMessage, Difficulty, ErrorCode, ServerMessage};

async fn scrape(address: SocketAddr) -> String {
    reqwest::get(format!("http://{address}/metrics"))
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .text()
        .await
        .unwrap()
}

/// The value of the sample line that starts with `series`, 0 while the series is absent.
fn sample(text: &str, series: &str) -> u64 {
    text.lines()
        .filter_map(|line| line.strip_prefix(series))
        .filter_map(|rest| rest.strip_prefix(' '))
        .find_map(|value| value.parse().ok())
        .unwrap_or(0)
}

async fn wait_for(address: SocketAddr, series: &str, at_least: u64) -> String {
    for _ in 0..100 {
        let text = scrape(address).await;
        if sample(&text, series) >= at_least {
            return text;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    panic!("{series} never reached {at_least}");
}

#[tokio::test]
async fn metrics_follow_connections_lobbies_errors_and_play() {
    let address = start(test_config()).await;
    let before = scrape(address).await;
    assert_eq!(sample(&before, "settler_connections"), 0);
    assert_eq!(sample(&before, "settler_actions_applied_total"), 0);

    let (mut client, _) = Client::welcomed(address, "Ada").await;
    let code = client
        .expect_error(|request_id| ClientMessage::LeaveLobby { request_id })
        .await;
    assert_eq!(code, ErrorCode::NotInLobby);
    client.create_lobby("Table", 3, None).await;
    for _ in 0..2 {
        client
            .expect_lobby(|request_id| ClientMessage::AddBot {
                request_id,
                difficulty: Difficulty::Random,
            })
            .await;
    }
    client
        .send(|request_id| ClientMessage::StartGame { request_id })
        .await;
    let mut legal = loop {
        if let ServerMessage::GameStarted { legal_actions, .. } = client.receive().await {
            break legal_actions;
        }
    };
    // The setup turn takes a settlement and a road before the bots move.
    for _ in 0..2 {
        let action = legal.into_iter().next().unwrap();
        client
            .send(|request_id| ClientMessage::Act { request_id, action })
            .await;
        legal = loop {
            if let ServerMessage::GameUpdate { legal_actions, .. } = client.receive().await {
                break legal_actions;
            }
        };
    }

    let text = wait_for(address, "settler_bot_actions_total", 1).await;
    assert_eq!(sample(&text, "settler_connections"), 1);
    assert_eq!(sample(&text, "settler_authenticated_connections"), 1);
    assert_eq!(sample(&text, "settler_lobbies"), 1);
    assert_eq!(sample(&text, "settler_running_games"), 1);
    assert!(sample(&text, "settler_actions_applied_total") >= 2);
    assert_eq!(
        sample(&text, "settler_errors_total{code=\"NotInLobby\"}"),
        1
    );
}
