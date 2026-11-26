mod common;

use common::{start, test_config, Client};
use settler_island_protocol::{
    ClientMessage, Difficulty, ErrorCode, LobbyId, ServerLimit, ServerMessage,
};
use settler_island_server::Config;

/// The attack loop of the review: one lobby after another, started with bots and left to them.
async fn start_and_leave(client: &mut Client, name: &str) -> LobbyId {
    let (lobby, _) = client
        .start_with_bots(name, 3, None, Difficulty::Random)
        .await;
    leave(client).await;
    lobby
}

async fn leave(client: &mut Client) {
    let reply = client
        .request(|request_id| ClientMessage::LeaveLobby { request_id })
        .await;
    let ServerMessage::LobbyLeft { .. } = reply else {
        panic!("expected LobbyLeft, got {reply:?}");
    };
}

/// A full lobby whose start the server refuses.
async fn refused_start(client: &mut Client, name: &str) -> ErrorCode {
    client.create_lobby(name, 3, None).await;
    for _ in 1..3 {
        client
            .expect_lobby(|request_id| ClientMessage::AddBot {
                request_id,
                difficulty: Difficulty::Random,
            })
            .await;
    }
    client
        .expect_error(|request_id| ClientMessage::StartGame { request_id })
        .await
}

async fn listed(client: &mut Client) -> Vec<LobbyId> {
    let reply = client
        .request(|request_id| ClientMessage::ListLobbies {
            request_id,
            page: 0,
            per_page: 10,
        })
        .await;
    let ServerMessage::Lobbies { total, lobbies, .. } = reply else {
        panic!("expected Lobbies, got {reply:?}");
    };
    assert_eq!(total as usize, lobbies.len());
    lobbies.into_iter().map(|summary| summary.info.id).collect()
}

#[tokio::test]
async fn starting_and_leaving_games_in_a_loop_stops_at_the_per_user_cap() {
    let config = Config {
        max_games_per_user: 2,
        ..test_config()
    };
    let address = start(config).await;
    let (mut attacker, _) = Client::welcomed(address, "Mallory").await;
    for round in 0..2 {
        start_and_leave(&mut attacker, &format!("Round {round}")).await;
    }

    let refusal = refused_start(&mut attacker, "One too many").await;

    let expected = ErrorCode::LimitReached {
        limit: ServerLimit::GamesPerUser,
    };
    assert_eq!(refusal, expected);
}

#[tokio::test]
async fn a_start_beyond_the_server_wide_cap_is_refused() {
    let config = Config {
        max_running_games: 2,
        ..test_config()
    };
    let address = start(config).await;
    for player in ["Ada", "Grace"] {
        let (mut client, _) = Client::welcomed(address, player).await;
        start_and_leave(&mut client, player).await;
    }
    let (mut late, _) = Client::welcomed(address, "Late").await;

    let refusal = refused_start(&mut late, "No room").await;

    let expected = ErrorCode::LimitReached {
        limit: ServerLimit::RunningGames,
    };
    assert_eq!(refusal, expected);
}

#[tokio::test]
async fn a_started_lobby_without_members_is_listed_only_to_its_seated_players() {
    let address = start(test_config()).await;
    let (mut watcher, _) = Client::welcomed(address, "Watcher").await;
    let (mut leaver, _) = Client::welcomed(address, "Leaver").await;
    let lobby = start_and_leave(&mut leaver, "Left to the bots").await;

    assert_eq!(listed(&mut watcher).await, Vec::<LobbyId>::new());
    assert_eq!(listed(&mut leaver).await, vec![lobby]);
}
