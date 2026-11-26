use proptest::prelude::*;
use settler_island_bot::{bot_seed, create_bot, play_game, Bot, Difficulty};
use settler_island_game::{GameSettings, Resource};

const CARDS_IN_PLAY: u32 = 95;

fn bots(seats: u8, seed: u64) -> Vec<Box<dyn Bot>> {
    (0..seats)
        .map(|seat| create_bot(Difficulty::Random, bot_seed(seed, usize::from(seat))))
        .collect()
}

fn settings(seats: u8, seed: u64) -> GameSettings {
    GameSettings {
        seats,
        points_to_win: 10,
        seed,
    }
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(24))]

    #[test]
    fn random_bots_never_error_and_keep_95_cards(seed in any::<u64>(), seats in 3u8..=4) {
        let outcome = play_game(settings(seats, seed), bots(seats, seed), 3000)
            .map_err(|error| TestCaseError::fail(error.to_string()))?;

        let view = &outcome.final_view;
        let bank: u32 = Resource::ALL.iter().map(|resource| u32::from(view.bank.get(*resource))).sum();
        let hands: u32 = view.players.iter().map(|player| u32::from(player.resource_count)).sum();
        prop_assert_eq!(bank + hands, CARDS_IN_PLAY);
    }
}

/// Run with `cargo test -p settler_island_bot -- --ignored --nocapture`.
#[test]
#[ignore = "benchmark, reports how many games finish"]
fn benchmark_finished_games() {
    let finished = (0..200u64)
        .filter(|seed| {
            let outcome = play_game(settings(4, *seed), bots(4, *seed), 3000).unwrap();
            outcome.winner.is_some()
        })
        .count();
    println!("finished {finished} of 200 games");
}
