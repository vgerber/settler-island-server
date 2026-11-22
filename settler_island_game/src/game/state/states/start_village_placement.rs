use log::trace;
use serde_json::Value;
use settler_island_util_derive::HasStateId;

use crate::game::{
    board::location::{
        settlement_location::{SettlementLocation, SettlementType},
        settlement_map::SettlementMap,
    },
    player::PlayerId,
    state::{
        action_data::{PlaceSettlementData, BUILD_SETTLEMENT_ACTION},
        state_machine::{GameAction, GameState},
        states::start_road_placement::StartRoadPlacement,
    },
    Game, GameError,
};

#[derive(HasStateId)]
pub struct StartVillagePlacement;

impl Default for StartVillagePlacement {
    fn default() -> Self {
        Self::new()
    }
}

impl StartVillagePlacement {
    pub fn new() -> Self {
        StartVillagePlacement {}
    }

    fn process_place_village(
        &self,
        game: &mut Game,
        player_id: &PlayerId,
        action_data: Value,
    ) -> Result<(), GameError> {
        let place_village_data = match serde_json::from_value::<PlaceSettlementData>(action_data) {
            Ok(data) => data,
            Err(err) => {
                trace!("Failed to parse place village data \"{}\"", err.to_string());
                return Err(GameError::ActionDataInvalid);
            }
        };

        StartVillagePlacement::place_village(
            game.get_board_mut().get_settlement_map_mut(),
            &place_village_data.settlement_id,
            player_id,
        )?;

        if let Err(_err) = game
            .get_state_machine()
            .borrow_mut()
            .transition_to(game, StartRoadPlacement::get_id())
        {
            return Err(GameError::ActionFailed);
        }
        Ok(())
    }

    fn place_village(
        settlement_map: &mut SettlementMap,
        settlement_id: &String,
        player_id: &usize,
    ) -> Result<(), GameError> {
        if SettlementMap::any_settlement_occupied(
            &(settlement_map.get_neighbor_settlements(settlement_id)),
        ) {
            trace!("Settlement cannot placed next to a settlement");
            return Err(GameError::InvalidLocation);
        }

        let settlement: &mut SettlementLocation =
            match settlement_map.get_settlement_mut(settlement_id) {
                Some(settlement) => settlement,
                None => {
                    trace!("Settlement \"{}\" not found", settlement_id);
                    return Err(GameError::InvalidLocation);
                }
            };

        match settlement.build_settlement(SettlementType::Village, player_id) {
            Ok(_) => Ok(()),
            Err(err) => {
                trace!("Failed to build village \"{}\"", err);
                Err(GameError::ActionFailed)
            }
        }
    }
}

impl GameState for StartVillagePlacement {
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
            BUILD_SETTLEMENT_ACTION => self.process_place_village(game, player_id, action.data),
            _ => Err(GameError::ActionNotAllowed),
        }
    }

    fn get_state(&self) -> Option<Value> {
        None
    }

    fn activate(&mut self, _game: &Game) {}
}
