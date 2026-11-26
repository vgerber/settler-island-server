use crate::action::Action;
use crate::board::{CornerId, EdgeId};
use crate::error::GameError;
use crate::event::Event;
use crate::game::{Game, Seat};
use crate::phase::{Phase, SetupRound};
use crate::rules::{building, production};

/// Setup order: the first round seats `0..n`, the second `n-1..=0`, then seat 0 rolls.
pub(crate) fn place_settlement(
    game: &mut Game,
    seat: Seat,
    corner: CornerId,
) -> Result<Vec<Event>, GameError> {
    let round = check_settlement(game, seat, corner)?;
    let mut events = vec![building::place_settlement(game, seat, corner)];
    if round == SetupRound::Second {
        let mut owed = vec![Default::default(); game.players.len()];
        owed[usize::from(seat)] = production::settlement_yield(game, corner);
        events.extend(production::distribute(game, &owed));
    }
    events.push(game.enter(Phase::SetupRoad {
        round,
        settlement: corner,
    }));
    Ok(events)
}

pub(crate) fn place_road(
    game: &mut Game,
    seat: Seat,
    edge: EdgeId,
) -> Result<Vec<Event>, GameError> {
    let round = check_road(game, seat, edge)?;
    let mut events = vec![building::place_road(game, seat, edge)];
    let last_seat = game.settings.seats - 1;
    let next = match round {
        SetupRound::First if seat < last_seat => Some((seat + 1, SetupRound::First)),
        SetupRound::First => Some((seat, SetupRound::Second)),
        SetupRound::Second if seat > 0 => Some((seat - 1, SetupRound::Second)),
        SetupRound::Second => None,
    };
    match next {
        Some((next_seat, round)) => {
            events.extend(game.pass_to(next_seat, Phase::SetupSettlement { round }))
        }
        None => events.extend(game.start_turn(0)),
    }
    Ok(events)
}

pub(crate) fn legal_settlements(game: &Game, seat: Seat) -> Vec<Action> {
    game.board
        .corner_ids()
        .filter(|corner| check_settlement(game, seat, *corner).is_ok())
        .map(|corner| Action::PlaceSettlement { corner })
        .collect()
}

pub(crate) fn legal_roads(game: &Game, seat: Seat) -> Vec<Action> {
    game.board
        .edge_ids()
        .filter(|edge| check_road(game, seat, *edge).is_ok())
        .map(|edge| Action::PlaceRoad { edge })
        .collect()
}

/// Returns the setup round.
fn check_settlement(game: &Game, seat: Seat, corner: CornerId) -> Result<SetupRound, GameError> {
    game.require_turn(seat)?;
    let Phase::SetupSettlement { round } = game.phase else {
        return Err(GameError::WrongPhase);
    };
    building::check_settlement_site(&game.board, corner)?;
    Ok(round)
}

