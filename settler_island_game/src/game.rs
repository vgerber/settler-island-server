use rand::seq::SliceRandom;
use rand::SeedableRng;
use rand_chacha::ChaCha8Rng;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

use crate::action::Action;
use crate::board::{self, Board};
use crate::error::GameError;
use crate::event::Event;
use crate::phase::Phase;
use crate::resource::ResourceCounts;
use crate::rules::{building, development, robber, scoring, setup, trade, turn};
use crate::view::PlayerView;

/// Player index `0..seats`.
pub type Seat = u8;

const MIN_SEATS: u8 = 3;
const MAX_SEATS: u8 = 4;
/// Below this the setup settlements alone could win.
const MIN_POINTS_TO_WIN: u8 = 3;
const BANK_PER_RESOURCE: u8 = 19;
const ROADS_PER_PLAYER: u8 = 15;
const SETTLEMENTS_PER_PLAYER: u8 = 5;
const CITIES_PER_PLAYER: u8 = 4;
const DECK: [(DevelopmentCard, usize); 5] = [
    (DevelopmentCard::Knight, 14),
    (DevelopmentCard::VictoryPoint, 5),
    (DevelopmentCard::RoadBuilding, 2),
    (DevelopmentCard::YearOfPlenty, 2),
    (DevelopmentCard::Monopoly, 2),
];

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub enum DevelopmentCard {
    Knight,
    RoadBuilding,
    YearOfPlenty,
    Monopoly,
    VictoryPoint,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub struct GameSettings {
    pub seats: u8,
    pub points_to_win: u8,
    pub seed: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub struct PlayerState {
    pub hand: ResourceCounts,
    pub roads_left: u8,
    pub settlements_left: u8,
    pub cities_left: u8,
    pub development_cards: Vec<DevelopmentCard>,
    /// Bought this turn: not playable until the next turn (step 2b moves them into `development_cards`).
    pub new_development_cards: Vec<DevelopmentCard>,
    pub played_development_card_this_turn: bool,
    pub knights_played: u8,
}

/// An open player trade (step 2a).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub struct TradeOffer {
    pub seat: Seat,
    pub give: ResourceCounts,
    pub receive: ResourceCounts,
    pub to: Option<Seat>,
    pub answers: Vec<(Seat, bool)>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct Game {
    pub(crate) settings: GameSettings,
    pub(crate) board: Board,
    pub(crate) players: Vec<PlayerState>,
    pub(crate) phase: Phase,
    pub(crate) current: Seat,
    pub(crate) bank: ResourceCounts,
    pub(crate) deck: Vec<DevelopmentCard>,
    /// The schema leaves the RNG state out: it is opaque and only snapshots carry it.
    #[schemars(skip)]
    pub(crate) rng: ChaCha8Rng,
    pub(crate) turn_number: u32,
    /// Whether the current seat rolled this turn; a knight before the roll returns to `Phase::Roll`.
    pub(crate) dice_rolled: bool,
    pub(crate) trade: Option<TradeOffer>,
    pub(crate) longest_road: Option<Seat>,
    pub(crate) largest_army: Option<Seat>,
}

impl Game {
    pub fn new(settings: GameSettings) -> Result<Game, GameError> {
        let seats_supported = (MIN_SEATS..=MAX_SEATS).contains(&settings.seats);
        if !seats_supported || settings.points_to_win < MIN_POINTS_TO_WIN {
            return Err(GameError::InvalidSettings);
        }

        let mut rng = ChaCha8Rng::seed_from_u64(settings.seed);
        let board = board::generate(&mut rng);
        let mut deck: Vec<DevelopmentCard> = DECK
            .iter()
            .flat_map(|(card, count)| std::iter::repeat_n(*card, *count))
            .collect();
        deck.shuffle(&mut rng);
        let player = PlayerState {
            hand: ResourceCounts::default(),
            roads_left: ROADS_PER_PLAYER,
            settlements_left: SETTLEMENTS_PER_PLAYER,
            cities_left: CITIES_PER_PLAYER,
            development_cards: Vec::new(),
            new_development_cards: Vec::new(),
            played_development_card_this_turn: false,
            knights_played: 0,
        };

        Ok(Game {
            players: vec![player; usize::from(settings.seats)],
            settings,
            board,
            phase: Phase::SetupSettlement { round: 1 },
            current: 0,
            bank: ResourceCounts::new([BANK_PER_RESOURCE; 5]),
            deck,
            rng,
            turn_number: 0,
            dice_rolled: false,
            trade: None,
            longest_road: None,
            largest_army: None,
        })
    }

    /// Validates first and mutates only on success, so an `Err` leaves the game unchanged.
    pub fn apply(&mut self, seat: Seat, action: Action) -> Result<Vec<Event>, GameError> {
        if matches!(self.phase, Phase::Finished { .. }) {
            return Err(GameError::GameFinished);
        }
        let mut events = match action {
            Action::PlaceSettlement { corner } => setup::place_settlement(self, seat, corner),
            Action::PlaceRoad { edge } => setup::place_road(self, seat, edge),
            Action::RollDice => turn::roll_dice(self, seat),
            Action::EndTurn => turn::end_turn(self, seat),
            Action::BuildRoad { edge } if matches!(self.phase, Phase::RoadBuilding { .. }) => {
                development::build_free_road(self, seat, edge)
            }
            Action::BuildRoad { edge } => building::build_road(self, seat, edge),
            Action::BuildSettlement { corner } => building::build_settlement(self, seat, corner),
            Action::BuildCity { corner } => building::build_city(self, seat, corner),
            Action::MoveRobber { tile } => robber::move_robber(self, seat, tile),
            Action::Steal { victim } => robber::steal(self, seat, victim),
            Action::Discard { resources } => robber::discard(self, seat, resources),
            Action::BankTrade { give, receive } => trade::bank_trade(self, seat, give, receive),
            Action::OfferTrade { give, receive, to } => {
                trade::offer_trade(self, seat, give, receive, to)
            }
            Action::AcceptTrade => trade::answer_trade(self, seat, true),
            Action::RejectTrade => trade::answer_trade(self, seat, false),
            Action::ConfirmTrade { with } => trade::confirm_trade(self, seat, with),
            Action::CancelTrade => trade::cancel_trade(self, seat),
            Action::BuyDevelopmentCard => development::buy(self, seat),
            Action::PlayKnight => development::play_knight(self, seat),
            Action::PlayRoadBuilding => development::play_road_building(self, seat),
            Action::PlayYearOfPlenty { first, second } => {
                development::play_year_of_plenty(self, seat, first, second)
            }
            Action::PlayMonopoly { resource } => development::play_monopoly(self, seat, resource),
        }?;
        events.extend(scoring::after_action(self));
        Ok(events)
    }

    /// Every listed action is accepted by `apply`. Leaves out `OfferTrade`, whose choices are open-ended.
    pub fn legal_actions(&self, seat: Seat) -> Vec<Action> {
        if !self.pending_seats().contains(&seat) {
            return Vec::new();
        }
        match &self.phase {
            Phase::SetupSettlement { .. } => setup::legal_settlements(self, seat),
            Phase::SetupRoad { .. } => setup::legal_roads(self, seat),
            Phase::Roll => {
                let mut actions = vec![Action::RollDice];
                actions.extend(development::legal_before_roll(self, seat));
                actions
            }
            Phase::Main => {
                let mut actions = building::legal_builds(self, seat);
                actions.extend(trade::legal_main(self, seat));
                actions.extend(development::legal_main(self, seat));
                actions.push(Action::EndTurn);
                actions
            }
            Phase::MoveRobber { .. } => robber::legal_moves(self, seat),
            Phase::Discard { .. } => robber::legal_discards(self, seat),
            Phase::Steal { .. } => robber::legal_steals(self, seat),
            Phase::RoadBuilding { .. } => development::legal_free_roads(self, seat),
            Phase::TradeOffered => trade::legal_answers(self, seat),
            Phase::Finished { .. } => Vec::new(),
        }
    }

    /// The seats that must act now.
    pub fn pending_seats(&self) -> Vec<Seat> {
        match &self.phase {
            Phase::Finished { .. } => Vec::new(),
            Phase::Discard { remaining } => remaining
                .iter()
                .filter(|(_, count)| *count > 0)
                .map(|(seat, _)| *seat)
                .collect(),
            Phase::TradeOffered => self.trade_pending_seats(),
            _ => vec![self.current],
        }
    }

    pub fn view(&self, seat: Option<Seat>) -> PlayerView {
        PlayerView::of(self, seat)
    }

    pub fn phase(&self) -> &Phase {
        &self.phase
    }

    /// The open player trade while the phase is `TradeOffered`.
    pub fn trade(&self) -> Option<&TradeOffer> {
        self.trade.as_ref()
    }

    pub fn current_seat(&self) -> Seat {
        self.current
    }

    pub fn board(&self) -> &Board {
        &self.board
    }

    /// Addressed seats that have not answered, plus the offerer who can confirm or cancel.
    fn trade_pending_seats(&self) -> Vec<Seat> {
        let Some(offer) = &self.trade else {
            return vec![self.current];
        };
        let mut seats: Vec<Seat> = (0..self.settings.seats)
            .filter(|seat| *seat != offer.seat)
            .filter(|seat| offer.to.is_none_or(|addressed| addressed == *seat))
            .filter(|seat| offer.answers.iter().all(|(answered, _)| answered != seat))
            .collect();
        seats.push(offer.seat);
        seats
    }

    pub(crate) fn player(&self, seat: Seat) -> Result<&PlayerState, GameError> {
        self.players
            .get(usize::from(seat))
            .ok_or(GameError::NotYourTurn)
    }

    pub(crate) fn require_turn(&self, seat: Seat) -> Result<(), GameError> {
        if seat != self.current {
            return Err(GameError::NotYourTurn);
        }
        Ok(())
    }

    /// Moves `cost` from the seat's hand to the bank; callers have checked that the hand covers it.
    pub(crate) fn pay_to_bank(&mut self, seat: Seat, cost: ResourceCounts) -> Event {
        let paid = self
            .players
            .get_mut(usize::from(seat))
            .is_some_and(|player| player.hand.try_remove(&cost).is_ok());
        if paid {
            self.bank.deposit(&cost);
        }
        Event::ResourcesPaid {
            seat,
            resources: cost,
        }
    }

    /// The phase a robber or card interruption returns to: `Main` after the roll, `Roll` before it.
    pub(crate) fn turn_phase(&self) -> Phase {
        if self.dice_rolled {
            return Phase::Main;
        }
        Phase::Roll
    }

    /// Hands the turn to `seat` (if it changes) and enters `phase`.
    pub(crate) fn pass_to(&mut self, seat: Seat, phase: Phase) -> Vec<Event> {
        let mut events = Vec::new();
        if seat != self.current {
            events.push(Event::TurnEnded { seat: self.current });
            self.current = seat;
            events.push(Event::TurnStarted { seat });
        }
        events.push(self.enter(phase));
        events
    }

    pub(crate) fn enter(&mut self, phase: Phase) -> Event {
        self.phase = phase.clone();
        Event::PhaseChanged { phase }
    }
}

#[cfg(test)]
mod tests {
    use proptest::prelude::*;

    use super::*;
    use crate::board::{CornerId, EdgeId, TileId};
    use crate::rules::test_support::{after_setup, give, main_phase_game, new_game};

    const ACTION_LIMIT: usize = 2000;

    fn resource_total(game: &Game) -> u32 {
        game.bank.total()
            + game
                .players
                .iter()
                .map(|player| player.hand.total())
                .sum::<u32>()
    }

    /// Every step-1 action kind with a few arguments, valid or not.
    fn probe_actions() -> Vec<Action> {
        let mut actions = vec![
            Action::RollDice,
            Action::EndTurn,
            Action::BuildRoad { edge: EdgeId(71) },
            Action::BuildSettlement {
                corner: CornerId(53),
            },
            Action::BuildCity {
                corner: CornerId(0),
            },
        ];
        for index in [0, 7, 30, 200] {
            actions.push(Action::PlaceSettlement {
                corner: CornerId(index),
            });
            actions.push(Action::PlaceRoad {
                edge: EdgeId(index),
            });
            actions.push(Action::BuildRoad {
                edge: EdgeId(index),
            });
            actions.push(Action::BuildSettlement {
                corner: CornerId(index),
            });
            actions.push(Action::BuildCity {
                corner: CornerId(index),
            });
            actions.push(Action::MoveRobber {
                tile: TileId(index),
            });
        }
        actions
    }

    #[test]
    fn new_rejects_unsupported_settings() {
        for (seats, points_to_win) in [(2, 10), (5, 10), (4, 2)] {
            let settings = GameSettings {
                seats,
                points_to_win,
                seed: 1,
            };
            assert_eq!(Game::new(settings), Err(GameError::InvalidSettings));
        }
    }

    #[test]
    fn errors_leave_the_game_unchanged() {
        let mut robber = main_phase_game(3, 8);
        robber.phase = Phase::MoveRobber { then_steal: true };
        // Full hands, so a rule that pays before validating would show up.
        let mut rich = main_phase_game(4, 8);
        for seat in 0..4 {
            give(&mut rich, seat, ResourceCounts::new([3, 3, 3, 3, 3]));
        }
        let states = vec![new_game(3, 8), after_setup(4, 8), rich, robber];

        let mut rejected = 0;
        for game in states {
            for seat in 0..5 {
                for action in probe_actions() {
                    let mut attempt = game.clone();
                    if attempt.apply(seat, action.clone()).is_err() {
                        rejected += 1;
                        assert_eq!(attempt, game, "seat {seat} {action:?}");
                    }
                }
            }
        }
        assert!(rejected > 400);
    }

    #[test]
    fn finished_game_rejects_everything() {
        let mut game = main_phase_game(3, 3);
        game.phase = Phase::Finished { winner: 1 };

        assert_eq!(game.pending_seats(), Vec::<Seat>::new());
        assert!(game.legal_actions(0).is_empty());
        assert_eq!(game.apply(0, Action::EndTurn), Err(GameError::GameFinished));
    }

    #[test]
    fn first_legal_action_game_is_deterministic() {
        let run = || {
            let mut game = Game::new(GameSettings {
                seats: 4,
                points_to_win: 10,
                seed: 2024,
            })
            .unwrap();
            let mut log = Vec::new();
            for _ in 0..ACTION_LIMIT {
                let Some(seat) = game.pending_seats().first().copied() else {
                    break;
                };
                let action = game.legal_actions(seat)[0].clone();
                log.push(game.apply(seat, action).unwrap());
            }
            (game, log)
        };

        let (game, log) = run();
        assert!(matches!(game.phase, Phase::Finished { .. }) || log.len() == ACTION_LIMIT);
        assert_eq!(run(), (game, log));
    }

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(64))]

        #[test]
        fn random_legal_play_never_fails(
            seed in any::<u64>(),
            seats in 3u8..=4,
            choices in proptest::collection::vec(any::<usize>(), ACTION_LIMIT),
        ) {
            let mut game = Game::new(GameSettings { seats, points_to_win: 10, seed }).unwrap();
            for choice in choices {
                let pending = game.pending_seats();
                if pending.is_empty() {
                    prop_assert!(matches!(game.phase, Phase::Finished { .. }), "nobody pending before the end");
                    break;
                }
                for seat in (0..seats).filter(|seat| !pending.contains(seat)) {
                    prop_assert!(game.legal_actions(seat).is_empty());
                }
                let seat = pending[choice % pending.len()];
                let legal = game.legal_actions(seat);
                prop_assert!(!legal.is_empty(), "no legal action in {:?}", game.phase);
                let action = legal[choice % legal.len()].clone();
                prop_assert!(game.apply(seat, action.clone()).is_ok(), "{:?} rejected", action);
                prop_assert_eq!(resource_total(&game), 95);
            }
        }
    }
}
