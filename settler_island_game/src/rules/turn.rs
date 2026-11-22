use rand::Rng;

use crate::error::GameError;
use crate::event::Event;
use crate::game::{Game, Seat};
use crate::phase::Phase;
use crate::rules::{development, production, robber};

const ROBBER_NUMBER: u8 = 7;

pub(crate) fn roll_dice(game: &mut Game, seat: Seat) -> Result<Vec<Event>, GameError> {
    game.require_turn(seat)?;
    if game.phase != Phase::Roll {
        return Err(GameError::WrongPhase);
    }

    let first: u8 = game.rng.random_range(1..=6);
    let second: u8 = game.rng.random_range(1..=6);
    let mut events = vec![Event::DiceRolled {
        seat,
        first,
        second,
    }];
    if first + second == ROBBER_NUMBER {
        events.extend(robber::on_seven(game, seat));
        return Ok(events);
    }
    events.extend(production::produce(game, first + second));
    events.push(game.enter(Phase::Main));
    Ok(events)
}

pub(crate) fn end_turn(game: &mut Game, seat: Seat) -> Result<Vec<Event>, GameError> {
    game.require_turn(seat)?;
    if game.phase != Phase::Main {
        return Err(GameError::WrongPhase);
    }

    development::on_turn_end(game, seat);
    let next = (seat + 1) % game.settings.seats;
    game.turn_number += 1;
    Ok(game.pass_to(next, Phase::Roll))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::action::Action;
    use crate::rules::test_support::after_setup;

    /// Rolls until `wanted` accepts the total, resetting the phase after each roll.
    fn roll_until(game: &Game, wanted: impl Fn(u8) -> bool) -> (Game, Vec<Event>) {
        let mut game = game.clone();
        loop {
            let seat = game.current;
            let events = game.apply(seat, Action::RollDice).unwrap();
            let total = events.iter().find_map(|event| match event {
                Event::DiceRolled { first, second, .. } => Some(first + second),
                _ => None,
            });
            if total.is_some_and(&wanted) {
                return (game, events);
            }
            game.phase = Phase::Roll;
        }
    }

    #[test]
    fn seven_moves_the_robber_without_production() {
        let game = after_setup(4, 6);
        let (game, events) = roll_until(&game, |total| total == 7);

        assert_eq!(game.phase, Phase::MoveRobber { then_steal: true });
        assert!(!events
            .iter()
            .any(|event| matches!(event, Event::ResourcesProduced { .. })));
        assert_eq!(game.legal_actions(game.current).len(), 18);
    }

    #[test]
    fn other_rolls_go_to_main_and_end_turn_passes_on() {
        let game = after_setup(3, 6);
        let (mut game, _) = roll_until(&game, |total| total != 7);

        assert_eq!(game.phase, Phase::Main);
        assert_eq!(game.apply(1, Action::EndTurn), Err(GameError::NotYourTurn));
        assert_eq!(game.apply(0, Action::RollDice), Err(GameError::WrongPhase));
        let events = game.apply(0, Action::EndTurn).unwrap();

        assert_eq!(
            events,
            vec![
                Event::TurnEnded { seat: 0 },
                Event::TurnStarted { seat: 1 },
                Event::PhaseChanged { phase: Phase::Roll }
            ]
        );
        assert_eq!(game.current, 1);
    }

    #[test]
    fn dice_are_seeded_and_vary() {
        let rolls = |seed: u64| {
            let mut game = after_setup(3, seed);
            (0..30)
                .map(|_| {
                    let seat = game.current;
                    let events = game.apply(seat, Action::RollDice).unwrap();
                    game.phase = Phase::Roll;
                    events[0].clone()
                })
                .collect::<Vec<Event>>()
        };

        assert_eq!(rolls(5), rolls(5));
        assert_ne!(rolls(5), rolls(6));
        let distinct: std::collections::BTreeSet<String> =
            rolls(5).iter().map(|event| format!("{event:?}")).collect();
        assert!(distinct.len() > 5);
    }
}