/// Returns the setup round. The road must touch the settlement just placed.
fn check_road(game: &Game, seat: Seat, edge: EdgeId) -> Result<SetupRound, GameError> {
    game.require_turn(seat)?;
    let Phase::SetupRoad { round, settlement } = game.phase else {
        return Err(GameError::WrongPhase);
    };
    let corners = building::check_road_site(&game.board, edge)?;
    if !corners.contains(&settlement) {
        return Err(GameError::NotConnected);
    }
    Ok(round)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rules::test_support::new_game;

    /// Places a settlement and road for whoever is current, always on the first legal spot.
    fn place_first(game: &mut Game) -> Seat {
        let seat = game.current;
        let settlement = game.legal_actions(seat)[0].clone();
        game.apply(seat, settlement).unwrap();
        let road = game.legal_actions(seat)[0].clone();
        game.apply(seat, road).unwrap();
        seat
    }

    #[test]
    fn setup_follows_snake_order() {
        for (seats, expected) in [
            (3, vec![0, 1, 2, 2, 1, 0]),
            (4, vec![0, 1, 2, 3, 3, 2, 1, 0]),
        ] {
            let mut game = new_game(seats, 1);
            let order: Vec<Seat> = (0..expected.len())
                .map(|_| place_first(&mut game))
                .collect();

            assert_eq!(order, expected);
            assert_eq!(game.phase, Phase::Roll);
            assert_eq!(game.current, 0);
            assert_eq!(game.legal_actions(0), vec![Action::RollDice]);
        }
    }

    #[test]
    fn the_last_setup_road_starts_the_first_turn_like_any_other() {
        let mut game = new_game(3, 1);
        for _ in 0..5 {
            place_first(&mut game);
        }
        assert_eq!(
            game.phase,
            Phase::SetupSettlement {
                round: SetupRound::Second
            }
        );
        let settlement = game.legal_actions(0)[0].clone();
        game.apply(0, settlement).unwrap();
        let road = game.legal_actions(0)[0].clone();

        let events = game.apply(0, road).unwrap();

        assert_eq!(
            events[1..],
            [
                Event::TurnEnded { seat: 0 },
                Event::TurnStarted { seat: 0 },
                Event::PhaseChanged { phase: Phase::Roll }
            ]
        );
        assert_eq!(game.turn_number, 1);
    }

    #[test]
    fn setup_road_must_touch_the_new_settlement() {
        let mut game = new_game(3, 2);
        let corner = CornerId(10);
        game.apply(0, Action::PlaceSettlement { corner }).unwrap();
        let touching = game.board.corner(corner).unwrap().edges.clone();
        let elsewhere = game
            .board
            .edge_ids()
            .find(|edge| !touching.contains(edge))
            .unwrap();

        let before = game.clone();
        assert_eq!(
            game.apply(0, Action::PlaceRoad { edge: elsewhere }),
            Err(GameError::NotConnected)
        );
        assert_eq!(game, before);
        let legal: Vec<Action> = touching
            .iter()
            .map(|edge| Action::PlaceRoad { edge: *edge })
            .collect();
        assert_eq!(game.legal_actions(0), legal);
    }

    #[test]
    fn only_the_second_settlement_yields_resources() {
        let mut game = new_game(3, 4);
        for _ in 0..3 {
            place_first(&mut game);
        }
        assert!(game.players.iter().all(|player| player.hand.is_empty()));

        let seat = game.current;
        let corner = game
            .board
            .corner_ids()
            .find(|corner| {
                game.board.corner(*corner).unwrap().tiles.len() == 3
                    && building::check_settlement_site(&game.board, *corner).is_ok()
            })
            .unwrap();
        let expected = production::settlement_yield(&game, corner);
        let events = game
            .apply(seat, Action::PlaceSettlement { corner })
            .unwrap();

        assert!(expected.total() >= 2);
        assert_eq!(game.players[usize::from(seat)].hand, expected);
        assert!(events.contains(&Event::ResourcesProduced {
            seat,
            resources: expected
        }));
        assert_eq!(game.bank.total() + expected.total(), 95);
    }

    #[test]
    fn distance_rule_rejects_neighbouring_corner_in_setup() {
        let mut game = new_game(3, 3);
        let corner = CornerId(20);
        game.apply(0, Action::PlaceSettlement { corner }).unwrap();
        let edge = game.board.corner(corner).unwrap().edges[0];
        game.apply(0, Action::PlaceRoad { edge }).unwrap();
        let neighbor = game.board.corner(corner).unwrap().neighbors[0];

        let before = game.clone();
        assert_eq!(
            game.apply(1, Action::PlaceSettlement { corner: neighbor }),
            Err(GameError::TooClose)
        );
        assert_eq!(
            game.apply(1, Action::PlaceSettlement { corner }),
            Err(GameError::Occupied)
        );
        assert_eq!(
            game.apply(
                2,
                Action::PlaceSettlement {
                    corner: CornerId(0)
                }
            ),
            Err(GameError::NotYourTurn)
        );
        assert_eq!(game, before);
        assert!(!game
            .legal_actions(1)
            .contains(&Action::PlaceSettlement { corner: neighbor }));
    }
}
