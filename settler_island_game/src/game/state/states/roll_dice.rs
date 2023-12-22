use std::cell::RefCell;

use log::error;
use settler_island_util_derive::HasStateId;

use crate::game::{
    board::{
        hexagon::hexagon_tile::{HexagonTile, TileType},
        location::settlement_location::{PlayerSettlement, SettlementType},
        resource::base_resource::ResourcedId,
        DoubleDiceRoll,
    },
    player::{Player, PlayerId},
    state::{
        action_data::ROLL_DICE_ACTION,
        state_machine::{GameAction, GameActionResult, GameState, StateMachine},
    },
    Game, GameError,
};

use super::{
    robber_relocate::RobberRelocate,
    robber_remove_cards::{has_a_player_too_many_cards, RobberRemoveCards},
};

#[derive(HasStateId)]
pub struct RollDice {}

impl RollDice {
    pub fn new() -> Self {
        RollDice {}
    }

    fn process_roll_dice(&self, game: &mut Game, player_id: &PlayerId) -> GameActionResult {
        let dice_roll = game.get_board_mut().roll_dice();
        match dice_roll.get_total() {
            7 => self.transition_to_robber_state(game),
            value => self.add_resources(game, &value),
        }
    }

    fn transition_to_robber_state(&self, game: &mut Game) -> GameActionResult {
        let transition_result = match has_a_player_too_many_cards(game) {
            true => game
                .get_state_machine()
                .borrow_mut()
                .transition_to(game, RobberRemoveCards::get_id()),
            false => game
                .get_state_machine()
                .borrow_mut()
                .transition_to(game, RobberRelocate::get_id()),
        };

        match transition_result {
            Ok(_) => Ok(()),
            Err(err) => {
                return Err(GameError::ActionFailed);
            }
        }
    }

    fn add_resources(&self, game: &mut Game, dice_roll_value: &u8) -> GameActionResult {
        let board = game.get_board();
        let tiles = board.get_tiles_by_dice_value(&dice_roll_value);
        for tile in tiles {
            let tile_borrow = tile.borrow();

            // tiles with robber do not yield resources
            if tile_borrow.get_coordinates() == board.get_robber().get_assigned_tile() {
                continue;
            }

            // only resource tiles yield resources
            let resource = match tile_borrow.get_type() {
                TileType::ResourceTile(resource) => resource,
                _ => continue,
            };

            // add resources to all players who own a settlement next to the tile
            for settlement_id in tile_borrow.get_corner_settlement_ids() {
                let settlement = match board.get_settlement_map().get_settlement(settlement_id) {
                    None => {
                        error!("Settlement \"{}\" not found in settlements", settlement_id);
                        return Err(GameError::ActionFailed);
                    }
                    Some(settlement) => settlement,
                };

                let player_settlement = match settlement.get_settlement() {
                    None => continue,
                    Some(player_settlement) => player_settlement,
                };

                self.add_settlement_resource(game, &player_settlement, resource);
            }
        }

        Ok(())
    }

    fn add_settlement_resource(
        &self,
        game: &Game,
        settlement: &PlayerSettlement,
        resource: &ResourcedId,
    ) -> Result<(), GameError> {
        let resource_factor: usize = match settlement.get_settlement_type() {
            SettlementType::Village => 1,
            SettlementType::City => 2,
        };

        game.get_player(*settlement.get_player_id())
            .borrow_mut()
            .get_resources_mut()
            .add_resource(resource, &resource_factor);
        Ok(())
    }
}

impl GameState for RollDice {
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
            ROLL_DICE_ACTION => self.process_roll_dice(game, player_id),
            _ => Err(crate::game::GameError::ActionNotAllowed),
        }
    }

    fn get_state(&self) -> Option<serde_json::Value> {
        None
    }

    fn activate(&mut self, game: &Game) {}
}
