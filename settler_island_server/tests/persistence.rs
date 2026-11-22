mod common;

use std::time::Duration;

use common::{guest_session, start_with, test_config, test_database, Client};
use settler_island_bot::{create_bot, Bot};
use settler_island_game::{Action, Game, GameRecord, GameSettings, Phase, PlayerView, Seat};
use settler_island_protocol::{
    ClientMessage, Difficulty, ErrorCode, LobbyId, ServerMessage, User, UserId, UserKind,
};
use settler_island_server::{
    Config, GameId, GameStore, IdentityStore, MemoryIdentityStore, NewGame, PostgresStore,
    SeatPlayer, StoreError, StoredAction, StoredGame, SNAPSHOT_INTERVAL,
};
use sqlx::ConnectOptions;
use tokio::runtime::Runtime;

const SEED: u64 = 23;
const POINTS_TO_WIN: u8 = 6;
/// Past the first snapshot, so the restart replays snapshot plus tail.
const ACTIONS_BEFORE_CRASH: usize = SNAPSHOT_INTERVAL as usize + 15;
const MAX_UPDATES: usize = 5000;

fn new_game() -> NewGame {
    NewGame {
        settings: GameSettings {
            seats: 3,
            points_to_win: 10,
            seed: 5,
        },
        seats: vec![
            SeatPlayer::Bot(Difficulty::Random),
            SeatPlayer::Human(User {
                id: UserId("guest-1".to_string()),
                name: "Ada".to_string(),
                kind: UserKind::Guest,
            }),
            SeatPlayer::Bot(Difficulty::Heuristic),
        ],
        lobby: LobbyId(7),
        lobby_name: "Harbour".to_string(),
        bot_difficulty: Difficulty::Heuristic,
    }
}

#[tokio::test]
async fn postgres_snapshot_plus_replay_equals_the_live_game() {
    let Some(options) = test_database("postgres_snapshot_plus_replay_equals_the_live_game").await
    else {
        return;
    };
    let store = PostgresStore::connect(options).await.unwrap();
    let id = store.create_game(new_game()).await.unwrap();
    let mut live = Game::new(new_game().settings).unwrap();
    let mut record = GameRecord::new(&live);
    for index in 0..2 * SNAPSHOT_INTERVAL + 9 {
        let seat = live.pending_seats()[0];
        let action = live.legal_actions(seat).pop().unwrap();
        let events = live.apply(seat, action.clone()).unwrap();
        record.push(seat, action.clone(), events.clone());
        let snapshot = (index + 1)
            .is_multiple_of(SNAPSHOT_INTERVAL)
            .then(|| live.clone());
        let stored = StoredAction {
            index,
            seat,
            action,
            events,
        };
        store.append_action(id, stored, snapshot).await.unwrap();
    }
    let duplicate = StoredAction {
        index: 3,
        seat: 0,
        action: Action::RollDice,
        events: Vec::new(),
    };
    let rejected = store.append_action(id, duplicate, None).await;
    assert!(matches!(
        rejected,
        Err(StoreError::OutOfOrder { got: 3, .. })
    ));

    let stored: StoredGame = store.load_running().await.unwrap().remove(0);
    assert_eq!(stored.game, new_game());
    assert_eq!(
        stored.snapshot.as_ref().map(|snapshot| snapshot.actions),
        Some(2 * SNAPSHOT_INTERVAL)
    );
    let (game, rebuilt_record) = stored.rebuild().unwrap();
    assert_eq!(game, live);
    assert_eq!(rebuilt_record, record);

    store.finish(id, 1).await.unwrap();
    assert!(store.load_running().await.unwrap().is_empty());
    let late = StoredAction {
        index: 2 * SNAPSHOT_INTERVAL + 9,
        seat: 0,
        action: Action::RollDice,
        events: Vec::new(),
    };
    let after_finish = store.append_action(id, late, None).await;
    assert!(matches!(after_finish, Err(StoreError::UnknownGame(_))));
}

