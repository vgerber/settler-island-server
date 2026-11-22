use crate::action::Action;
use crate::error::GameError;
use crate::event::Event;
use crate::game::{Game, Seat};
use crate::resource::{Resource, ResourceCounts};

/// Step 2a: bank and port trade.
pub(crate) fn bank_trade(
    _game: &mut Game,
    _seat: Seat,
    _give: Resource,
    _receive: Resource,
) -> Result<Vec<Event>, GameError> {
    Err(GameError::NotImplemented)
}

/// Step 2a: opens a player trade.
pub(crate) fn offer_trade(
    _game: &mut Game,
    _seat: Seat,
    _give: ResourceCounts,
    _receive: ResourceCounts,
    _to: Option<Seat>,
) -> Result<Vec<Event>, GameError> {
    Err(GameError::NotImplemented)
}

/// Step 2a: an addressed seat accepts or rejects the open trade.
pub(crate) fn answer_trade(
    _game: &mut Game,
    _seat: Seat,
    _accepted: bool,
) -> Result<Vec<Event>, GameError> {
    Err(GameError::NotImplemented)
}

/// Step 2a: the offerer completes the trade with an accepting seat.
pub(crate) fn confirm_trade(
    _game: &mut Game,
    _seat: Seat,
    _with: Seat,
) -> Result<Vec<Event>, GameError> {
    Err(GameError::NotImplemented)
}

/// Step 2a.
pub(crate) fn cancel_trade(_game: &mut Game, _seat: Seat) -> Result<Vec<Event>, GameError> {
    Err(GameError::NotImplemented)
}

/// Step 2a: bank trades available in `Phase::Main`.
pub(crate) fn legal_main(_game: &Game, _seat: Seat) -> Vec<Action> {
    Vec::new()
}

/// Step 2a: answers, confirm and cancel in `Phase::TradeOffered`.
pub(crate) fn legal_answers(_game: &Game, _seat: Seat) -> Vec<Action> {
    Vec::new()
}
