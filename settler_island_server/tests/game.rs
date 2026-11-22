mod common;

use std::time::Duration;

use common::{start, test_config, Client};
use settler_island_bot::create_bot;
use settler_island_game::{replay, Action, GameSettings, Phase, PlayerView, Seat};
use settler_island_protocol::{ClientMessage, Difficulty, ErrorCode, ServerMessage};
use settler_island_server::Config;

const SEED: u64 = 11;
/// The lowest goal the rules allow, so random play finishes in a few hundred actions.
const POINTS_TO_WIN: u8 = 3;
/// Some random games wander; another attempt with a different human trajectory is cheap.
const ATTEMPTS: u64 = 8;
const MAX_UPDATES_PER_ATTEMPT: u32 = 1500;

struct Finished {
    seat: Seat,
    view: PlayerView,
    actions: Vec<(Seat, Action)>,
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn one_human_and_three_bots_play_a_seeded_game_to_a_win() {
    let config = Config {
        seed: Some(SEED),
        messages_per_second: 10_000,
        ..test_config()
    };
    let address = start(config).await;
    let play = async {
        for attempt in 0..ATTEMPTS {
            if let Some(finished) = play_once(address, attempt).await {
                return finished;
            }
        }
        panic!("no game finished in {ATTEMPTS} attempts");
    };
    let finished = tokio::time::timeout(Duration::from_secs(45), play)
        .await
        .expect("the game did not finish in time");

    let Phase::Finished { winner } = finished.view.phase else {
        panic!("the last update must show the finished game");
    };
    assert_eq!(finished.view.own.map(|own| own.seat), Some(finished.seat));
    let settings = GameSettings {
        seats: 4,
        points_to_win: POINTS_TO_WIN,
        seed: SEED,
    };
    let replayed = replay(settings, &finished.actions).expect("the record replays");
    assert_eq!(replayed.phase(), &Phase::Finished { winner });
    // The human's view hides other seats' victory point cards, so check the winner's own total.
    let winner_view = replayed.view(Some(winner));
    assert!(winner_view.players[usize::from(winner)].points >= POINTS_TO_WIN);
}

/// Plays one game with the random bot logic for the human; `None` when it runs too long.
async fn play_once(address: std::net::SocketAddr, attempt: u64) -> Option<Finished> {
    let (mut client, _) = Client::welcomed(address, "Human").await;
    let password = None;
    client
        .expect_lobby(|request_id| ClientMessage::CreateLobby {
            request_id,
            name: "Seeded".to_string(),
            password,
            seats: 4,
            points_to_win: Some(POINTS_TO_WIN),
            bot_difficulty: None,
        })
        .await;
    for _ in 0..3 {
        client
            .expect_lobby(|request_id| ClientMessage::AddBot {
                request_id,
                difficulty: Difficulty::Random,
            })
            .await;
    }
    let start_id = client
        .send(|request_id| ClientMessage::StartGame { request_id })
        .await;
    let (seat, mut view, mut legal) = loop {
        if let ServerMessage::GameStarted {
            request_id: Some(id),
            seat,
            view,
            legal_actions,
        } = client.receive().await
        {
            assert_eq!(id, start_id);
            break (seat, view, legal_actions);
        }
    };

    let mut human = create_bot(Difficulty::Random, 1000 + attempt);
    let mut outstanding: Option<u32> = None;
    for _ in 0..MAX_UPDATES_PER_ATTEMPT {
        if outstanding.is_none() && !legal.is_empty() {
            let action = human.choose(&view, &legal);
            outstanding = Some(
                client
                    .send(|request_id| ClientMessage::Act { request_id, action })
                    .await,
            );
        }
        match client.receive().await {
            ServerMessage::GameUpdate {
                request_id,
                view: next_view,
                legal_actions,
                ..
            } => {
                if request_id.is_some() && request_id == outstanding {
                    outstanding = None;
                }
                view = next_view;
                legal = legal_actions;
            }
            // A move chosen from an update that bots overtook meanwhile; the next update brings a fresh list.
            ServerMessage::Error {
                request_id,
                code: ErrorCode::Game { .. },
                ..
            } if request_id.is_some() && request_id == outstanding => outstanding = None,
            other => panic!("unexpected message during play: {other:?}"),
        }
        if matches!(view.phase, Phase::Finished { .. }) {
            let actions = full_record(&mut client).await;
            return Some(Finished {
                seat,
                view,
                actions,
            });
        }
    }
    client
        .request(|request_id| ClientMessage::LeaveLobby { request_id })
        .await;
    None
}

async fn full_record(client: &mut Client) -> Vec<(Seat, Action)> {
    let reply = client
        .request(|request_id| ClientMessage::GetRecord { request_id })
        .await;
    let ServerMessage::Record { record, .. } = reply else {
        panic!("expected Record, got {reply:?}");
    };
    record
        .entries
        .into_iter()
        .map(|entry| (entry.seat, entry.action))
        .collect()
}
