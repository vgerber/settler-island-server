use crate::action::Action;
use crate::board::TileId;
use crate::error::GameError;
use crate::event::Event;
use crate::game::{Game, Seat};
use crate::phase::Phase;

/// Moves the robber to another tile. Stealing after it arrives in step 2d; until then the turn continues in `Main`.
pub(crate) fn move_robber(
    game: &mut Game,
    seat: Seat,
    tile: TileId,
) -> Result<Vec<Event>, GameError> {
    check_move(game, seat, tile)?;
    game.board.set_robber(tile);
    Ok(vec![
        Event::RobberMoved { seat, tile },
        game.enter(Phase::Main),
    ])
}

pub(crate) fn legal_moves(game: &Game, seat: Seat) -> Vec<Action> {
    game.board
        .tile_ids()
        .filter(|tile| check_move(game, seat, *tile).is_ok())
        .map(|tile| Action::MoveRobber { tile })
        .collect()
}

/// Discard and steal arrive in step 2d.
pub(crate) fn not_implemented() -> Result<Vec<Event>, GameError> {
    Err(GameError::NotImplemented)
}

fn check_move(game: &Game, seat: Seat, tile: TileId) -> Result<(), GameError> {
    game.require_turn(seat)?;
    if !matches!(game.phase, Phase::MoveRobber { .. }) {
        return Err(GameError::WrongPhase);
    }
    if game.board.tile(tile).is_none() || tile == game.board.robber() {
        return Err(GameError::InvalidLocation);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rules::test_support::after_setup;

    #[test]
    fn robber_must_leave_its_tile() {
        let mut game = after_setup(4, 12);
        game.phase = Phase::MoveRobber { then_steal: true };
        let seat = game.current;
        let start = game.board.robber();

        let before = game.clone();
        assert_eq!(
            game.apply(seat, Action::MoveRobber { tile: start }),
            Err(GameError::InvalidLocation)
        );
        assert_eq!(
            game.apply(seat, Action::MoveRobber { tile: TileId(19) }),
            Err(GameError::InvalidLocation)
        );
        assert_eq!(game, before);

        let target = TileId((start.0 + 1) % 19);
        let events = game
            .apply(seat, Action::MoveRobber { tile: target })
            .unwrap();
        assert_eq!(events[0], Event::RobberMoved { seat, tile: target });
        assert_eq!(game.board.robber(), target);
        assert_eq!(game.phase, Phase::Main);
    }
}
