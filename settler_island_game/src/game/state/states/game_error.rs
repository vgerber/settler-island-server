use settler_island_util_derive::HasStateId;

use crate::game::{
    player::PlayerId,
    state::state_machine::{GameAction, GameActionResult, GameState, StateMachine},
    Game, GameError,
};

#[derive(HasStateId)]
pub struct GameErrorState {}

impl GameErrorState {
    pub fn new() -> Self {
        GameErrorState {}
    }
}

impl GameState for GameErrorState {
    fn perform_action(
        &mut self,
        game: &mut Game,
        player_id: &PlayerId,
        action: GameAction,
    ) -> GameActionResult {
        Err(GameError::ActionNotAllowed)
    }

    fn get_state(&self) -> Option<serde_json::Value> {
        None
    }

    fn activate(&mut self, game: &Game) {}
}
