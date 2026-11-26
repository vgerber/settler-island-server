mod harness;
mod heuristic;
mod random;

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use settler_island_game::{Action, PlayerView};

pub use harness::{play_game, GameOutcome, PlayError};

/// A bot sees only its own view and the legal list; it never reads the game.
pub trait Bot: Send {
    /// `legal` is never empty when the game asks for an action.
    fn choose(&mut self, view: &PlayerView, legal: &[Action]) -> Action;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub enum Difficulty {
    Random,
    Heuristic,
}

/// Distinct per seat and per game, reproducible from the game seed.
pub fn bot_seed(game_seed: u64, seat: usize) -> u64 {
    game_seed.wrapping_add(seat as u64 + 1)
}

pub fn create_bot(difficulty: Difficulty, seed: u64) -> Box<dyn Bot> {
    match difficulty {
        Difficulty::Random => Box::new(random::RandomBot::new(seed)),
        // Deterministic, so the seed is not needed.
        Difficulty::Heuristic => Box::new(heuristic::HeuristicBot::new()),
    }
}
