use std::{borrow::BorrowMut, cell::RefCell, collections::HashMap};

use log::error;
use serde::Deserialize;
use serde_json::Value;
use settler_island_util::state_id::HasStateId;

use crate::game::{
    board::{self, GameBoard},
    player::{Player, PlayerId},
    Game, GameError,
};

use super::states::game_error::GameErrorState;

pub type GameStateT = Box<dyn GameState + Send + Sync>;
pub type GameActionResult = Result<(), GameError>;
type GameStates = HashMap<String, GameStateT>;

#[derive(Debug, Deserialize)]
pub struct GameAction {
    pub id: String,
    pub data: Value,
}

pub trait GameState: HasStateId {
    fn get_state(&self) -> Option<Value>;
    fn activate(&mut self, game: &Game);
    fn perform_action(
        &mut self,
        game: &mut Game,
        player_id: &PlayerId,
        action: GameAction,
    ) -> GameActionResult;
}

pub struct StateMachine {
    current_state_id: String,
    states: GameStates,
}

impl StateMachine {
    pub fn from(mut states: Vec<GameStateT>, current_state_id: String) -> Self {
        let mut states_map = GameStates::new();
        while !states.is_empty() {
            let state = states.pop().unwrap();
            states_map.insert(state.get_id().to_string(), state);
        }

        StateMachine {
            current_state_id: current_state_id,
            states: states_map,
        }
    }

    pub fn get_current_state(&self) -> &GameStateT {
        self.states.get(&self.current_state_id).unwrap()
    }

    pub fn transition_to(&mut self, game: &Game, state_id: &str) -> Result<(), String> {
        match self.states.get_mut(state_id) {
            Some(state) => {
                self.current_state_id = state_id.to_string();
                state.activate(game);
                Ok(())
            }
            None => {
                let err = format!(
                    "State {} not found, transitioning to {}",
                    state_id,
                    GameErrorState::get_id()
                );
                error!("{}", err);
                self.to_error_state();
                Err(err)
            }
        }
    }

    pub fn to_error_state(&mut self) {
        self.current_state_id = GameErrorState::get_id().to_string();
    }
}
