mod common;

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use common::{eventually, start_with, test_config, Client, Dealt};
use settler_island_game::{Game, GameSettings, RecordEntry};
use settler_island_protocol::{
    ClientMessage, Difficulty, ErrorCode, LobbyId, ServerMessage, User, UserId, UserKind,
};
use settler_island_server::{
    Config, GameId, GameStore, MemoryIdentityStore, MemoryStore, NewGame, SeatPlayer, StoreError,
    StoredGame,
};

const ABANDON_AFTER: Duration = Duration::from_millis(400);

/// Lets the test read the store the server writes to.
#[derive(Clone, Default)]
struct SharedStore(Arc<MemoryStore>);

impl GameStore for SharedStore {
    async fn create_game(&self, game: NewGame) -> Result<GameId, StoreError> {
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

    async fn finish(&self, game: GameId, winner: u8) -> Result<(), StoreError> {
        self.0.finish(game, winner).await
    }

    async fn abandon(&self, game: GameId) -> Result<(), StoreError> {
        self.0.abandon(game).await
    }

    async fn set_attended(&self, game: GameId, attended: bool) -> Result<(), StoreError> {
        self.0.set_attended(game, attended).await
    }
}

async fn started_game(client: &mut Client, name: &str) -> LobbyId {
    client
        .start_with_bots(name, 3, None, Difficulty::Random)
        .await
        .0
}

/// Deliberate wait: the abandon timer has no event, so elapsed time is the thing under test.
async fn elapse(duration: Duration) {
    tokio::time::sleep(duration).await;
}

async fn lobby_count(client: &mut Client) -> u32 {
    let reply = client
        .request(|request_id| ClientMessage::ListLobbies {
            request_id,
            page: 0,
            per_page: 10,
        })
        .await;
    let ServerMessage::Lobbies { total, .. } = reply else {
        panic!("expected Lobbies, got {reply:?}");
    };
    total
}

async fn running_games(address: SocketAddr) -> u64 {
    let text = reqwest::get(format!("http://{address}/metrics"))
        .await
        .unwrap()
        .text()
        .await
        .unwrap();
    text.lines()
        .find_map(|line| line.strip_prefix("settler_running_games "))
        .and_then(|value| value.parse().ok())
        .unwrap()
}

/// Waits for the seat's turn and makes one accepted move.
async fn move_once(client: &mut Client, dealt: Dealt) {
    let mut legal = dealt.legal_actions;
    loop {
        while legal.is_empty() {
            legal = client.next_game_update().await.1;
        }
        let action = legal[0].clone();
        let reply = client
            .request(|request_id| ClientMessage::Act { request_id, action })
            .await;
        match reply {
            ServerMessage::GameUpdate { .. } => return,
            // A bot moved first; the fresh deal says what is legal now.
            ServerMessage::Error {
                code: ErrorCode::Game { .. },
                ..
            } => {
                client
                    .request(|request_id| ClientMessage::GetState { request_id })
                    .await;
                legal = client.next_game_started().await.legal_actions;
            }
            other => panic!("expected GameUpdate, got {other:?}"),
        }
    }
}

fn unattended_config(unattended_abandon_after: Duration) -> Config {
    Config {
        unattended_abandon_after,
        ..test_config()
    }
}

#[tokio::test]
async fn a_game_no_human_played_is_abandoned_after_the_short_grace() {
    let store = SharedStore::default();
    let config = unattended_config(ABANDON_AFTER);
    let address = start_with(config, store.clone(), MemoryIdentityStore::default()).await;
    let (mut watcher, _) = Client::welcomed(address, "Watcher").await;
    let (mut leaver, _) = Client::welcomed(address, "Leaver").await;
    started_game(&mut leaver, "Left at once").await;
    assert_eq!(running_games(address).await, 1);

    let reply = leaver
        .request(|request_id| ClientMessage::LeaveLobby { request_id })
        .await;
    assert!(matches!(reply, ServerMessage::LobbyLeft { .. }));
    eventually("the unplayed game to be abandoned", || async {
        store.load_running().await.unwrap().is_empty().then_some(())
    })
    .await;

    eventually("the running games gauge to drop", || async {
        (running_games(address).await == 0).then_some(())
    })
    .await;
    assert_eq!(lobby_count(&mut watcher).await, 0);
    assert_eq!(lobby_count(&mut leaver).await, 0);
}

#[tokio::test]
async fn a_game_a_human_played_keeps_the_long_deadline() {
    let store = SharedStore::default();
    let config = unattended_config(ABANDON_AFTER);
    let address = start_with(config, store.clone(), MemoryIdentityStore::default()).await;
    let (mut player, _) = Client::welcomed(address, "Player").await;
    let (_, dealt) = player
        .start_with_bots("Played", 3, None, Difficulty::Random)
        .await;
    move_once(&mut player, dealt).await;

    drop(player);
    eventually("the game to be marked unattended", || async {
        store.load_running().await.unwrap()[0]
            .unattended_for
            .is_some()
            .then_some(())
    })
    .await;
    elapse(ABANDON_AFTER * 3).await;

    assert_eq!(store.load_running().await.unwrap().len(), 1);
    assert_eq!(running_games(address).await, 1);
}

#[tokio::test]
async fn an_unplayed_game_restored_after_its_short_grace_is_abandoned() {
    let store = SharedStore::default();
    let id = store.create_game(stored_game("Unplayed")).await.unwrap();
    store.set_attended(id, false).await.unwrap();
    let grace = Duration::from_secs(1);
    elapse(grace).await;

    start_with(
        unattended_config(grace),
        store.clone(),
        MemoryIdentityStore::default(),
    )
    .await;
    // Well before a fresh short grace would pass.
    elapse(grace / 3).await;

    assert!(store.load_running().await.unwrap().is_empty());
}

#[tokio::test]
async fn a_game_without_a_connected_human_is_abandoned_and_its_lobby_closes() {
    let store = SharedStore::default();
    let config = Config {
        abandon_after: ABANDON_AFTER,
        ..test_config()
    };
    let address = start_with(config, store.clone(), MemoryIdentityStore::default()).await;
    let (mut watcher, _) = Client::welcomed(address, "Watcher").await;
    let (mut present, _) = Client::welcomed(address, "Present").await;
    let (mut leaver, _) = Client::welcomed(address, "Leaver").await;
    started_game(&mut present, "Occupied").await;
    started_game(&mut leaver, "Deserted").await;
    assert_eq!(store.load_running().await.unwrap().len(), 2);

    drop(leaver);
    eventually("the deserted game to be abandoned", || async {
        (store.load_running().await.unwrap().len() == 1).then_some(())
    })
    .await;

    // Only the lobby that still has a human survives, and only its game stays in the store.
    assert_eq!(lobby_count(&mut watcher).await, 1);
    let running = store.load_running().await.unwrap();
    assert_eq!(running.len(), 1);
    assert_eq!(running[0].game.lobby_name, "Occupied");
}

#[tokio::test]
async fn rejoining_before_the_deadline_keeps_the_game() {
    let store = SharedStore::default();
    let config = Config {
        abandon_after: ABANDON_AFTER,
        ..test_config()
    };
    let address = start_with(config, store.clone(), MemoryIdentityStore::default()).await;
    let session = common::guest_session(address, "Ada").await;
    let (mut client, _) = Client::authenticated(address, &session.token).await;
    let lobby = started_game(&mut client, "Brief").await;
    drop(client);
    eventually("the game to be marked unattended", || async {
        store.load_running().await.unwrap()[0]
            .unattended_for
            .is_some()
            .then_some(())
    })
    .await;

    let (mut returning, _) = Client::authenticated(address, &session.token).await;
    returning.try_join(lobby, None).await.unwrap();
    assert_eq!(store.load_running().await.unwrap()[0].unattended_for, None);
    elapse(ABANDON_AFTER * 3).await;

    assert_eq!(store.load_running().await.unwrap().len(), 1);
    assert_eq!(lobby_count(&mut returning).await, 1);
}

#[tokio::test]
async fn time_unattended_before_a_restart_counts_toward_the_deadline() {
    let store = SharedStore::default();
    let id = store
        .create_game(stored_game("Left before the restart"))
        .await
        .unwrap();
    store.set_attended(id, false).await.unwrap();
    let abandon_after = Duration::from_secs(1);
    elapse(abandon_after).await;

    let config = Config {
        abandon_after,
        ..test_config()
    };
    start_with(config, store.clone(), MemoryIdentityStore::default()).await;
    // Well before a fresh deadline would pass.
    elapse(abandon_after / 3).await;

    assert!(store.load_running().await.unwrap().is_empty());
}

/// A game with one human seat and no moves yet.
fn stored_game(name: &str) -> NewGame {
    let human = User {
        id: UserId("guest:ada".to_string()),
        name: "Ada".to_string(),
        kind: UserKind::Guest,
    };
    NewGame {
        settings: GameSettings {
            seats: 3,
            points_to_win: 10,
            seed: 7,
        },
        seats: vec![
            SeatPlayer::Human(human),
            SeatPlayer::Bot(Difficulty::Random),
            SeatPlayer::Bot(Difficulty::Random),
        ],
        lobby: LobbyId(1),
        lobby_name: name.to_string(),
        bot_difficulty: Difficulty::Random,
    }
}
