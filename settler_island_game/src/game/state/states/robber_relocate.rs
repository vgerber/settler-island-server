use log::trace;
use rand::{seq::SliceRandom, thread_rng, Rng};
use serde_json::Value;
use settler_island_util_derive::HasStateId;

use crate::game::{
    board::resource::base_resource::ResourcedId,
    player::{Player, PlayerId},
    state::{
        action_data::{PlaceRobberData, PLACE_ROBBER_ACTION},
        state_machine::{GameAction, GameActionResult, GameState, StateMachine},
    },
    Game,
};

#[derive(HasStateId)]
pub struct RobberRelocate {}

impl RobberRelocate {
    pub fn new() -> Self {
        RobberRelocate {}
    }

    fn process_place_robber(
        &self,
        game: &mut Game,
        player_id: &PlayerId,
        action_data: Value,
    ) -> GameActionResult {
        let new_robber_location = match serde_json::from_value::<PlaceRobberData>(action_data) {
            Err(err) => {
                trace!("Failed to parse robber location \"{}\"", err);
                return Err(crate::game::GameError::ActionDataInvalid);
            }
            Ok(location) => location,
        };

        let tile_map = game.get_board().get_tile_map();
        let tile = match tile_map.get_tile(&new_robber_location.tile_location) {
            None => {
                trace!("Tile at {:?} not found", new_robber_location.tile_location);
                return Err(crate::game::GameError::InvalidLocation);
            }
            Some(tile) => tile,
        };

        let settlement_map = game.get_board().get_settlement_map();
        let mut tile_players: Vec<PlayerId> = tile
            .borrow()
            .get_corner_settlement_ids()
            .iter()
            .filter_map(|tile_id| settlement_map.get_settlement(tile_id))
            .filter_map(|settlement| settlement.get_settlement().clone())
            .map(|settlement| *settlement.get_player_id())
            .collect();
        tile_players.dedup();

        if !tile_players.contains(&new_robber_location.robbed_player_id) {
            trace!(
                "Player {} not found at tile {:?}",
                new_robber_location.robbed_player_id,
                new_robber_location.tile_location
            );
            return Err(crate::game::GameError::ActionFailed);
        }

        // exchange single resource from robbed player to player
        let robbed_player = game.get_player(new_robber_location.robbed_player_id);
        match RobberRelocate::get_random_resource_from_player(&robbed_player.borrow()) {
            None => {
                trace!(
                    "Tried to rob player {} without resources",
                    new_robber_location.robbed_player_id
                );
                return Err(crate::game::GameError::ActionFailed);
            }
            Some(resource) => {
                robbed_player
                    .borrow_mut()
                    .get_resources_mut()
                    .remove_resource(&resource, &1);
                game.get_player(*player_id)
                    .borrow_mut()
                    .get_resources_mut()
                    .add_resource(&resource, &1);
            }
        }

        Ok(())
    }

    fn get_random_resource_from_player(player: &Player) -> Option<ResourcedId> {
        if player.get_resources().get_total_resources() == 0 {
            return None;
        }

        let resources = player.get_resources().get_resources();
        let player_resource_ids: Vec<&ResourcedId> = resources.keys().collect();
        loop {
            let resource = *player_resource_ids.choose(&mut thread_rng()).unwrap();
            match resources.get(resource) {
                Some(count) => {
                    if *count > 0 {
                        return Some(resource.clone());
                    }
                }
                _ => (),
            }
        }
        None
    }
}

impl GameState for RobberRelocate {
    fn perform_action(
        &mut self,
        game: &mut Game,
        player_id: &PlayerId,
        action: GameAction,
    ) -> GameActionResult {
        match action.id.as_str() {
            PLACE_ROBBER_ACTION => self.process_place_robber(game, player_id, action.data),
            _ => Err(crate::game::GameError::ActionNotAllowed),
        }
    }

    fn get_state(&self) -> Option<Value> {
        None
    }

    fn activate(&mut self, game: &Game) {}
}
