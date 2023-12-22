use log::{error, trace};
use serde_json::Value;
use settler_island_util_derive::HasStateId;

use crate::game::{
    player::PlayerId,
    state::{
        action_data::{PlaceRoadData, BUILD_ROAD_ACTION},
        state_machine::{GameAction, GameActionResult, GameState, StateMachine},
        states::select_action::{self, SelectAction},
    },
    Game, GameError,
};

#[derive(HasStateId)]
pub struct BuildNFreeRoads {
    free_roads: usize,
    free_roads_left: usize,
}

impl BuildNFreeRoads {
    pub fn new(free_roads: usize) -> Self {
        BuildNFreeRoads {
            free_roads: free_roads,
            free_roads_left: 0,
        }
    }

    fn process_build_road(
        &mut self,
        game: &mut Game,
        player_id: &PlayerId,
        action_data: Value,
    ) -> GameActionResult {
        if self.free_roads_left == 0 {
            error!("Player {} has no free roads left", player_id);
            return Err(GameError::ActionFailed);
        }

        let place_road_data = match serde_json::from_value::<PlaceRoadData>(action_data) {
            Err(err) => {
                trace!("Failed to parse place road data \"{}\"", err);
                return Err(GameError::ActionDataInvalid);
            }
            Ok(data) => data,
        };

        if let Err(err) = select_action::place_road(
            game.get_board_mut().get_settlement_map_mut(),
            &place_road_data.road_id,
            player_id,
        ) {
            return Err(err);
        }

        self.free_roads_left -= 1;
        if self.free_roads_left > 0 {
            return Ok(());
        }

        match game
            .get_state_machine()
            .borrow_mut()
            .transition_to(game, SelectAction::get_id())
        {
            Err(err) => Err(GameError::ActionFailed),
            Ok(_) => Ok(()),
        }
    }
}

impl GameState for BuildNFreeRoads {
    fn perform_action(
        &mut self,
        game: &mut Game,
        player_id: &PlayerId,
        action: GameAction,
    ) -> GameActionResult {
        if !game.is_player_turn(player_id) {
            return Err(GameError::NotPlayerTurn);
        }

        match action.id.as_str() {
            BUILD_ROAD_ACTION => self.process_build_road(game, player_id, action.data),
            _ => Err(GameError::ActionNotAllowed),
        }
    }

    fn get_state(&self) -> Option<serde_json::Value> {
        None
    }

    fn activate(&mut self, game: &Game) {
        self.free_roads_left = self.free_roads
    }
}
