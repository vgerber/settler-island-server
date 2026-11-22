use settler_island_util_derive::HasStateId;

use crate::game::{
    player::PlayerId,
    state::state_machine::{GameAction, GameActionResult, GameState},
    Game, GameError,
};

#[derive(HasStateId)]
pub struct GameErrorState {}

impl Default for GameErrorState {
    fn default() -> Self {
        Self::new()
    }
}

impl GameErrorState {
    pub fn new() -> Self {
        GameErrorState {}
    }
}

impl GameState for GameErrorState {
    fn perform_action(
        &mut self,
        _game: &mut Game,
        _player_id: &PlayerId,
        _action: GameAction,
    ) -> GameActionResult {
        Err(GameError::ActionNotAllowed)
    }

    fn get_state(&self) -> Option<serde_json::Value> {
        None
    }

    fn activate(&mut self, _game: &Game) {}
}
