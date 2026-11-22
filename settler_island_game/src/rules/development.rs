use crate::action::Action;
use crate::board::EdgeId;
use crate::error::GameError;
use crate::event::Event;
use crate::game::{Game, Seat};
use crate::resource::Resource;

/// Step 2b.
pub(crate) fn buy(_game: &mut Game, _seat: Seat) -> Result<Vec<Event>, GameError> {
    Err(GameError::NotImplemented)
}

/// Step 2b.
pub(crate) fn play_knight(_game: &mut Game, _seat: Seat) -> Result<Vec<Event>, GameError> {
    Err(GameError::NotImplemented)
}

/// Step 2b.
pub(crate) fn play_road_building(_game: &mut Game, _seat: Seat) -> Result<Vec<Event>, GameError> {
    Err(GameError::NotImplemented)
}

/// Step 2b.
pub(crate) fn play_year_of_plenty(
    _game: &mut Game,
    _seat: Seat,
    _first: Resource,
    _second: Resource,
) -> Result<Vec<Event>, GameError> {
    Err(GameError::NotImplemented)
}

/// Step 2b.
pub(crate) fn play_monopoly(
    _game: &mut Game,
    _seat: Seat,
    _resource: Resource,
) -> Result<Vec<Event>, GameError> {
    Err(GameError::NotImplemented)
}

/// Step 2b: a free road in `Phase::RoadBuilding`.
pub(crate) fn build_free_road(
    _game: &mut Game,
    _seat: Seat,
    _edge: EdgeId,
) -> Result<Vec<Event>, GameError> {
    Err(GameError::NotImplemented)
}

/// Step 2b: called by `EndTurn` before the turn passes on.
pub(crate) fn on_turn_end(_game: &mut Game, _seat: Seat) {}

/// Step 2b: a knight before rolling.
pub(crate) fn legal_before_roll(_game: &Game, _seat: Seat) -> Vec<Action> {
    Vec::new()
}

/// Step 2b: buy and play in `Phase::Main`.
pub(crate) fn legal_main(_game: &Game, _seat: Seat) -> Vec<Action> {
    Vec::new()
}

/// Step 2b: free roads in `Phase::RoadBuilding`.
pub(crate) fn legal_free_roads(_game: &Game, _seat: Seat) -> Vec<Action> {
    Vec::new()
}
