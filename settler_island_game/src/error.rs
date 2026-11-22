use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

#[derive(
    Debug, Clone, Copy, PartialEq, Eq, thiserror::Error, Serialize, Deserialize, JsonSchema,
)]
#[serde(tag = "code")]
pub enum GameError {
    #[error("the settings are outside the supported range")]
    InvalidSettings,
    #[error("it is not this seat's turn")]
    NotYourTurn,
    #[error("the action is not allowed in the current phase")]
    WrongPhase,
    #[error("the location does not exist or is not allowed")]
    InvalidLocation,
    #[error("the piece does not connect to the seat's network")]
    NotConnected,
    #[error("a settlement or city is too close")]
    TooClose,
    #[error("the location is already occupied")]
    Occupied,
    #[error("no pieces of this kind are left")]
    NoPiecesLeft,
    #[error("not enough resources")]
    NotEnoughResources,
    #[error("the bank cannot pay")]
    BankEmpty,
    #[error("the trade is invalid")]
    InvalidTrade,
    #[error("no trade is open")]
    NoTradeOpen,
    #[error("no such card")]
    NoCard,
    #[error("the card cannot be played now")]
    CardNotPlayable,
    #[error("this seat cannot be robbed")]
    InvalidVictim,
    #[error("the discard is invalid")]
    InvalidDiscard,
    #[error("the game is finished")]
    GameFinished,
}
