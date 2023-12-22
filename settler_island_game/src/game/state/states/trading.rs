use std::{borrow::Borrow, cell::RefCell};

use log::{error, trace};
use serde_json::Value;
use settler_island_util_derive::HasStateId;

use crate::game::{
    player::{Player, PlayerId},
    state::{
        action_data::{
            CompletePlayerTradeData, TradeOfferData, ACCEPT_TRADE_ACTION, CANCEL_TRADE_ACTION,
            COMPLETE_TRADE_ACTION, OFFER_BANK_TRADE_ACTION, OFFER_TRADE_ACTION,
            REJECT_TRADE_ACTION,
        },
        state_machine::{GameAction, GameActionResult, GameState, StateMachine},
    },
    trade::TradeOffer,
    Game, GameError,
};

#[derive(HasStateId)]
pub struct Trading {}

impl Trading {
    pub fn new() -> Self {
        Trading {}
    }
}

impl GameState for Trading {
    fn perform_action(
        &mut self,
        game: &mut Game,
        player_id: &PlayerId,
        action: GameAction,
    ) -> GameActionResult {
        if game.is_player_turn(player_id) {
            match action.id.as_str() {
                COMPLETE_TRADE_ACTION => process_complete_trade(game, action.data),
                CANCEL_TRADE_ACTION => process_cancel_trade(game),
                _ => Err(crate::game::GameError::ActionNotAllowed),
            }
        } else {
            match action.id.as_str() {
                ACCEPT_TRADE_ACTION => process_accept_trade_offer(game, *player_id),
                REJECT_TRADE_ACTION => process_reject_trade_offer(game, *player_id),
                _ => Err(crate::game::GameError::ActionNotAllowed),
            }
        }
    }

    fn get_state(&self) -> Option<serde_json::Value> {
        None
    }

    fn activate(&mut self, game: &Game) {}
}

pub fn process_trade_offer(
    game: &mut Game,
    player_id: &PlayerId,
    action_data: Value,
) -> Result<(), GameError> {
    let trade_data = match serde_json::from_value::<TradeOfferData>(action_data) {
        Err(err) => {
            trace!("Failed to parse trade offer data \"{}\"", err.to_string());
            return Err(GameError::ActionDataInvalid);
        }
        Ok(data) => data,
    };

    if !game
        .get_player(*player_id)
        .borrow()
        .get_resources()
        .has_resources(&trade_data.resource_offer)
    {
        return Err(GameError::NotEnoughResources);
    }

    game.create_trade_offer(TradeOffer::new(
        *player_id,
        trade_data.resource_offer,
        trade_data.resource_receive,
        game.get_players()
            .iter()
            .map(|player| *player.borrow().get_id())
            .filter(|id| id != player_id)
            .collect(),
    ));

    Ok(())
}

pub fn process_bank_trade_offer(
    game: &mut Game,
    player_id: &PlayerId,
    action_data: Value,
) -> Result<(), GameError> {
    error!("Bank trades are not implemented yet");
    Err(GameError::ActionFailed)
}

fn process_complete_trade(game: &mut Game, action_data: Value) -> Result<(), GameError> {
    let complete_data = match serde_json::from_value::<CompletePlayerTradeData>(action_data) {
        Err(err) => {
            trace!(
                "Failed to parse complete trade data \"{}\"",
                err.to_string()
            );
            return Err(GameError::ActionDataInvalid);
        }
        Ok(data) => data,
    };

    let opt_offer = game.get_trade_offer().borrow();
    let offer = match opt_offer.as_ref() {
        None => {
            trace!("No active trade offer found");
            return Err(GameError::ActionFailed);
        }
        Some(offer) => offer,
    };

    if !offer
        .players_accepted
        .get(&complete_data.accepted_player_id)
        .unwrap_or(&false)
    {
        trace!(
            "Player {} did not accept the offer",
            complete_data.accepted_player_id
        );
        return Err(GameError::ActionNotAllowed);
    }

    let player = game.get_player(offer.creator);
    let accepted_player = game.get_player(complete_data.accepted_player_id);
    accepted_player
        .borrow_mut()
        .get_resources_mut()
        .remove_resources(&offer.resource_receive);
    player
        .borrow_mut()
        .get_resources_mut()
        .remove_resources(&offer.resource_offer);

    accepted_player
        .borrow_mut()
        .get_resources_mut()
        .add_resources(offer.resource_offer.clone());
    player
        .borrow_mut()
        .get_resources_mut()
        .add_resources(offer.resource_receive.clone());

    Ok(game.complete_trade_offer())
}

fn process_cancel_trade(game: &mut Game) -> Result<(), GameError> {
    match game.get_trade_offer().borrow().as_ref() {
        None => Err(GameError::ActionNotAllowed),
        Some(_) => {
            game.cancel_trade_offer();
            Ok(())
        }
    }
}

fn process_accept_trade_offer(game: &mut Game, player_id: PlayerId) -> Result<(), GameError> {
    let player = game.get_player(player_id).borrow();
    let mut opt_offer = game.get_trade_offer().borrow_mut();
    let mut offer = match opt_offer.as_mut() {
        None => {
            trace!("No active trade offer found");
            return Err(GameError::ActionFailed);
        }
        Some(offer) => offer,
    };

    if !player
        .get_resources()
        .has_resources(&offer.resource_receive)
    {
        trace!(
            "Player {} cannot not provide the requested resources",
            player_id
        );
        return Err(GameError::NotEnoughResources);
    }

    offer.players_accepted.insert(player_id, true);
    Ok(())
}

fn process_reject_trade_offer(game: &mut Game, player_id: PlayerId) -> Result<(), GameError> {
    let mut opt_offer = game.get_trade_offer().borrow_mut();
    let mut offer = match opt_offer.as_mut() {
        None => {
            trace!("No active trade offer found");
            return Err(GameError::ActionFailed);
        }
        Some(offer) => offer,
    };

    offer.players_accepted.insert(player_id, false);
    Ok(())
}
