use crate::board::BuildingKind;
use crate::event::Event;
use crate::game::{Game, Seat};
use crate::phase::Phase;

/// Points everyone can see. Step 1 counts buildings only; step 2c adds longest road, largest army and cards.
pub(crate) fn public_points(game: &Game, seat: Seat) -> u8 {
    game.board
        .corner_ids()
        .filter_map(|corner| game.board.building(corner))
        .filter(|building| building.seat == seat)
        .map(|building| match building.kind {
            BuildingKind::Settlement => 1,
            BuildingKind::City => 2,
        })
        .sum()
}

/// Runs after every accepted action: awards (step 2c) and the win check for the seat whose turn it is.
pub(crate) fn after_action(game: &mut Game) -> Vec<Event> {
    if matches!(game.phase, Phase::Finished { .. }) {
        return Vec::new();
    }
    let seat = game.current;
    check_winner(game, seat)
}

/// Ends the game when `seat` reached the target during its own turn.
fn check_winner(game: &mut Game, seat: Seat) -> Vec<Event> {
    let points = public_points(game, seat);
    if points < game.settings.points_to_win {
        return Vec::new();
    }
    vec![
        Event::GameWon { seat, points },
        game.enter(Phase::Finished { winner: seat }),
    ]
}