#[tokio::test]
async fn postgres_abandoned_games_are_kept_but_not_restored() {
    let Some(options) = test_database("postgres_abandoned_games_are_kept_but_not_restored").await
    else {
        return;
    };
    let store = PostgresStore::connect(options.clone()).await.unwrap();
    let abandoned = store.create_game(new_game()).await.unwrap();
    let running = store.create_game(new_game()).await.unwrap();

    store.abandon(abandoned).await.unwrap();

    let restored = store.load_running().await.unwrap();
    assert_eq!(restored.len(), 1);
    assert_eq!(restored[0].id, running);
    let mut connection = options.connect().await.unwrap();
    let status: String = sqlx::query_scalar("SELECT status FROM games WHERE id = $1")
        .bind(i64::try_from(abandoned.0).unwrap())
        .fetch_one(&mut connection)
        .await
        .unwrap();
    assert_eq!(status, "abandoned");
    assert!(matches!(
        store.abandon(abandoned).await,
        Err(StoreError::UnknownGame(_))
    ));
    assert!(matches!(
        store.finish(abandoned, 0).await,
        Err(StoreError::UnknownGame(_))
    ));
}

#[tokio::test]
async fn postgres_identity_links_keep_the_first_user() {
    let Some(options) = test_database("postgres_identity_links_keep_the_first_user").await else {
        return;
    };
    let store = PostgresStore::connect(options).await.unwrap();
    let first = UserId("guest-first".to_string());
    let second = UserId("guest-second".to_string());

    assert_eq!(store.linked_user("subject").await.unwrap(), None);
    assert_eq!(store.link("subject", &first).await.unwrap(), first);
    assert_eq!(store.link("subject", &second).await.unwrap(), first);
    assert_eq!(store.linked_user("subject").await.unwrap(), Some(first));
    assert_eq!(store.linked_user("other").await.unwrap(), None);
}

/// Accepts games but fails every action write.
struct RejectingStore;

impl GameStore for RejectingStore {
    async fn create_game(&self, _game: NewGame) -> Result<GameId, StoreError> {
        Ok(GameId(1))
    }

    async fn append_action(
        &self,
        game: GameId,
        _action: StoredAction,
        _snapshot: Option<Game>,
    ) -> Result<(), StoreError> {
        Err(StoreError::UnknownGame(game))
    }

    async fn load_running(&self) -> Result<Vec<StoredGame>, StoreError> {
        Ok(Vec::new())
    }

    async fn finish(&self, _game: GameId, _winner: Seat) -> Result<(), StoreError> {
        Ok(())
    }

