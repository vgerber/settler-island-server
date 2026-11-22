use settler_island_bot::{create_bot, play_game, Bot, Difficulty, GameOutcome};
use settler_island_game::{GameSettings, Seat};

const MAX_ACTIONS: u32 = 3000;

/// The heuristic bot sits at `seed % 4`, so every seat position is covered.
fn heuristic_seat(seed: u64) -> Seat {
    (seed % 4) as Seat
}

fn play(seed: u64) -> GameOutcome {
    let settings = GameSettings {
        seats: 4,
        points_to_win: 10,
        seed,
    };
    let bots: Vec<Box<dyn Bot>> = (0..4u8)
        .map(|seat| {
            let difficulty = if seat == heuristic_seat(seed) {
                Difficulty::Heuristic
            } else {
                Difficulty::Random
            };
            create_bot(
                difficulty,
                seed.wrapping_mul(31).wrapping_add(u64::from(seat)),
            )
        })
        .collect();
    // A rejected action, offers included, is an error and fails the test.
    play_game(settings, bots, MAX_ACTIONS).unwrap()
}

/// Wins of the heuristic seat and the sorted game lengths in turns.
fn wins(seeds: std::ops::Range<u64>) -> (usize, Vec<u32>) {
    let mut won = 0;
    let mut turns = Vec::new();
    for seed in seeds {
        let outcome = play(seed);
        if outcome.winner == Some(heuristic_seat(seed)) {
            won += 1;
        }
        turns.push(outcome.final_view.turn_number);
    }
    turns.sort_unstable();
    (won, turns)
}

#[test]
fn heuristic_bot_beats_three_random_bots() {
    let (won, _) = wins(0..20);

    assert!(won >= 15, "won {won} of 20");
}

#[test]
fn four_heuristic_bots_finish_their_games() {
    for seed in 0..10 {
        let settings = GameSettings {
            seats: 4,
            points_to_win: 10,
            seed,
        };
        let bots = (0..4)
            .map(|seat| create_bot(Difficulty::Heuristic, seat))
            .collect();

        let outcome = play_game(settings, bots, MAX_ACTIONS).unwrap();

        assert!(outcome.winner.is_some(), "seed {seed} did not finish");
    }
}

/// Run with `cargo test --release -p settler_island_bot -- --ignored --nocapture`.
#[test]
#[ignore = "benchmark, reports win rate and median game length"]
fn benchmark_heuristic_against_random() {
    let (won, turns) = wins(0..200);

    println!(
        "heuristic won {won} of 200, median game length {} turns",
        turns[turns.len() / 2]
    );
    assert!(won >= 180, "won {won} of 200");
}
