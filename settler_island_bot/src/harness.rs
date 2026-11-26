use settler_island_game::{
    Action, Game, GameError, GameRecord, GameSettings, Phase, PlayerView, RecordEntry, Seat,
};

use crate::Bot;

#[derive(Debug, Clone, PartialEq)]
pub struct GameOutcome {
    /// `None` when `max_actions` ran out first.
    pub winner: Option<Seat>,
    pub actions: u32,
    pub record: GameRecord,
    /// Spectator view of the final state.
    pub final_view: PlayerView,
}

#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub enum PlayError {
    #[error("{bots} bots for {seats} seats")]
    BotCountMismatch { seats: u8, bots: usize },
    #[error("game rejected settings: {0}")]
    Settings(GameError),
    #[error("seat {seat} was offered no legal action")]
    NoLegalAction { seat: Seat },
    #[error("seat {seat} played {action:?} from the legal list and was rejected: {error}")]
    IllegalAction {
        seat: Seat,
        action: Box<Action>,
        error: GameError,
    },
}

/// Plays until a winner or `max_actions`; the first pending seat acts each step.
pub fn play_game(
    settings: GameSettings,
    mut bots: Vec<Box<dyn Bot>>,
    max_actions: u32,
) -> Result<GameOutcome, PlayError> {
    if bots.len() != usize::from(settings.seats) {
        return Err(PlayError::BotCountMismatch {
            seats: settings.seats,
            bots: bots.len(),
        });
    }
    let mut game = Game::new(settings).map_err(PlayError::Settings)?;
    let mut record = GameRecord::new(&game);
    let mut actions = 0;
    while actions < max_actions {
        let Some(seat) = game.pending_seats().first().copied() else {
            break;
        };
        let legal = game.legal_actions(seat);
        if legal.is_empty() {
            return Err(PlayError::NoLegalAction { seat });
        }
        let view = game.view(Some(seat));
        let action = bots[usize::from(seat)].choose(&view, &legal);
        let events =
            game.apply(seat, action.clone())
                .map_err(|error| PlayError::IllegalAction {
                    seat,
                    action: Box::new(action.clone()),
                    error,
                })?;
        record.push_entry(RecordEntry {
            index: u32::try_from(record.entries.len()).unwrap_or(u32::MAX),
            seat,
            action,
            events,
        });
        actions += 1;
    }
    let winner = match game.phase() {
        Phase::Finished { winner } => Some(*winner),
        _ => None,
    };
    Ok(GameOutcome {
        winner,
        actions,
        record,
        final_view: game.view(None),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{create_bot, Difficulty};
    use settler_island_game::replay;

    struct Fixed(Action);

    impl Bot for Fixed {
        fn choose(&mut self, _view: &PlayerView, _legal: &[Action]) -> Action {
            self.0.clone()
        }
    }

    fn settings(seats: u8, seed: u64) -> GameSettings {
        GameSettings {
            seats,
            points_to_win: 10,
            seed,
        }
    }

    #[test]
    fn rejected_action_is_reported_not_swallowed() {
        let bots: Vec<Box<dyn Bot>> = (0..3)
            .map(|_| Box::new(Fixed(Action::RollDice)) as Box<dyn Bot>)
            .collect();

        let result = play_game(settings(3, 1), bots, 10);

        assert!(matches!(
            result,
            Err(PlayError::IllegalAction { seat: 0, .. })
        ));
    }

    #[test]
    fn wrong_bot_count_is_an_error() {
        let result = play_game(settings(4, 1), Vec::new(), 10);

        assert_eq!(
            result.unwrap_err(),
            PlayError::BotCountMismatch { seats: 4, bots: 0 }
        );
    }

    #[test]
    fn stops_at_max_actions_and_record_replays_to_the_same_state() {
        let bots = (0..4)
            .map(|seat| create_bot(Difficulty::Random, seat))
            .collect();

        let outcome = play_game(settings(4, 7), bots, 200).unwrap();

        assert_eq!(outcome.actions as usize, outcome.record.entries.len());
        assert!(outcome.actions <= 200);
        let fresh = Game::new(settings(4, 7)).unwrap();
        let game = replay(fresh, &outcome.record.entries).unwrap();
        assert_eq!(game.view(None), outcome.final_view);
    }
}
