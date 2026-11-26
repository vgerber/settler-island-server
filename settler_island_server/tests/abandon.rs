mod common;

use std::sync::Arc;
use std::time::Duration;

use common::{eventually, start_with, test_config, Client};
use settler_island_game::{Game, GameSettings};
use settler_island_protocol::{
    ClientMessage, Difficulty, LobbyId, ServerMessage, User, UserId, UserKind,
};
use settler_island_server::{
    Config, GameId, GameStore, MemoryIdentityStore, MemoryStore, NewGame, SeatPlayer, StoreError,
    StoredAction, StoredGame,
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
        action: StoredAction,
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
    let human = User {
        id: UserId("guest:ada".to_string()),
        name: "Ada".to_string(),
        kind: UserKind::Guest,
    };
    let game = NewGame {
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
        lobby_name: "Left before the restart".to_string(),
        bot_difficulty: Difficulty::Random,
    };
    let id = store.create_game(game).await.unwrap();
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
