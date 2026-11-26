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

pub const MIN_SEATS: u8 = 3;
pub const MAX_SEATS: u8 = 4;
/// Below this the setup settlements alone could win.
pub const MIN_POINTS_TO_WIN: u8 = 3;
pub const MAX_POINTS_TO_WIN: u8 = 15;
pub const DEFAULT_POINTS_TO_WIN: u8 = 10;
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

/// An open player trade (step 2a); it exists only inside the `TradeOffered` phase.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub struct TradeOffer {
    pub offerer: Seat,
    pub give: ResourceCounts,
    pub receive: ResourceCounts,
    /// `None` asks every other seat.
    pub addressed: Option<Seat>,
    /// Who answered and whether they accepted, at most one entry per seat.
    pub answers: Vec<(Seat, bool)>,
}

impl TradeOffer {
    /// Whether `seat` is asked: the addressed seat, or anyone but the offerer when the offer is open to all.
    pub fn asks(&self, seat: Seat) -> bool {
        seat != self.offerer && self.addressed.is_none_or(|addressed| addressed == seat)
    }

    /// `Some(accepted)` once `seat` has answered.
    pub fn answer_of(&self, seat: Seat) -> Option<bool> {
        self.answers
            .iter()
            .find(|(answered, _)| *answered == seat)
            .map(|(_, accepted)| *accepted)
    }

    /// Whether `seat` is asked and has not answered yet.
    pub fn awaits_answer_from(&self, seat: Seat) -> bool {
        self.asks(seat) && self.answer_of(seat).is_none()
    }
}

/// One side of a resource transfer.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Holder {
    Bank,
    Seat(Seat),
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
    pub(crate) longest_road: Option<Seat>,
    pub(crate) largest_army: Option<Seat>,
}

