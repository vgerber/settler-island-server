use std::{
    cell::{RefCell, RefMut},
    collections::HashMap,
};

use log::{error, trace};
use serde_json::Value;
use settler_island_util_derive::HasStateId;

use crate::game::{
    board::{
        location::{
            road_location::PlayerRoad,
            settlement_location::{SettlementLocation, SettlementType},
            settlement_map::SettlementMap,
        },
        resource::{
            base_resource::{
                RESOURCE_CLAY, RESOURCE_ORE, RESOURCE_SHEEP, RESOURCE_WHEAT, RESOURCE_WOOD,
            },
            player_resources::ResourceCollection,
        },
    },
    player::{Player, PlayerId},
    state::{
        action_data::{
            PlaceRoadData, PlaceSettlementData, BUILD_ROAD_ACTION, BUILD_SETTLEMENT_ACTION,
            DRAW_DEVELOPMENT_CARD_ACTION, END_TURN_ACTION, OFFER_BANK_TRADE_ACTION,
            OFFER_TRADE_ACTION,
        },
        state_machine::{GameAction, GameActionResult, GameState, StateMachine},
    },
    Game, GameError,
};

use super::{development_card, roll_dice::RollDice, trading};

#[derive(HasStateId)]
pub struct SelectAction {}

impl SelectAction {
    pub fn new() -> Self {
        SelectAction {}
    }
}

impl GameState for SelectAction {
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
            BUILD_SETTLEMENT_ACTION => process_build_settlement(game, player_id, action.data),
            BUILD_ROAD_ACTION => process_build_road(game, player_id, action.data),
            DRAW_DEVELOPMENT_CARD_ACTION => {
                development_card::process_action(game, player_id, action.data)
            }
            END_TURN_ACTION => process_end_turn(game, player_id, action.data),
            OFFER_TRADE_ACTION => trading::process_trade_offer(game, player_id, action.data),
            OFFER_BANK_TRADE_ACTION => {
                trading::process_bank_trade_offer(game, player_id, action.data)
            }
            _ => Err(crate::game::GameError::ActionNotAllowed),
        }
    }

    fn get_state(&self) -> Option<Value> {
        None
    }

    fn activate(&mut self, game: &Game) {}
}

fn process_build_road(
    game: &mut Game,
    player_id: &PlayerId,
    action_data: Value,
) -> GameActionResult {
    let place_road_data = match serde_json::from_value::<PlaceRoadData>(action_data) {
        Err(err) => {
            trace!("Failed to parse place road data \"{}\"", err);
            return Err(GameError::ActionDataInvalid);
        }
        Ok(data) => data,
    };

    let player = game.get_player(*player_id);
    if let Err(err) = remove_resources(&mut player.borrow_mut(), &get_road_cost()) {
        return Err(err);
    }

    match place_road(
        game.get_board_mut().get_settlement_map_mut(),
        &place_road_data.road_id,
        player_id,
    ) {
        Err(err) => Err(err),
        Ok(_) => Ok(()),
    }
}

fn process_build_settlement(
    game: &mut Game,
    player_id: &PlayerId,
    action_data: Value,
) -> GameActionResult {
    let place_settlement_data = match serde_json::from_value::<PlaceSettlementData>(action_data) {
        Err(err) => {
            trace!("Failed to parse place road data \"{}\"", err);
            return Err(GameError::ActionDataInvalid);
        }
        Ok(data) => data,
    };

    let resource_cost = match place_settlement_data.settlement_type {
        SettlementType::Village => get_village_cost(),
        SettlementType::City => get_city_cost(),
    };

    if let Err(err) = remove_resources(
        &mut game.get_player(*player_id).borrow_mut(),
        &resource_cost,
    ) {
        return Err(err);
    }

    place_settlement(
        game.get_board_mut().get_settlement_map_mut(),
        &place_settlement_data.settlement_id,
        place_settlement_data.settlement_type,
        player_id,
    )
}

fn process_draw_development_card(
    game: &mut Game,
    player_id: &PlayerId,
    action_data: Value,
) -> GameActionResult {
    Err(GameError::ActionNotAllowed)
}

fn process_end_turn(game: &mut Game, player_id: &PlayerId, action_data: Value) -> GameActionResult {
    game.end_turn();
    match game
        .get_state_machine()
        .borrow_mut()
        .transition_to(game, RollDice::get_id())
    {
        Err(err) => Err(GameError::ActionFailed),
        Ok(_) => Ok(()),
    }
}

fn process_trade_offer(
    game: &mut Game,
    player_id: &PlayerId,
    action_data: Value,
) -> GameActionResult {
    // TODO create trade offer
    // TODO transition to trading state
    Err(GameError::ActionNotAllowed)
}

fn get_road_cost() -> ResourceCollection {
    ResourceCollection::from([
        (RESOURCE_CLAY.to_string(), 1),
        (RESOURCE_WOOD.to_string(), 1),
    ])
}

fn get_village_cost() -> ResourceCollection {
    ResourceCollection::from([
        (RESOURCE_CLAY.to_string(), 1),
        (RESOURCE_WOOD.to_string(), 1),
        (RESOURCE_SHEEP.to_string(), 1),
        (RESOURCE_WHEAT.to_string(), 1),
    ])
}

fn get_city_cost() -> ResourceCollection {
    ResourceCollection::from([
        (RESOURCE_ORE.to_string(), 3),
        (RESOURCE_WHEAT.to_string(), 2),
    ])
}

fn get_development_card_cost() -> ResourceCollection {
    ResourceCollection::from([
        (RESOURCE_ORE.to_string(), 1),
        (RESOURCE_SHEEP.to_string(), 1),
        (RESOURCE_WHEAT.to_string(), 1),
    ])
}

fn remove_resources(
    player: &mut RefMut<'_, Player>,
    resources: &ResourceCollection,
) -> GameActionResult {
    if !player.get_resources().has_resources(&resources) {
        return Err(GameError::NotEnoughResources);
    }

    if !player.get_resources_mut().remove_resources(&resources) {
        error!(
            "Failed to remove resources {:?} from {}",
            resources,
            player.get_id()
        );
        return Err(GameError::ActionFailed);
    }
    Ok(())
}

pub fn place_road(
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

    if !settlement_a.is_owner(&player_id) && !settlement_b.is_owner(&player_id) {
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

fn place_settlement(
    settlement_map: &mut SettlementMap,
    settlement_id: &String,
    settlement_type: SettlementType,
    player_id: &usize,
) -> Result<(), GameError> {
    if SettlementMap::any_settlement_occupied(
        &(settlement_map.get_neighbor_settlements(settlement_id)),
    ) {
        trace!(
            "Settlement {} cannot placed next to a settlement",
            settlement_id
        );
        return Err(GameError::InvalidLocation);
    }

    if !settlement_map.has_settlement_player_roads(settlement_id, *player_id) {
        trace!("Settlement {} needs a road connection", settlement_id);
        return Err(GameError::InvalidLocation);
    }

    let settlement: &mut SettlementLocation =
        match settlement_map.get_settlement_mut(&settlement_id) {
            Some(settlement) => settlement,
            None => {
                trace!("Settlement \"{}\" not found", settlement_id);
                return Err(GameError::InvalidLocation);
            }
        };

    match settlement.build_settlement(settlement_type, player_id) {
        Ok(_) => Ok(()),
        Err(err) => {
            trace!("Failed to build village \"{}\"", err);
            Err(GameError::ActionFailed)
        }
    }
}
