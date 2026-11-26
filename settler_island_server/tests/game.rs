mod common;

use std::time::Duration;

use common::{play_as, start, test_config, Client, Play};
use settler_island_bot::create_bot;
use settler_island_game::{
    replay, Action, Game, GameSettings, Phase, PlayerView, RecordEntry, Seat,
};
use settler_island_protocol::{ClientMessage, Difficulty, ServerMessage};
use settler_island_server::Config;

const SEED: u64 = 11;
/// The lowest goal the rules allow, so random play finishes in a few hundred actions.
const POINTS_TO_WIN: u8 = 3;
/// Some random games wander; another attempt with a different human trajectory is cheap.
const ATTEMPTS: u64 = 8;
const MAX_UPDATES_PER_ATTEMPT: u32 = 1500;

struct Finished {
    seat: Seat,
    view: PlayerView,
    actions: Vec<RecordEntry>,
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn one_human_and_three_bots_play_a_seeded_game_to_a_win() {
    let config = Config {
        seed: Some(SEED),
        messages_per_second: 10_000,
        ..test_config()
    };
    let address = start(config).await;
    let play = async {
        for attempt in 0..ATTEMPTS {
            if let Some(finished) = play_once(address, attempt).await {
                return finished;
            }
        }
        panic!("no game finished in {ATTEMPTS} attempts");
    };
    let finished = tokio::time::timeout(Duration::from_secs(45), play)
        .await
        .expect("the game did not finish in time");

    let Phase::Finished { winner } = finished.view.phase else {
        panic!("the last update must show the finished game");
    };
    assert_eq!(finished.view.own.map(|own| own.seat), Some(finished.seat));
    let settings = GameSettings {
        seats: 4,
        points_to_win: POINTS_TO_WIN,
        seed: SEED,
    };
    let replayed =
        replay(Game::new(settings).unwrap(), &finished.actions).expect("the record replays");
    assert_eq!(replayed.phase(), &Phase::Finished { winner });
    // The human's view hides other seats' victory point cards, so check the winner's own total.
    let winner_view = replayed.view(Some(winner));
    assert!(winner_view.players[usize::from(winner)].points >= POINTS_TO_WIN);
}

/// Plays one game with the random bot logic for the human; `None` when it runs too long.
async fn play_once(address: std::net::SocketAddr, attempt: u64) -> Option<Finished> {
    let (mut client, _) = Client::welcomed(address, "Human").await;
    let (_, dealt) = client
        .start_with_bots("Seeded", 4, Some(POINTS_TO_WIN), Difficulty::Random)
        .await;
    let mut human = create_bot(Difficulty::Random, 1000 + attempt);
    let mut play = Play::new(dealt.view, dealt.legal_actions);
    play_as(&mut client, human.as_mut(), &mut play, |play| {
        play.finished() || play.updates >= MAX_UPDATES_PER_ATTEMPT as usize
    })
    .await;
    if play.finished() {
        let actions = full_record(&mut client).await;
        return Some(Finished {
            seat: dealt.seat,
            view: play.view,
            actions,
        });
    }
    client
        .request(|request_id| ClientMessage::LeaveLobby { request_id })
        .await;
    None
}

async fn full_record(client: &mut Client) -> Vec<RecordEntry> {
    let reply = client
        .request(|request_id| ClientMessage::GetRecord { request_id })
        .await;
    let ServerMessage::Record { record, .. } = reply else {
        panic!("expected Record, got {reply:?}");
    };
    record.entries
}

/// How long the human leaves a bot's offer unanswered before checking that it is still open.
const UNANSWERED: Duration = Duration::from_millis(800);

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn a_bot_offer_stays_open_until_the_asked_human_answers() {
    let config = Config {
        seed: Some(SEED),
        messages_per_second: 10_000,
        trade_answer_time: Duration::from_secs(5),
        ..test_config()
    };
    let address = start(config).await;
    let (mut client, _) = Client::welcomed(address, "Human").await;
    let (_, dealt) = client
        .start_with_bots("Traders", 4, None, Difficulty::Heuristic)
        .await;
    let seat = dealt.seat;
    let mut human = create_bot(Difficulty::Random, 3);
    let mut play = Play::new(dealt.view, dealt.legal_actions);
    let offered_by_bot = |play: &Play| {
        let by_bot = play
            .view
            .phase
            .trade_offer()
            .is_some_and(|offer| offer.offerer != seat);
        by_bot && play.legal.contains(&Action::RejectTrade)
    };
    play_as(&mut client, human.as_mut(), &mut play, |play| {
        offered_by_bot(play)
            || play.finished()
            || play.updates >= MAX_UPDATES_PER_ATTEMPT as usize * 4
    })
    .await;
    assert!(offered_by_bot(&play), "no bot offered the human a trade");
    assert_offer_stays_open(&mut client).await;
    client
        .send(|request_id| ClientMessage::Act {
            request_id,
            action: Action::RejectTrade,
        })
        .await;
}

/// Every update while the human stays silent still shows the offer.
async fn assert_offer_stays_open(client: &mut Client) {
    let deadline = tokio::time::Instant::now() + UNANSWERED;
    while let Ok(message) = tokio::time::timeout_at(deadline, client.receive()).await {
        if let ServerMessage::GameUpdate { view, .. } = message {
            assert!(
                view.phase.trade_offer().is_some(),
                "the bot closed its offer before the human answered"
            );
        }
    }
}
