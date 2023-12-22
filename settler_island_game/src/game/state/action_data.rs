use serde::Deserialize;

use crate::game::{
    board::{
        hexagon::cube_coordinates::CubeCoordinates, location::settlement_location::SettlementType,
        resource::player_resources::ResourceCollection,
    },
    player::PlayerId,
};

use super::states::development_card::DevelopmentCard;

pub const DRAW_DEVELOPMENT_CARD_ACTION: &str = "BuildSettlement";
pub const BUILD_SETTLEMENT_ACTION: &str = "BuildSettlement";
pub const BUILD_ROAD_ACTION: &str = "BuildRoad";
pub const PLACE_ROBBER_ACTION: &str = "PlaceRobber";
pub const REMOVE_CARDS_ACTION: &str = "RemoveCards";
pub const SELECT_SETTLEMENT_ACTION: &str = "SelectSettlement";
pub const ROLL_DICE_ACTION: &str = "RollDice";
pub const END_TURN_ACTION: &str = "EndTurn";

pub const OFFER_TRADE_ACTION: &str = "OfferTrade";
pub const OFFER_BANK_TRADE_ACTION: &str = "OfferBankTrade";
pub const ACCEPT_TRADE_ACTION: &str = "AcceptTrade";
pub const REJECT_TRADE_ACTION: &str = "RejectTrade";
pub const COMPLETE_TRADE_ACTION: &str = "CompleteTrade";
pub const CANCEL_TRADE_ACTION: &str = "CancelTrade";

#[derive(Debug, Deserialize, Clone)]
pub struct PlaceSettlementData {
    pub settlement_type: SettlementType,
    pub settlement_id: String,
}

#[derive(Debug, Deserialize, Clone)]
pub struct PlaceRoadData {
    pub road_id: String,
}

#[derive(Debug, Deserialize, Clone)]
pub struct PlaceRobberData {
    pub tile_location: CubeCoordinates,
    pub robbed_player_id: PlayerId,
}

#[derive(Debug, Deserialize, Clone)]
pub struct DrawDevelopmentCardData {
    pub card: String,
}

#[derive(Debug, Deserialize, Clone)]
pub struct TradeOfferData {
    pub resource_offer: ResourceCollection,
    pub resource_receive: ResourceCollection,
}

#[derive(Debug, Deserialize, Clone)]
pub struct CompletePlayerTradeData {
    pub accepted_player_id: PlayerId,
}
