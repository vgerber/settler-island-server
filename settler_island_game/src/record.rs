use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

use crate::action::Action;
use crate::board::Board;
use crate::error::GameError;
use crate::event::Event;
use crate::game::{Game, GameSettings, Seat};

const FORMAT_VERSION: u16 = 1;
const RULES_VERSION: u16 = 1;

/// A game as header plus ordered entries; random outcomes are in the events, the seed is never stored.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct GameRecord {
    pub header: RecordHeader,
    pub entries: Vec<RecordEntry>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct RecordHeader {
    pub format_version: u16,
    pub rules_version: u16,
    pub settings_without_seed: RecordSettings,
    pub board: Board,
}

/// `GameSettings` without the seed, which would reveal future rolls.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub struct RecordSettings {
    pub seats: u8,
    pub points_to_win: u8,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct RecordEntry {
    pub index: u32,
    pub seat: Seat,
    pub action: Action,
    pub events: Vec<Event>,
}

impl GameRecord {
    /// Starts a record for a freshly created game.
    pub fn new(game: &Game) -> GameRecord {
        GameRecord {
            header: RecordHeader {
                format_version: FORMAT_VERSION,
                rules_version: RULES_VERSION,
                settings_without_seed: RecordSettings {
                    seats: game.settings.seats,
                    points_to_win: game.settings.points_to_win,
                },
                board: game.board.clone(),
            },
            entries: Vec::new(),
        }
    }

    pub fn push(&mut self, seat: Seat, action: Action, events: Vec<Event>) {
        self.entries.push(RecordEntry {
            index: self.entries.len() as u32,
            seat,
            action,
            events,
        });
    }
}

/// Rebuilds a game from its settings and the actions applied so far.
pub fn replay(settings: GameSettings, actions: &[(Seat, Action)]) -> Result<Game, GameError> {
    let mut game = Game::new(settings)?;
    for (seat, action) in actions {
        game.apply(*seat, action.clone())?;
    }
    Ok(game)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn settings() -> GameSettings {
        GameSettings {
            seats: 4,
            points_to_win: 10,
            seed: 99,
        }
    }

    /// Plays `count` actions, always the last legal one so that turns end and dice are rolled often.
    fn play(count: usize) -> (Game, GameRecord) {
        let mut game = Game::new(settings()).unwrap();
        let mut record = GameRecord::new(&game);
        for _ in 0..count {
            let seat = game.pending_seats()[0];
            let action = game.legal_actions(seat).pop().unwrap();
            let events = game.apply(seat, action.clone()).unwrap();
            record.push(seat, action, events);
        }
        (game, record)
    }

    #[test]
    fn replay_reproduces_every_event_and_the_final_state() {
        let (game, record) = play(300);
        let actions: Vec<(Seat, Action)> = record
            .entries
            .iter()
            .map(|entry| (entry.seat, entry.action.clone()))
            .collect();

        let mut fresh = Game::new(settings()).unwrap();
        assert_eq!(record.header.board, fresh.board);
        for entry in &record.entries {
            assert_eq!(
                fresh.apply(entry.seat, entry.action.clone()).as_ref(),
                Ok(&entry.events)
            );
        }
        assert_eq!(replay(settings(), &actions), Ok(game));
    }

    #[test]
    fn json_snapshot_mid_game_continues_identically() {
        let (mut game, _) = play(150);
        let json = serde_json::to_string(&game).unwrap();
        let mut restored: Game = serde_json::from_str(&json).unwrap();
        assert_eq!(restored, game);

        for _ in 0..200 {
            let seat = game.pending_seats()[0];
            let action = game.legal_actions(seat).pop().unwrap();
            assert_eq!(
                game.apply(seat, action.clone()),
                restored.apply(seat, action)
            );
        }
        assert_eq!(restored, game);
    }

    #[test]
    fn record_round_trips_through_json() {
        let (_, record) = play(80);
        let json = serde_json::to_string(&record).unwrap();

        assert_eq!(serde_json::from_str::<GameRecord>(&json).unwrap(), record);
    }
}
