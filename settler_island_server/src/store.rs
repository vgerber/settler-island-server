use std::collections::BTreeMap;
use std::future::Future;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use settler_island_bot::Difficulty;
use settler_island_game::{
    replay, Game, GameError, GameRecord, GameSettings, RecordEntry, ReplayError, Seat,
};
use settler_island_protocol::{AwayPolicy, LobbyId};

use crate::identity::Player;

/// A snapshot every this many actions bounds the replay work of a restart.
pub const SNAPSHOT_INTERVAL: u32 = 50;

/// Whether the state after the action at `index` is stored as a snapshot.
pub fn wants_snapshot(index: u32) -> bool {
    (index + 1).is_multiple_of(SNAPSHOT_INTERVAL)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct GameId(pub u64);

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SeatPlayer {
    Human(Player),
    Bot(Difficulty),
}

/// A game as it starts, plus what a restart needs to recreate its lobby.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewGame {
    pub settings: GameSettings,
    pub seats: Vec<SeatPlayer>,
    pub lobby: LobbyId,
    pub lobby_name: String,
    /// Plays for humans who are away.
    pub bot_difficulty: Difficulty,
    /// What a seat whose human is away does.
    pub away_policy: AwayPolicy,
}

/// The game state after the first `actions` actions.
#[derive(Debug, Clone, PartialEq)]
pub struct Snapshot {
    pub actions: u32,
    pub state: Game,
}

#[derive(Debug, Clone, PartialEq)]
pub struct StoredGame {
    pub id: GameId,
    pub game: NewGame,
    /// Every action so far, in order.
    pub actions: Vec<RecordEntry>,
    /// The latest snapshot, if any.
    pub snapshot: Option<Snapshot>,
    /// How long no human has been connected; `None` while one is.
    pub unattended_for: Option<Duration>,
}