impl Game {
    pub fn new(settings: GameSettings) -> Result<Game, GameError> {
        let seats_supported = (MIN_SEATS..=MAX_SEATS).contains(&settings.seats);
        let points_supported =
            (MIN_POINTS_TO_WIN..=MAX_POINTS_TO_WIN).contains(&settings.points_to_win);
        if !seats_supported || !points_supported {
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
            longest_road: None,
            largest_army: None,
        })
    }

    /// Validates first and mutates only on success, so an `Err` leaves the game unchanged.
    pub fn apply(&mut self, seat: Seat, action: Action) -> Result<Vec<Event>, GameError> {
        if self.is_finished() {
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
            Phase::TradeOffered { offer } => trade::legal_answers(self, offer, seat),
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
            Phase::TradeOffered { offer } => trade::pending_seats(self, offer),
            _ => vec![self.current],
        }
    }

    pub fn view(&self, seat: Option<Seat>) -> PlayerView {
        PlayerView::of(self, seat)
    }

    pub fn phase(&self) -> &Phase {
        &self.phase
    }

    pub fn winner(&self) -> Option<Seat> {
        match self.phase {
            Phase::Finished { winner } => Some(winner),
            _ => None,
        }
    }

    pub fn is_finished(&self) -> bool {
        self.winner().is_some()
    }

    pub fn current_seat(&self) -> Seat {
        self.current
    }

    pub fn board(&self) -> &Board {
        &self.board
    }

    pub(crate) fn player(&self, seat: Seat) -> Result<&PlayerState, GameError> {
        self.players
            .get(usize::from(seat))
            .ok_or(GameError::NotYourTurn)
    }

    pub(crate) fn player_mut(&mut self, seat: Seat) -> Result<&mut PlayerState, GameError> {
        self.players
            .get_mut(usize::from(seat))
            .ok_or(GameError::NotYourTurn)
    }

    pub(crate) fn require_turn(&self, seat: Seat) -> Result<(), GameError> {
        if seat != self.current {
            return Err(GameError::NotYourTurn);
        }
        Ok(())
    }

    pub(crate) fn require_main_turn(&self, seat: Seat) -> Result<(), GameError> {
        self.require_turn(seat)?;
        if self.phase != Phase::Main {
            return Err(GameError::WrongPhase);
        }
        Ok(())
    }

    /// Moves all of `amount` or nothing: both sides are checked before either changes.
    pub(crate) fn move_resources(
        &mut self,
        from: Holder,
        to: Holder,
        amount: ResourceCounts,
    ) -> Result<(), GameError> {
        let mut source = self.holdings(from)?;
        let target = self.holdings(to)?;
        source.try_remove(&amount)?;
        if from == to {
            return Ok(());
        }
        // Unreachable with 95 cards in play; rejected rather than saturated so no card is lost.
        let target = target.checked_add(&amount).ok_or(GameError::InvalidTrade)?;
        *self.holdings_mut(from)? = source;
        *self.holdings_mut(to)? = target;
        Ok(())
    }

    fn holdings(&self, holder: Holder) -> Result<ResourceCounts, GameError> {
        match holder {
            Holder::Bank => Ok(self.bank),
            Holder::Seat(seat) => Ok(self.player(seat)?.hand),
        }
    }

    fn holdings_mut(&mut self, holder: Holder) -> Result<&mut ResourceCounts, GameError> {
        match holder {
            Holder::Bank => Ok(&mut self.bank),
            Holder::Seat(seat) => Ok(&mut self.player_mut(seat)?.hand),
        }
    }

    /// Moves `cost` from the seat's hand to the bank, all or nothing; the event exists only when it was paid.
    pub(crate) fn pay_to_bank(
        &mut self,
        seat: Seat,
        cost: ResourceCounts,
    ) -> Result<Event, GameError> {
        self.move_resources(Holder::Seat(seat), Holder::Bank, cost)?;
        Ok(Event::ResourcesPaid {
            seat,
            resources: cost,
        })
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
    use crate::resource::Resource;
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
        for (seats, points_to_win) in [(2, 10), (5, 10), (4, 2), (4, 16)] {
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
    fn paying_more_than_the_hand_reports_nothing_paid() {
        let mut game = main_phase_game(3, 8);
        give(&mut game, 0, ResourceCounts::new([1, 0, 0, 0, 0]));
        let before = game.clone();

        assert_eq!(
            game.pay_to_bank(0, ResourceCounts::new([2, 0, 0, 0, 0])),
            Err(GameError::NotEnoughResources)
        );
        assert_eq!(game, before);
    }

    #[test]
    fn move_resources_is_all_or_nothing() {
        let mut game = main_phase_game(3, 8);
        give(&mut game, 0, ResourceCounts::new([2, 1, 0, 0, 0]));
        game.players[1].hand.set(Resource::Ore, u8::MAX);
        game.bank.set(Resource::Wheat, 0);
        let before = game.clone();

        let failures = [
            (
                Holder::Seat(0),
                Holder::Bank,
                ResourceCounts::new([3, 0, 0, 0, 0]),
            ),
            (
                Holder::Bank,
                Holder::Seat(0),
                ResourceCounts::new([1, 0, 0, 1, 0]),
            ),
            (
                Holder::Seat(0),
                Holder::Seat(1),
                ResourceCounts::new([1, 0, 0, 0, 1]),
            ),
            (
                Holder::Bank,
                Holder::Seat(1),
                ResourceCounts::new([0, 0, 0, 0, 1]),
            ),
            (
                Holder::Seat(0),
                Holder::Seat(7),
                ResourceCounts::new([1, 0, 0, 0, 0]),
            ),
            (Holder::Seat(7), Holder::Seat(0), ResourceCounts::default()),
        ];
        for (from, to, amount) in failures {
            assert!(
                game.move_resources(from, to, amount).is_err(),
                "{from:?} -> {to:?}"
            );
            assert_eq!(game, before, "{from:?} -> {to:?}");
        }

        let pair = ResourceCounts::new([1, 1, 0, 0, 0]);
        assert_eq!(
            game.move_resources(Holder::Seat(0), Holder::Seat(2), pair),
            Ok(())
        );
        assert_eq!(game.players[0].hand, ResourceCounts::new([1, 0, 0, 0, 0]));
        assert_eq!(game.players[2].hand, pair);
        assert_eq!(resource_total(&game), resource_total(&before));
    }

    #[test]
    fn finished_game_rejects_everything() {
        let mut game = main_phase_game(3, 3);
        assert_eq!((game.winner(), game.is_finished()), (None, false));
        game.phase = Phase::Finished { winner: 1 };
        assert_eq!((game.winner(), game.is_finished()), (Some(1), true));

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