    async fn abandon(&self, _game: GameId) -> Result<(), StoreError> {
        Ok(())
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn an_action_the_store_rejects_is_never_broadcast() {
    let address = start_with(
        test_config(),
        RejectingStore,
        MemoryIdentityStore::default(),
    )
    .await;
    let (mut client, _) = Client::welcomed(address, "Ada").await;
    client.create_lobby("Unlucky", 3, None).await;
    for _ in 0..2 {
        client
            .expect_lobby(|request_id| ClientMessage::AddBot {
                request_id,
                difficulty: Difficulty::Random,
            })
            .await;
    }
    let started = client
        .request(|request_id| ClientMessage::StartGame { request_id })
        .await;
    let ServerMessage::LobbyState { .. } = started else {
        panic!("expected LobbyState, got {started:?}");
    };
    let (view, legal) = next_game_started(&mut client).await;
    let action = legal[0].clone();

    let act = client
        .send(|request_id| ClientMessage::Act { request_id, action })
        .await;
    // The very next message: an update sent before the store refused would arrive first.
    match client.receive().await {
        ServerMessage::Error {
            request_id, code, ..
        } => {
            assert_eq!(request_id, Some(act));
            assert_eq!(code, ErrorCode::Internal);
        }
        other => panic!("expected the store error, got {other:?}"),
    }
    client
        .send(|request_id| ClientMessage::GetState { request_id })
        .await;
    let (view_after, _) = next_game_started(&mut client).await;
    assert_eq!(view_after, view);
}

async fn next_game_started(client: &mut Client) -> (PlayerView, Vec<Action>) {
    loop {
        if let ServerMessage::GameStarted {
            view,
            legal_actions,
            ..
        } = client.receive().await
        {
            return (view, legal_actions);
        }
    }
}

/// Plays with `human` until the game finishes, or until `stop_after` updates arrived and it is the human's
/// turn (so the bots wait); returns the update count.
async fn play(
    client: &mut Client,
    human: &mut dyn Bot,
    view: &mut PlayerView,
    mut legal: Vec<Action>,
    stop_after: usize,
) -> usize {
    let mut outstanding: Option<u32> = None;
    let mut updates = 0;
    while !matches!(view.phase, Phase::Finished { .. }) {
        let human_to_move = outstanding.is_none() && !legal.is_empty();
        if updates >= stop_after && human_to_move {
            break;
        }
        if human_to_move {
            let action = human.choose(view, &legal);
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
                *view = next_view;
                legal = legal_actions;
                updates += 1;
            }
            // A move chosen from an update that bots overtook meanwhile.
            ServerMessage::Error {
                request_id,
                code: ErrorCode::Game { .. },
                ..
            } if request_id.is_some() && request_id == outstanding => outstanding = None,
            ServerMessage::LobbyState { .. } => {}
            other => panic!("unexpected message during play: {other:?}"),
        }
    }
    updates
}

fn server_runtime() -> Runtime {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .unwrap()
}

#[test]
fn a_game_survives_a_server_restart_and_finishes_like_an_uninterrupted_replay() {
    let client_runtime = server_runtime();
    let Some(options) = client_runtime.block_on(test_database(
        "a_game_survives_a_server_restart_and_finishes_like_an_uninterrupted_replay",
    )) else {
        return;
    };
    let config = Config {
        seed: Some(SEED),
        messages_per_second: 10_000,
        ..test_config()
    };
    let server_a = server_runtime();
    let address_a = server_a.block_on(async {
        let store = PostgresStore::connect(options.clone()).await.unwrap();
        start_with(config.clone(), store.clone(), store).await
    });

    let mut human = create_bot(Difficulty::Heuristic, 77);
    let (token, lobby, played_before) = client_runtime.block_on(async {
        let session = guest_session(address_a, "Ada").await;
        let (mut client, _) = Client::authenticated(address_a, &session.token).await;
        let lobby = start_game(&mut client).await;
        let (mut view, legal) = next_game_started(&mut client).await;
        let played = play(
            &mut client,
            human.as_mut(),
            &mut view,
            legal,
            ACTIONS_BEFORE_CRASH,
        )
        .await;
        assert!(
            !matches!(view.phase, Phase::Finished { .. }),
            "the game must still run when the server dies"
        );
        (session.token, lobby, played)
    });
    // A crash: every task of server A stops mid-flight.
    drop(server_a);

    let server_b = server_runtime();
    let address_b = server_b.block_on(async {
        let store = PostgresStore::connect(options.clone()).await.unwrap();
        start_with(config.clone(), store.clone(), store).await
    });
    let record = client_runtime.block_on(async {
        let (mut client, user) = Client::authenticated(address_b, &token).await;
        assert_eq!(user.name, "Ada");
        let joined = client.join(lobby, None).await;
        let ServerMessage::LobbyState { lobby: details, .. } = joined else {
            panic!("rejoining after the restart failed: {joined:?}");
        };
        assert!(details.started);
        let (mut view, legal) = next_game_started(&mut client).await;
        let finish = play(&mut client, human.as_mut(), &mut view, legal, MAX_UPDATES);
        tokio::time::timeout(Duration::from_secs(60), finish)
            .await
            .expect("the restored game did not finish in time");
        assert!(matches!(view.phase, Phase::Finished { .. }));
        let reply = client
            .request(|request_id| ClientMessage::GetRecord { request_id })
            .await;
        let ServerMessage::Record { record, .. } = reply else {
            panic!("expected Record, got {reply:?}");
        };
        record
    });
    assert!(record.entries.len() > played_before);

    let settings = GameSettings {
        seats: 4,
        points_to_win: POINTS_TO_WIN,
        seed: SEED,
    };
    let mut replayed = Game::new(settings).unwrap();
    let mut expected = GameRecord::new(&replayed);
    for entry in &record.entries {
        let events = replayed.apply(entry.seat, entry.action.clone()).unwrap();
        expected.push(entry.seat, entry.action.clone(), events);
    }
    assert_eq!(record, expected);
    assert!(matches!(replayed.phase(), Phase::Finished { .. }));
}

/// Creates a 4-seat lobby with three heuristic bots and starts it.
async fn start_game(client: &mut Client) -> LobbyId {
    let password = None;
    let lobby = client
        .expect_lobby(|request_id| ClientMessage::CreateLobby {
            request_id,
            name: "Restart".to_string(),
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
                difficulty: Difficulty::Heuristic,
            })
            .await;
    }
    client
        .send(|request_id| ClientMessage::StartGame { request_id })
        .await;
    lobby.id
}
