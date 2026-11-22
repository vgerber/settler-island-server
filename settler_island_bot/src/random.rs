use rand::seq::IndexedRandom;
use rand::{Rng, SeedableRng};
use rand_chacha::ChaCha8Rng;
use settler_island_game::{Action, PlayerView};

use crate::Bot;

pub(crate) struct RandomBot {
    rng: ChaCha8Rng,
}

impl RandomBot {
    pub(crate) fn new(seed: u64) -> RandomBot {
        RandomBot {
            rng: ChaCha8Rng::seed_from_u64(seed),
        }
    }
}

impl Bot for RandomBot {
    fn choose(&mut self, _view: &PlayerView, legal: &[Action]) -> Action {
        // Half of the time ending the turn is not an option, so games progress.
        let skip_end_turn = self.rng.random_bool(0.5);
        let others: Vec<&Action> = legal
            .iter()
            .filter(|action| **action != Action::EndTurn)
            .collect();
        let pool: Vec<&Action> = if skip_end_turn && !others.is_empty() {
            others
        } else {
            legal.iter().collect()
        };
        // An empty list never happens in play; ending the turn is the harmless answer.
        pool.choose(&mut self.rng)
            .map_or(Action::EndTurn, |action| (*action).clone())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use settler_island_game::{EdgeId, Game, GameSettings};

    fn view() -> PlayerView {
        let settings = GameSettings {
            seats: 3,
            points_to_win: 10,
            seed: 1,
        };
        Game::new(settings).unwrap().view(Some(0))
    }

    #[test]
    fn same_seed_same_choices_and_both_kinds_are_chosen() {
        let legal = vec![
            Action::RollDice,
            Action::EndTurn,
            Action::BuildRoad { edge: EdgeId(3) },
        ];
        let mut first = RandomBot::new(5);
        let mut second = RandomBot::new(5);
        let view = view();
        let mut seen_end_turn = false;
        let mut seen_other = false;
        for _ in 0..200 {
            let choice = first.choose(&view, &legal);
            assert_eq!(choice, second.choose(&view, &legal));
            assert!(legal.contains(&choice));
            seen_end_turn |= choice == Action::EndTurn;
            seen_other |= choice != Action::EndTurn;
        }
        assert!(seen_end_turn && seen_other);
    }

    #[test]
    fn single_legal_action_is_taken() {
        let mut bot = RandomBot::new(9);
        let view = view();
        for _ in 0..20 {
            assert_eq!(bot.choose(&view, &[Action::RollDice]), Action::RollDice);
        }
    }
}
