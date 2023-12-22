use std::cell::{RefCell, RefMut};

use log::trace;
use serde::Deserialize;
use serde_json::Value;

use crate::game::{
    player::{Player, PlayerId},
    state::{
        action_data::{DrawDevelopmentCardData, PlaceRobberData},
        state_machine::{GameAction, GameActionResult},
    },
    Game, GameError,
};

use self::build_n_free_roads::BuildNFreeRoads;

use super::robber_relocate::RobberRelocate;

pub mod build_n_free_roads;

pub type DevelopmentCard = &'static str;

pub const DEVELOPMENT_CARD_STREET_CONSTRUCTION: DevelopmentCard = "StreetConstruction";
pub const DEVELOPMENT_CARD_MONOPOLY: DevelopmentCard = "Monopoly";
pub const DEVELOPMENT_CARD_INVENTION: DevelopmentCard = "Invention";
pub const DEVELOPMENT_CARD_KNIGHT: DevelopmentCard = "Knight";
pub const DEVELOPMENT_CARD_VICTORY_POINT: DevelopmentCard = "VictoryPoint";

#[derive(Debug, Deserialize, Clone)]
pub struct InventionData {
    pub resource_a: String,
    pub resource_b: String,
}

#[derive(Debug, Deserialize, Clone)]
pub struct MonopolyData {
    pub resource: String,
}

pub fn process_action(
    game: &mut Game,
    player_id: &PlayerId,
    action_data: Value,
) -> GameActionResult {
    let card_data = match serde_json::from_value::<DrawDevelopmentCardData>(action_data) {
        Err(err) => {
            trace!("Failed to parse draw development card data \"{}\"", err);
            return Err(GameError::ActionDataInvalid);
        }
        Ok(data) => data,
    };

    let card = card_data.card.as_str();
    if let Err(err) = play_card(&mut game.get_player(*player_id).borrow_mut(), card) {
        return Err(err);
    }

    match card {
        DEVELOPMENT_CARD_STREET_CONSTRUCTION => Ok(()),
        DEVELOPMENT_CARD_MONOPOLY => Ok(()),
        DEVELOPMENT_CARD_INVENTION => Ok(()),
        DEVELOPMENT_CARD_KNIGHT => Ok(()),
        _ => Err(GameError::ActionNotAllowed),
    }
}

fn play_card(player: &mut RefMut<'_, Player>, card: &str) -> GameActionResult {
    let cards = player.get_development_cards_mut();
    let card_count = cards.get(card).unwrap_or(&0);

    if *card_count == 0 {
        return Err(GameError::NotEnoughResources);
    }

    cards.insert(card.to_string(), card_count - 1);
    Ok(())
}

pub fn process_street_construction(
    game: &mut Game,
    player_id: &PlayerId,
    action: GameAction,
) -> GameActionResult {
    match game
        .get_state_machine()
        .borrow_mut()
        .transition_to(game, BuildNFreeRoads::get_id())
    {
        Err(err) => Err(GameError::ActionFailed),
        Ok(_) => Ok(()),
    }
}

pub fn process_monopoly(
    game: &mut Game,
    player_id: &PlayerId,
    action: GameAction,
) -> GameActionResult {
    let monopoly_data = match serde_json::from_value::<MonopolyData>(action.data) {
        Err(err) => {
            trace!("Failed to parse monopoly data \"{}\"", err);
            return Err(GameError::ActionDataInvalid);
        }
        Ok(data) => data,
    };

    let mut resource_count: usize = 0;
    let resource = monopoly_data.resource;
    game.get_players()
        .iter()
        .filter(|player| player.borrow().get_id() != player_id)
        .for_each(|player| {
            let mut player = player.borrow_mut();
            let player_resource_count =
                *player.get_resources().get_resource(&resource).unwrap_or(&0);
            player
                .get_resources_mut()
                .remove_resource(&resource, &player_resource_count);
            resource_count += player_resource_count;
        });

    game.get_player(*player_id)
        .borrow_mut()
        .get_resources_mut()
        .add_resource(&resource, &resource_count);

    Ok(())
}

pub fn process_invention(
    game: &mut Game,
    player_id: &PlayerId,
    action: GameAction,
) -> GameActionResult {
    let invention_data = match serde_json::from_value::<InventionData>(action.data) {
        Err(err) => {
            trace!("Failed to parse invention data \"{}\"", err);
            return Err(GameError::ActionDataInvalid);
        }
        Ok(data) => data,
    };

    game.get_player(*player_id)
        .borrow_mut()
        .get_resources_mut()
        .add_resource(&invention_data.resource_a, &1);
    game.get_player(*player_id)
        .borrow_mut()
        .get_resources_mut()
        .add_resource(&invention_data.resource_b, &1);

    Ok(())
}

pub fn process_knight(
    game: &mut Game,
    player_id: &PlayerId,
    action: GameAction,
) -> GameActionResult {
    match game
        .get_state_machine()
        .borrow_mut()
        .transition_to(game, RobberRelocate::get_id())
    {
        Err(err) => Err(GameError::ActionFailed),
        Ok(_) => Ok(()),
    }
}
