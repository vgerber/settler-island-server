mod common;

use std::time::Duration;

use common::{guest_session, play_as, start_with, test_config, test_database, Client, Play};
use settler_island_bot::create_bot;
use settler_island_game::{
    replay, Action, Game, GameRecord, GameSettings, Phase, RecordEntry, Seat,
};
use settler_island_protocol::{
    ClientMessage, Difficulty, ErrorCode, LobbyId, ServerMessage, User, UserId, UserKind,
};
use settler_island_server::{
    wants_snapshot, Config, GameId, GameStore, IdentityStore, MemoryIdentityStore, NewGame,
    PostgresStore, SeatPlayer, StoreError, StoredGame, SNAPSHOT_INTERVAL,
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
    let Some(database) = test_database().await else {
        return;
    };
    let options = database.options();
    let store = PostgresStore::connect(options).await.unwrap();
    let id = store.create_game(new_game()).await.unwrap();
    let mut live = Game::new(new_game().settings).unwrap();
    let mut record = GameRecord::new(&live);
    for index in 0..2 * SNAPSHOT_INTERVAL + 9 {
        let seat = live.pending_seats()[0];
        let action = live.legal_actions(seat).pop().unwrap();
        let events = live.apply(seat, action.clone()).unwrap();
        record.push(seat, action.clone(), events.clone());
        let snapshot = wants_snapshot(index).then(|| live.clone());
        let stored = RecordEntry {
            index,
            seat,
            action,
            events,
        };
        store.append_action(id, stored, snapshot).await.unwrap();
    }
    let duplicate = RecordEntry {
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
    let late = RecordEntry {
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
    let Some(database) = test_database().await else {
        return;
    };
    let options = database.options();
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
async fn postgres_unattended_time_survives_a_reload_and_is_cleared_on_return() {
    let Some(database) = test_database().await else {
        return;
    };
    let options = database.options();
    let store = PostgresStore::connect(options.clone()).await.unwrap();
    let id = store.create_game(new_game()).await.unwrap();
    assert_eq!(store.load_running().await.unwrap()[0].unattended_for, None);

    store.set_attended(id, false).await.unwrap();
    let mut connection = options.connect().await.unwrap();
    sqlx::query("UPDATE games SET unattended_since = now() - interval '2 hours' WHERE id = $1")
        .bind(i64::try_from(id.0).unwrap())
        .execute(&mut connection)
        .await
        .unwrap();
    // Marking it unattended again (as a restore does) keeps the earlier time.
    store.set_attended(id, false).await.unwrap();
    let unattended = store.load_running().await.unwrap()[0].unattended_for;
    assert!(unattended.is_some_and(|duration| duration >= Duration::from_secs(7200)));

    store.set_attended(id, true).await.unwrap();
    assert_eq!(store.load_running().await.unwrap()[0].unattended_for, None);
    store.abandon(id).await.unwrap();
    assert!(matches!(
        store.set_attended(id, false).await,
        Err(StoreError::UnknownGame(_))
    ));
}

#[tokio::test]
async fn postgres_identity_links_keep_the_first_user() {
    let Some(database) = test_database().await else {
        return;
    };
    let options = database.options();
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
        _action: RecordEntry,
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

    async fn set_attended(&self, _game: GameId, _attended: bool) -> Result<(), StoreError> {
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
    let (_, dealt) = client
        .start_with_bots("Unlucky", 3, None, Difficulty::Random)
        .await;
    let (view, legal) = (dealt.view, dealt.legal_actions);
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
    assert_eq!(client.next_game_started().await.view, view);
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
    let Some(database) = client_runtime.block_on(test_database()) else {
        return;
    };
    let options = database.options();
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
        let (lobby, dealt) = client
            .start_with_bots("Restart", 4, Some(POINTS_TO_WIN), Difficulty::Heuristic)
            .await;
        let mut play = Play::new(dealt.view, dealt.legal_actions);
        play_as(&mut client, human.as_mut(), &mut play, |play| {
            play.finished() || (play.updates >= ACTIONS_BEFORE_CRASH && play.to_move())
        })
        .await;
        assert!(
            !play.finished(),
            "the game must still run when the server dies"
        );
        (session.token, lobby, play.updates)
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
        let details = client
            .try_join(lobby, None)
            .await
            .expect("rejoining after the restart failed");
        assert!(details.started);
        let dealt = client.next_game_started().await;
        let mut play = Play::new(dealt.view, dealt.legal_actions);
        let finish = play_as(&mut client, human.as_mut(), &mut play, |play| {
            play.finished() || (play.updates >= MAX_UPDATES && play.to_move())
        });
        tokio::time::timeout(Duration::from_secs(60), finish)
            .await
            .expect("the restored game did not finish in time");
        assert!(play.finished());
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
    let replayed = replay(Game::new(settings).unwrap(), &record.entries).unwrap();
    assert!(matches!(replayed.phase(), Phase::Finished { .. }));
}

#[tokio::test]
async fn postgres_refuses_a_lobby_id_its_column_cannot_hold() {
    let Some(database) = test_database().await else {
        return;
    };
    let store = PostgresStore::connect(database.options()).await.unwrap();
    let mut game = new_game();
    game.lobby = LobbyId(u32::MAX);

    let result = store.create_game(game).await;

    assert!(matches!(
        result,
        Err(StoreError::OutOfRange { field: "lobby id" })
    ));
    assert!(store.load_running().await.unwrap().is_empty());
}

#[tokio::test]
async fn postgres_names_the_raw_row_and_field_of_an_out_of_range_value() {
    let Some(database) = test_database().await else {
        return;
    };
    let options = database.options();
    let store = PostgresStore::connect(options.clone()).await.unwrap();
    let id = store.create_game(new_game()).await.unwrap();
    let mut connection = options.connect().await.unwrap();
    let row = i64::try_from(id.0).unwrap();
    sqlx::query("UPDATE games SET lobby_id = -1 WHERE id = $1")
        .bind(row)
        .execute(&mut connection)
        .await
        .unwrap();

    let result = store.load_running().await;

    assert!(matches!(
        result,
        Err(StoreError::Corrupt { row: found, field: "lobby id" }) if found == row
    ));
}
