use log::{error, trace};
use serde_json::Value;
use settler_island_util_derive::HasStateId;

use crate::game::{
    board::location::{
        road_location::PlayerRoad,
        settlement_location::{SettlementLocation, SettlementType},
        settlement_map::SettlementMap,
    },
    player::{Player, PlayerId},
    state::{
        action_data::{PlaceSettlementData, BUILD_ROAD_ACTION},
        state_machine::{GameAction, GameState, StateMachine},
        states::{roll_dice::RollDice, start_village_placement::StartVillagePlacement},
    },
    Game, GameError,
};

#[derive(HasStateId, Debug)]
pub struct StartRoadPlacement;

impl StartRoadPlacement {
    pub fn new() -> Self {
        StartRoadPlacement {}
    }

    fn process_place_road(
        &self,
        game: &mut Game,
        player_id: &PlayerId,
        action_data: Value,
    ) -> Result<(), GameError> {
        let place_road_data = match serde_json::from_value::<PlaceSettlementData>(action_data) {
            Ok(data) => data,
            Err(err) => {
                trace!("Failed to parse place village data \"{}\"", err.to_string());
                return Err(GameError::ActionDataInvalid);
            }
        };

        if let Err(err) = StartRoadPlacement::place_road(
            game.get_board_mut().get_settlement_map_mut(),
            &place_road_data.settlement_id,
            player_id,
        ) {
            return Err(err);
        }

        // end turn on settlement placed
        // last player can place all settlements in one round
        let has_two_settlements =
            StartRoadPlacement::get_player_settlement_count(game, player_id) >= 2;
        let is_last_player = *game.get_current_player_index() == (game.get_player_count() - 1);
        if !is_last_player {
            game.end_turn();
        } else if has_two_settlements {
            game.end_turn();
        }

        // If all players placed their settlements and roads the game continues with the first dice roll
        let all_players_placed_two_settlements =
            StartRoadPlacement::all_players_have_at_least_n_settlements(game, 2);
        if all_players_placed_two_settlements {
            if let Err(_) = game
                .get_state_machine()
                .borrow_mut()
                .transition_to(game, RollDice::get_id())
            {
                return Err(GameError::ActionFailed);
            }
        } else {
            if let Err(_) = game
                .get_state_machine()
                .borrow_mut()
                .transition_to(game, StartVillagePlacement::get_id())
            {
                return Err(GameError::ActionFailed);
            }
        }

        Ok(())
    }

    fn place_road(
        settlement_map: &mut SettlementMap,
        road_id: &String,
        player_id: &PlayerId,
    ) -> Result<(), GameError> {
        let road = match settlement_map.get_road(road_id) {
            None => {
                error!("Road \"{}\" not found", road_id);
                return Err(GameError::ActionFailed);
            }
            Some(road) => road,
        };

        if road.has_road() {
            trace!("Road \"{}\" is already occupied", road_id);
            return Err(GameError::InvalidLocation);
        }

        let settlement_a = match settlement_map.get_settlement(road.get_settlement_a_id()) {
            None => {
                error!(
                    "Road \"{}\" has no connection to a \"{}\"",
                    road_id,
                    road.get_settlement_a_id()
                );
                return Err(GameError::ActionFailed);
            }
            Some(settlement) => settlement,
        };

        let settlement_b = match settlement_map.get_settlement(road.get_settlement_b_id()) {
            None => {
                error!(
                    "Road \"{}\" has no connection to b \"{}\"",
                    road_id,
                    road.get_settlement_b_id()
                );
                return Err(GameError::ActionFailed);
            }
            Some(settlement) => settlement,
        };

        if !settlement_a.is_owner(player_id) && !settlement_b.is_owner(player_id) {
            trace!(
                "Player {} does not own a settlement on road \"{}\"",
                player_id,
                road_id
            );
            return Err(GameError::InvalidLocation);
        }

        match settlement_map
            .get_road_mut(road_id)
            .unwrap()
            .build_road(PlayerRoad::from(*player_id))
        {
            Err(err) => {
                trace!("Road {} placement failed \"{}\"", road_id, err);
                Err(GameError::ActionFailed)
            }
            Ok(_) => Ok(()),
        }
    }

    fn get_player_settlement_count(game: &Game, player_id: &PlayerId) -> usize {
        game.get_board()
            .get_settlement_map()
            .get_player_settlements(player_id)
            .len()
    }

    fn all_players_have_at_least_n_settlements(
        game: &Game,
        expected_settlement_count: usize,
    ) -> bool {
        game.get_players()
            .iter()
            .map(|player| {
                StartRoadPlacement::get_player_settlement_count(game, &player.borrow().get_id())
            })
            .all(|settlement_count| settlement_count >= expected_settlement_count)
    }
}

impl GameState for StartRoadPlacement {
    fn perform_action(
        &mut self,
        game: &mut Game,
        player_id: &PlayerId,
        action: GameAction,
    ) -> Result<(), GameError> {
        if !game.is_player_turn(player_id) {
            return Err(GameError::NotPlayerTurn);
        }

        match action.id.as_str() {
            BUILD_ROAD_ACTION => self.process_place_road(game, player_id, action.data),
            _ => Err(GameError::ActionNotAllowed),
        }
    }

    fn get_state(&self) -> Option<Value> {
        None
    }

    fn activate(&mut self, game: &Game) {}
}