#[derive(Debug, thiserror::Error)]
pub enum RebuildError {
    #[error(transparent)]
    Game(#[from] GameError),
    #[error(transparent)]
    Replay(#[from] ReplayError),
    #[error("the snapshot covers {snapshot} actions but only {stored} are stored")]
    SnapshotBeyondLog { snapshot: u32, stored: u32 },
}

impl StoredGame {
    /// The live game (latest snapshot plus the later actions) and its full record.
    pub fn rebuild(&self) -> Result<(Game, GameRecord), RebuildError> {
        let initial = Game::new(self.game.settings.clone())?;
        // The record starts from the empty board, not the snapshot's.
        let mut record = GameRecord::new(&initial);
        let (game, replay_from) = match &self.snapshot {
            Some(snapshot) => (snapshot.state.clone(), snapshot.actions),
            None => (initial, 0),
        };
        let stored = self.actions.len() as u32;
        if replay_from > stored {
            return Err(RebuildError::SnapshotBeyondLog {
                snapshot: replay_from,
                stored,
            });
        }
        let game = replay(game, &self.actions[replay_from as usize..])?;
        for entry in &self.actions {
            record.push_entry(entry.clone());
        }
        Ok((game, record))
    }
}

#[derive(Debug, thiserror::Error)]
pub enum StoreError {
    #[error("game {0:?} is unknown or finished")]
    UnknownGame(GameId),
    #[error("action index {got} does not follow the stored {expected}")]
    OutOfOrder { expected: u32, got: u32 },
    #[error("the store lock is poisoned")]
    Poisoned,
    #[error("database: {0}")]
    Database(#[from] sqlx::Error),
    #[error("database migration: {0}")]
    Migration(#[from] sqlx::migrate::MigrateError),
    #[error("database row {row} has a stored {field} out of range")]
    Corrupt { row: i64, field: &'static str },
    #[error("{field} does not fit its database column")]
    OutOfRange { field: &'static str },
}

/// Durable game log: a lobby writes each action here before anyone sees its events.
pub trait GameStore: Send + Sync + 'static {
    fn create_game(&self, game: NewGame)
        -> impl Future<Output = Result<GameId, StoreError>> + Send;

    /// Stores `action`, plus `snapshot` (the state after it) when given, in one step.
    fn append_action(
        &self,
        game: GameId,
        action: RecordEntry,
        snapshot: Option<Game>,
    ) -> impl Future<Output = Result<(), StoreError>> + Send;

    fn load_running(&self) -> impl Future<Output = Result<Vec<StoredGame>, StoreError>> + Send;

    fn finish(
        &self,
        game: GameId,
        winner: Seat,
    ) -> impl Future<Output = Result<(), StoreError>> + Send;

    /// Closes a running game nobody returned to; it is never restored.
    fn abandon(&self, game: GameId) -> impl Future<Output = Result<(), StoreError>> + Send;

    /// Records whether a human is connected; an unattended game keeps the time it was first left alone.
    fn set_attended(
        &self,
        game: GameId,
        attended: bool,
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
    unattended_since: BTreeMap<GameId, Instant>,
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

impl MemoryStore {
    fn drop_running(&self, game: GameId) -> Result<(), StoreError> {
        self.with_state(|state| {
            state.unattended_since.remove(&game);
            state
                .running
                .remove(&game)
                .map(|_| ())
                .ok_or(StoreError::UnknownGame(game))
        })
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
                snapshot: None,
                unattended_for: None,
            };
            state.running.insert(id, stored);
            Ok(id)
        })
    }

    async fn append_action(
        &self,
        game: GameId,
        action: RecordEntry,
        snapshot: Option<Game>,
    ) -> Result<(), StoreError> {
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
            if let Some(state) = snapshot {
                stored.snapshot = Some(Snapshot {
                    actions: action.index + 1,
                    state,
                });
            }
            stored.actions.push(action);
            Ok(())
        })
    }

    async fn load_running(&self) -> Result<Vec<StoredGame>, StoreError> {
        self.with_state(|state| {
            let games = state.running.values().map(|stored| StoredGame {
                unattended_for: state.unattended_since.get(&stored.id).map(Instant::elapsed),
                ..stored.clone()
            });
            Ok(games.collect())
        })
    }

    async fn finish(&self, game: GameId, _winner: Seat) -> Result<(), StoreError> {
        self.drop_running(game)
    }

    async fn abandon(&self, game: GameId) -> Result<(), StoreError> {
        self.drop_running(game)
    }

    async fn set_attended(&self, game: GameId, attended: bool) -> Result<(), StoreError> {
        self.with_state(|state| {
            if !state.running.contains_key(&game) {
                return Err(StoreError::UnknownGame(game));
            }
            if attended {
                state.unattended_since.remove(&game);
            } else {
                state
                    .unattended_since
                    .entry(game)
                    .or_insert_with(Instant::now);
            }
            Ok(())
        })
    }
}

#[cfg(test)]
mod tests {
    use settler_island_game::Action;
    use settler_island_protocol::{PublicId, User, UserKind};

    use crate::identity::UserId;

    use super::*;

    fn new_game() -> NewGame {
        NewGame {
            settings: GameSettings {
                seats: 3,
                points_to_win: 10,
                seed: 5,
            },
            seats: vec![
                SeatPlayer::Human(Player {
                    id: UserId("a".to_string()),
                    user: User {
                        id: PublicId("public-a".to_string()),
                        name: "Ada".to_string(),
                        kind: UserKind::Guest,
                    },
                }),
                SeatPlayer::Bot(Difficulty::Random),
                SeatPlayer::Bot(Difficulty::Random),
            ],
            lobby: LobbyId(4),
            lobby_name: "Table".to_string(),
            bot_difficulty: Difficulty::Heuristic,
            away_policy: AwayPolicy::BotTakesOver,
        }
    }

    fn action(index: u32) -> RecordEntry {
        RecordEntry {
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

        store.append_action(first, action(0), None).await.unwrap();
        store.append_action(first, action(1), None).await.unwrap();
        let gap = store.append_action(first, action(3), None).await;
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
        assert!(store.append_action(first, action(2), None).await.is_err());
    }

    #[tokio::test]
    async fn an_unattended_game_keeps_the_time_it_was_first_left_alone() {
        let store = MemoryStore::default();
        let id = store.create_game(new_game()).await.unwrap();
        assert_eq!(store.load_running().await.unwrap()[0].unattended_for, None);

        store.set_attended(id, false).await.unwrap();
        tokio::time::sleep(Duration::from_millis(30)).await;
        // A restore marks the game unattended again; that must not restart the clock.
        store.set_attended(id, false).await.unwrap();
        let unattended = store.load_running().await.unwrap()[0].unattended_for;
        assert!(unattended.is_some_and(|duration| duration >= Duration::from_millis(30)));

        store.set_attended(id, true).await.unwrap();
        assert_eq!(store.load_running().await.unwrap()[0].unattended_for, None);
    }

    #[tokio::test]
    async fn rebuilding_from_snapshot_and_tail_equals_the_live_game() {
        let store = MemoryStore::default();
        let id = store.create_game(new_game()).await.unwrap();
        let mut live = Game::new(new_game().settings).unwrap();
        let mut record = GameRecord::new(&live);
        let count = 2 * SNAPSHOT_INTERVAL + 7;
        for index in 0..count {
            let seat = live.pending_seats()[0];
            let action = live.legal_actions(seat).pop().unwrap();
            let events = live.apply(seat, action.clone()).unwrap();
            let snapshot = wants_snapshot(index).then(|| live.clone());
            let stored = RecordEntry {
                index,
                seat,
                action,
                events,
            };
            record.push_entry(stored.clone());
            store.append_action(id, stored, snapshot).await.unwrap();
        }

        let stored = store.load_running().await.unwrap().remove(0);
        assert_eq!(
            stored.snapshot.as_ref().map(|snapshot| snapshot.actions),
            Some(2 * SNAPSHOT_INTERVAL)
        );
        let (game, rebuilt_record) = stored.rebuild().unwrap();
        assert_eq!(game, live);
        assert_eq!(rebuilt_record, record);
    }
}
