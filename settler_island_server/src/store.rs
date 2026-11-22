use std::collections::BTreeMap;
use std::future::Future;
use std::sync::Mutex;

use settler_island_bot::Difficulty;
use settler_island_game::{Action, Event, GameSettings, Seat};
use settler_island_protocol::UserId;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct GameId(pub u64);

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SeatPlayer {
    Human(UserId),
    Bot(Difficulty),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewGame {
    pub settings: GameSettings,
    pub seats: Vec<SeatPlayer>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StoredAction {
    pub index: u32,
    pub seat: Seat,
    pub action: Action,
    pub events: Vec<Event>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StoredGame {
    pub id: GameId,
    pub game: NewGame,
    pub actions: Vec<StoredAction>,
}

#[derive(Debug, thiserror::Error)]
pub enum StoreError {
    #[error("game {0:?} is unknown or finished")]
    UnknownGame(GameId),
    #[error("action index {got} does not follow the stored {expected}")]
    OutOfOrder { expected: u32, got: u32 },
    #[error("the store lock is poisoned")]
    Poisoned,
}

/// Durable game log: a lobby writes each action here before anyone sees its events.
pub trait GameStore: Send + Sync + 'static {
    fn create_game(&self, game: NewGame)
        -> impl Future<Output = Result<GameId, StoreError>> + Send;

    fn append_action(
        &self,
        game: GameId,
        action: StoredAction,
    ) -> impl Future<Output = Result<(), StoreError>> + Send;

    fn load_running(&self) -> impl Future<Output = Result<Vec<StoredGame>, StoreError>> + Send;

    fn finish(
        &self,
        game: GameId,
        winner: Seat,
    ) -> impl Future<Output = Result<(), StoreError>> + Send;
}

/// Keeps running games in memory; finished games are dropped.
#[derive(Debug, Default)]
pub struct MemoryStore {
    // A plain mutex is fine: it is never held across an await.
    state: Mutex<MemoryState>,
}

#[derive(Debug, Default)]
struct MemoryState {
    next_id: u64,
    running: BTreeMap<GameId, StoredGame>,
}

impl MemoryStore {
    fn with_state<T>(
        &self,
        change: impl FnOnce(&mut MemoryState) -> Result<T, StoreError>,
    ) -> Result<T, StoreError> {
        let mut state = self.state.lock().map_err(|_| StoreError::Poisoned)?;
        change(&mut state)
    }
}

impl GameStore for MemoryStore {
    async fn create_game(&self, game: NewGame) -> Result<GameId, StoreError> {
        self.with_state(|state| {
            state.next_id += 1;
            let id = GameId(state.next_id);
            let stored = StoredGame {
                id,
                game,
                actions: Vec::new(),
            };
            state.running.insert(id, stored);
            Ok(id)
        })
    }

    async fn append_action(&self, game: GameId, action: StoredAction) -> Result<(), StoreError> {
        self.with_state(|state| {
            let stored = state
                .running
                .get_mut(&game)
                .ok_or(StoreError::UnknownGame(game))?;
            let expected = stored.actions.len() as u32;
            if action.index != expected {
                return Err(StoreError::OutOfOrder {
                    expected,
                    got: action.index,
                });
            }
            stored.actions.push(action);
            Ok(())
        })
    }

    async fn load_running(&self) -> Result<Vec<StoredGame>, StoreError> {
        self.with_state(|state| Ok(state.running.values().cloned().collect()))
    }

    async fn finish(&self, game: GameId, _winner: Seat) -> Result<(), StoreError> {
        self.with_state(|state| {
            state
                .running
                .remove(&game)
                .map(|_| ())
                .ok_or(StoreError::UnknownGame(game))
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn new_game() -> NewGame {
        NewGame {
            settings: GameSettings {
                seats: 3,
                points_to_win: 10,
                seed: 5,
            },
            seats: vec![
                SeatPlayer::Human(UserId("a".to_string())),
                SeatPlayer::Bot(Difficulty::Random),
                SeatPlayer::Bot(Difficulty::Random),
            ],
        }
    }

    fn action(index: u32) -> StoredAction {
        StoredAction {
            index,
            seat: 0,
            action: Action::RollDice,
            events: Vec::new(),
        }
    }

    #[tokio::test]
    async fn running_games_keep_their_actions_in_order_until_finished() {
        let store = MemoryStore::default();
        let first = store.create_game(new_game()).await.unwrap();
        let second = store.create_game(new_game()).await.unwrap();
        assert_ne!(first, second);

        store.append_action(first, action(0)).await.unwrap();
        store.append_action(first, action(1)).await.unwrap();
        let gap = store.append_action(first, action(3)).await;
        assert!(matches!(
            gap,
            Err(StoreError::OutOfOrder {
                expected: 2,
                got: 3
            })
        ));

        let running = store.load_running().await.unwrap();
        assert_eq!(running.len(), 2);
        assert_eq!(running[0].actions, vec![action(0), action(1)]);
        assert_eq!(running[0].game, new_game());

        store.finish(first, 0).await.unwrap();
        let running = store.load_running().await.unwrap();
        assert_eq!(running.len(), 1);
        assert_eq!(running[0].id, second);
        assert!(store.append_action(first, action(2)).await.is_err());
    }
}
