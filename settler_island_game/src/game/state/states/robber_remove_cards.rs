use std::collections::HashMap;

use log::trace;
use serde_json::Value;
use settler_island_util_derive::HasStateId;

use crate::game::{
    board::resource::player_resources::{get_total_resources, ResourceCollection},
    player::{Player, PlayerId},
    state::{
        action_data::REMOVE_CARDS_ACTION,
        state_machine::{GameAction, GameActionResult, GameState, StateMachine},
    },
    Game,
};

use super::robber_relocate::RobberRelocate;

pub fn has_a_player_too_many_cards(game: &Game) -> bool {
    game.get_players()
        .iter()
        .any(|game_player| player_needs_to_remove_resources(&game_player.borrow()))
}

#[derive(HasStateId)]
pub struct RobberRemoveCards {
    player_remove_counts: HashMap<PlayerId, usize>,
}

impl RobberRemoveCards {
    pub fn new() -> Self {
        RobberRemoveCards {
            player_remove_counts: HashMap::new(),
        }
    }
}

impl GameState for RobberRemoveCards {
    fn perform_action(
        &mut self,
        game: &mut Game,
        player_id: &PlayerId,
        action: GameAction,
    ) -> GameActionResult {
        match action.id.as_str() {
            REMOVE_CARDS_ACTION => process_remove_cards(game, player_id, action.data),
            _ => Err(crate::game::GameError::ActionNotAllowed),
        }
    }

    fn get_state(&self) -> Option<Value> {
        None
    }

    fn activate(&mut self, game: &Game) {
        self.player_remove_counts.clear();
    }
}

fn process_remove_cards(
    game: &mut Game,
    player_id: &PlayerId,
    action_data: Value,
) -> GameActionResult {
    if let Err(err) = remove_player_cards(game, player_id, action_data) {
        return Err(err);
    }

    match has_a_player_too_many_cards(game) {
        true => Ok(()),
        false => match game
            .get_state_machine()
            .borrow_mut()
            .transition_to(game, RobberRelocate::get_id())
        {
            Ok(_) => Ok(()),
            Err(err) => {
                return Err(crate::game::GameError::ActionFailed);
            }
        },
    }
}

fn player_needs_to_remove_resources(player: &Player) -> bool {
    player.get_resources().get_total_resources() > 7
}

fn is_player_removing_invalid_resources_count(
    player: &Player,
    removed_resources: &ResourceCollection,
) -> bool {
    (player.get_resources().get_total_resources() - 7) != get_total_resources(removed_resources)
}

fn remove_player_cards(
    game: &mut Game,
    player_id: &PlayerId,
    action_data: Value,
) -> GameActionResult {
    let player = game.get_player(*player_id).borrow();
    if !player_needs_to_remove_resources(&player) {
        trace!("Player does not need to remove resources");
        return Err(crate::game::GameError::ActionNotAllowed);
    }
    let removed_cards = match serde_json::from_value::<ResourceCollection>(action_data) {
        Err(err) => {
            trace!("Failed to parse removed cards \"{}\"", err);
            return Err(crate::game::GameError::ActionDataInvalid);
        }
        Ok(cards) => cards,
    };

    if is_player_removing_invalid_resources_count(&player, &removed_cards) {
        trace!("Player did not remove the necessary resource amount");
        return Err(crate::game::GameError::ActionFailed);
    }

    game.get_player(*player_id)
        .borrow_mut()
        .get_resources_mut()
        .remove_resources(&removed_cards);
    Ok(())
}
