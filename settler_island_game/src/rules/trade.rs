use crate::action::Action;
use crate::board::{CornerId, Port};
use crate::error::GameError;
use crate::event::Event;
use crate::game::{Game, Seat, TradeOffer};
use crate::phase::Phase;
use crate::resource::{Resource, ResourceCounts};

const BANK_RATE: u8 = 4;
const GENERIC_PORT_RATE: u8 = 3;
const SPECIFIC_PORT_RATE: u8 = 2;

/// What one card of each resource costs at the bank for `seat`.
pub(crate) fn bank_rates(game: &Game, seat: Seat) -> ResourceCounts {
    let mut rates = ResourceCounts::default();
    for resource in Resource::ALL {
        rates.set(resource, bank_rate(game, seat, resource));
    }
    rates
}

/// Rate 2 with a matching specific port, 3 with any generic port, else 4.
fn bank_rate(game: &Game, seat: Seat, give: Resource) -> u8 {
    game.board
        .corner_ids()
        .filter(|corner| {
            game.board
                .building(*corner)
                .is_some_and(|building| building.seat == seat)
        })
        .map(|corner| port_rate(game, corner, give))
        .min()
        .unwrap_or(BANK_RATE)
        .min(BANK_RATE)
}

fn port_rate(game: &Game, corner: CornerId, give: Resource) -> u8 {
    match game.board.corner(corner).and_then(|corner| corner.port) {
        Some(Port::Specific(resource)) if resource == give => SPECIFIC_PORT_RATE,
        Some(Port::Generic) => GENERIC_PORT_RATE,
        _ => BANK_RATE,
    }
}

fn check_main_turn(game: &Game, seat: Seat) -> Result<(), GameError> {
    game.require_turn(seat)?;
    if game.phase != Phase::Main {
        return Err(GameError::WrongPhase);
    }
    Ok(())
}

pub(crate) fn bank_trade(
    game: &mut Game,
    seat: Seat,
    give: Resource,
    receive: Resource,
) -> Result<Vec<Event>, GameError> {
    check_main_turn(game, seat)?;
    if give == receive {
        return Err(GameError::InvalidTrade);
    }
    let gave = ResourceCounts::single(give, bank_rate(game, seat, give));
    let received = ResourceCounts::single(receive, 1);
    if !game.player(seat)?.hand.contains(&gave) {
        return Err(GameError::NotEnoughResources);
    }
    if !game.bank.contains(&received) {
        return Err(GameError::BankEmpty);
    }

    exchange_with_bank(game, seat, &gave, &received);
    Ok(vec![Event::BankTraded {
        seat,
        gave,
        received,
    }])
}

/// Callers have checked that the hand and the bank cover their side.
fn exchange_with_bank(
    game: &mut Game,
    seat: Seat,
    gave: &ResourceCounts,
    received: &ResourceCounts,
) {
    let Some(player) = game.players.get_mut(usize::from(seat)) else {
        return;
    };
    if player.hand.try_remove(gave).is_err() || game.bank.try_remove(received).is_err() {
        return;
    }
    player.hand.deposit(received);
    game.bank.deposit(gave);
}

pub(crate) fn offer_trade(
    game: &mut Game,
    seat: Seat,
    give: ResourceCounts,
    receive: ResourceCounts,
    to: Option<Seat>,
) -> Result<Vec<Event>, GameError> {
    check_main_turn(game, seat)?;
    if give.is_empty() || receive.is_empty() || shares_a_resource(&give, &receive) {
        return Err(GameError::InvalidTrade);
    }
    if to.is_some_and(|addressed| addressed == seat || addressed >= game.settings.seats) {
        return Err(GameError::InvalidTrade);
    }
    if !game.player(seat)?.hand.contains(&give) {
        return Err(GameError::NotEnoughResources);
    }

    game.trade = Some(TradeOffer {
        seat,
        give,
        receive,
        to,
        answers: Vec::new(),
    });
    Ok(vec![
        Event::TradeOffered {
            seat,
            give,
            receive,
            to,
        },
        game.enter(Phase::TradeOffered),
    ])
}

fn shares_a_resource(first: &ResourceCounts, second: &ResourceCounts) -> bool {
    Resource::ALL
        .iter()
        .any(|resource| first.get(*resource) > 0 && second.get(*resource) > 0)
}

fn open_offer(game: &Game) -> Result<&TradeOffer, GameError> {
    let offer = game.trade.as_ref().ok_or(GameError::NoTradeOpen)?;
    if game.phase != Phase::TradeOffered {
        return Err(GameError::WrongPhase);
    }
    Ok(offer)
}

pub(crate) fn answer_trade(
    game: &mut Game,
    seat: Seat,
    accepted: bool,
) -> Result<Vec<Event>, GameError> {
    let offer = open_offer(game)?;
    let addressed = seat != offer.seat && offer.to.is_none_or(|to| to == seat);
    if !addressed || seat >= game.settings.seats {
        return Err(GameError::NotYourTurn);
    }
    if offer.answers.iter().any(|(answered, _)| *answered == seat) {
        return Err(GameError::InvalidTrade);
    }
    if accepted && !game.player(seat)?.hand.contains(&offer.receive) {
        return Err(GameError::NotEnoughResources);
    }

    if let Some(open) = game.trade.as_mut() {
        open.answers.push((seat, accepted));
    }
    Ok(vec![Event::TradeAnswered { seat, accepted }])
}

pub(crate) fn confirm_trade(
    game: &mut Game,
    seat: Seat,
    with: Seat,
) -> Result<Vec<Event>, GameError> {
    let offer = open_offer(game)?.clone();
    if seat != offer.seat {
        return Err(GameError::NotYourTurn);
    }
    if !offer.answers.contains(&(with, true)) {
        return Err(GameError::InvalidTrade);
    }
    if !game.player(with)?.hand.contains(&offer.receive) {
        return Err(GameError::NotEnoughResources);
    }
    if !game.player(seat)?.hand.contains(&offer.give) {
        return Err(GameError::NotEnoughResources);
    }

    swap_hands(game, &offer, with);
    game.trade = None;
    Ok(vec![
        Event::TradeCompleted {
            seat,
            with,
            gave: offer.give,
            received: offer.receive,
        },
        game.enter(Phase::Main),
    ])
}

/// Callers have checked both hands.
fn swap_hands(game: &mut Game, offer: &TradeOffer, with: Seat) {
    if let Some(player) = game.players.get_mut(usize::from(offer.seat)) {
        if player.hand.try_remove(&offer.give).is_ok() {
            player.hand.deposit(&offer.receive);
        }
    }
    if let Some(player) = game.players.get_mut(usize::from(with)) {
        if player.hand.try_remove(&offer.receive).is_ok() {
            player.hand.deposit(&offer.give);
        }
    }
}

pub(crate) fn cancel_trade(game: &mut Game, seat: Seat) -> Result<Vec<Event>, GameError> {
    if open_offer(game)?.seat != seat {
        return Err(GameError::NotYourTurn);
    }

    game.trade = None;
    Ok(vec![
        Event::TradeCancelled { seat },
        game.enter(Phase::Main),
    ])
}

pub(crate) fn legal_main(game: &Game, seat: Seat) -> Vec<Action> {
    let Ok(player) = game.player(seat) else {
        return Vec::new();
    };
    let mut actions = Vec::new();
    for give in Resource::ALL {
        if player.hand.get(give) < bank_rate(game, seat, give) {
            continue;
        }
        for receive in Resource::ALL {
            if receive != give && game.bank.get(receive) > 0 {
                actions.push(Action::BankTrade { give, receive });
            }
        }
    }
    actions
}

pub(crate) fn legal_answers(game: &Game, seat: Seat) -> Vec<Action> {
    let Some(offer) = &game.trade else {
        return Vec::new();
    };
    if seat == offer.seat {
        return offerer_choices(game, offer);
    }
    let mut actions = Vec::new();
    if holds(game, seat, &offer.receive) {
        actions.push(Action::AcceptTrade);
    }
    actions.push(Action::RejectTrade);
    actions
}

fn offerer_choices(game: &Game, offer: &TradeOffer) -> Vec<Action> {
    let mut actions: Vec<Action> = offer
        .answers
        .iter()
        .filter(|(_, accepted)| *accepted)
        .filter(|(with, _)| holds(game, *with, &offer.receive))
        .map(|(with, _)| Action::ConfirmTrade { with: *with })
        .collect();
    actions.push(Action::CancelTrade);
    actions
}

fn holds(game: &Game, seat: Seat, resources: &ResourceCounts) -> bool {
    game.player(seat)
        .is_ok_and(|player| player.hand.contains(resources))
}

#[cfg(test)]
mod tests {
    use proptest::prelude::*;
    use rand::SeedableRng;
    use rand_chacha::ChaCha8Rng;

    use super::*;
    use crate::rules::test_support::{give, main_phase_game, put_settlement};

    fn cards(resource: Resource, amount: u8) -> ResourceCounts {
        ResourceCounts::single(resource, amount)
    }

    fn corner_with(game: &Game, wanted: Option<Port>) -> CornerId {
        game.board
            .corner_ids()
            .find(|corner| game.board.corner(*corner).unwrap().port == wanted)
            .unwrap()
    }

    fn total(game: &Game) -> u32 {
        game.bank.total()
            + game
                .players
                .iter()
                .map(|player| player.hand.total())
                .sum::<u32>()
    }

    /// A main-phase game with an empty board (ports only) and seat 0 holding `hand`.
    fn bare_game(hand: ResourceCounts) -> Game {
        let mut game = main_phase_game(3, 5);
        game.board = crate::board::generate(&mut ChaCha8Rng::seed_from_u64(5));
        give(&mut game, 0, hand);
        game
    }

    fn bank_trade_action(give: Resource, receive: Resource) -> Action {
        Action::BankTrade { give, receive }
    }

    /// Trades `paid` for a resource other than itself and returns how many cards left the hand.
    fn trade_rate(game: &mut Game, paid: Resource) -> u8 {
        let receive = if paid == Resource::Ore {
            Resource::Wood
        } else {
            Resource::Ore
        };
        let before = game.players[0].hand.get(paid);
        game.apply(0, bank_trade_action(paid, receive)).unwrap();
        before - game.players[0].hand.get(paid)
    }

    #[test]
    fn rate_is_four_without_a_port() {
        let mut game = bare_game(cards(Resource::Wood, 4));
        let corner = corner_with(&game, None);
        put_settlement(&mut game, 0, corner);

        assert_eq!(trade_rate(&mut game, Resource::Wood), 4);
        assert_eq!(game.players[0].hand.get(Resource::Ore), 1);
        assert_eq!(total(&game), 95);
    }

    #[test]
    fn generic_port_gives_three_and_specific_port_two_only_for_its_resource() {
        let mut game = bare_game(ResourceCounts::new([4, 7, 0, 0, 0]));
        let generic = corner_with(&game, Some(Port::Generic));
        put_settlement(&mut game, 0, generic);
        assert_eq!(trade_rate(&mut game, Resource::Wood), 3);

        let specific = corner_with(&game, Some(Port::Specific(Resource::Clay)));
        put_settlement(&mut game, 0, specific);
        assert_eq!(trade_rate(&mut game, Resource::Clay), 2);
        assert_eq!(trade_rate(&mut game, Resource::Wood), 3);
    }

    #[test]
    fn the_own_view_shows_the_rate_each_trade_pays() {
        let mut game = bare_game(ResourceCounts::new([8, 8, 8, 8, 8]));
        let specific = corner_with(&game, Some(Port::Specific(Resource::Clay)));
        put_settlement(&mut game, 0, specific);
        let shown = game.view(Some(0)).own.unwrap().bank_rates;

        assert_eq!(shown, ResourceCounts::new([2, 4, 4, 4, 4]));
        for resource in Resource::ALL {
            assert_eq!(trade_rate(&mut game, resource), shown.get(resource));
        }
    }

    #[test]
    fn specific_port_of_another_resource_does_not_help() {
        let mut game = bare_game(cards(Resource::Clay, 4));
        let specific = corner_with(&game, Some(Port::Specific(Resource::Wood)));
        put_settlement(&mut game, 0, specific);

        assert_eq!(trade_rate(&mut game, Resource::Clay), 4);
    }

    #[test]
    fn a_port_of_another_player_does_not_help() {
        let mut game = bare_game(cards(Resource::Wood, 4));
        let generic = corner_with(&game, Some(Port::Generic));
        put_settlement(&mut game, 1, generic);

        assert_eq!(trade_rate(&mut game, Resource::Wood), 4);
    }

    #[test]
    fn bank_trade_failures_leave_the_game_unchanged() {
        let game = bare_game(cards(Resource::Wood, 4));
        let mut empty_bank = game.clone();
        empty_bank.bank.set(Resource::Ore, 0);
        let short = bare_game(cards(Resource::Wood, 3));
        let mut wrong_phase = game.clone();
        wrong_phase.phase = Phase::Roll;
        let wood_for_ore = bank_trade_action(Resource::Wood, Resource::Ore);
        let cases = [
            (
                game.clone(),
                0,
                bank_trade_action(Resource::Wood, Resource::Wood),
                GameError::InvalidTrade,
            ),
            (
                short,
                0,
                wood_for_ore.clone(),
                GameError::NotEnoughResources,
            ),
            (empty_bank, 0, wood_for_ore.clone(), GameError::BankEmpty),
            (game, 1, wood_for_ore.clone(), GameError::NotYourTurn),
            (wrong_phase, 0, wood_for_ore, GameError::WrongPhase),
        ];

        for (mut attempt, seat, action, error) in cases {
            let before = attempt.clone();
            assert_eq!(attempt.apply(seat, action), Err(error));
            assert_eq!(attempt, before);
        }
    }

    #[test]
    fn legal_bank_trades_are_exactly_the_affordable_ones() {
        let mut game = bare_game(cards(Resource::Wood, 4));
        game.bank.set(Resource::Ore, 0);
        let corner = corner_with(&game, Some(Port::Specific(Resource::Wood)));
        put_settlement(&mut game, 0, corner);
        give(&mut game, 0, cards(Resource::Sheep, 3));

        let legal = legal_main(&game, 0);

        // Wood (rate 2) for 3 resources other than the empty ore; sheep (3 < rate 4) is unaffordable.
        assert_eq!(legal.len(), 3);
        assert!(!legal.contains(&bank_trade_action(Resource::Wood, Resource::Ore)));
        for action in legal {
            game.clone().apply(0, action).unwrap();
        }
    }

    fn open_trade(to: Option<Seat>) -> Game {
        let mut game = bare_game(cards(Resource::Wood, 2));
        give(&mut game, 1, cards(Resource::Ore, 1));
        give(&mut game, 2, cards(Resource::Ore, 1));
        game.apply(
            0,
            Action::OfferTrade {
                give: cards(Resource::Wood, 2),
                receive: cards(Resource::Ore, 1),
                to,
            },
        )
        .unwrap();
        game
    }

    #[test]
    fn full_player_trade_moves_cards_and_returns_to_main() {
        let mut game = open_trade(None);
        assert_eq!(game.phase, Phase::TradeOffered);
        game.apply(1, Action::AcceptTrade).unwrap();
        game.apply(2, Action::RejectTrade).unwrap();
        let events = game.apply(0, Action::ConfirmTrade { with: 1 }).unwrap();

        assert_eq!(game.phase, Phase::Main);
        assert_eq!(game.trade, None);
        assert!(events.contains(&Event::TradeCompleted {
            seat: 0,
            with: 1,
            gave: cards(Resource::Wood, 2),
            received: cards(Resource::Ore, 1),
        }));
        assert_eq!(game.players[0].hand, cards(Resource::Ore, 1));
        assert_eq!(game.players[1].hand, cards(Resource::Wood, 2));
        assert_eq!(game.players[2].hand, cards(Resource::Ore, 1));
        assert_eq!(total(&game), 95);
    }

    #[test]
    fn offer_is_validated() {
        let game = bare_game(ResourceCounts::new([0, 2, 0, 0, 1]));
        let offer = |give: ResourceCounts, receive: ResourceCounts, to| Action::OfferTrade {
            give,
            receive,
            to,
        };
        let wood = cards(Resource::Wood, 1);
        let ore = cards(Resource::Ore, 1);
        let cases = [
            (
                offer(ResourceCounts::default(), ore, None),
                GameError::InvalidTrade,
            ),
            (
                offer(wood, ResourceCounts::default(), None),
                GameError::InvalidTrade,
            ),
            // Wood on both sides.
            (
                offer(ResourceCounts::new([0, 1, 0, 0, 1]), wood, None),
                GameError::InvalidTrade,
            ),
            (offer(wood, ore, Some(0)), GameError::InvalidTrade),
            (offer(wood, ore, Some(3)), GameError::InvalidTrade),
            (
                offer(cards(Resource::Wood, 3), ore, None),
                GameError::NotEnoughResources,
            ),
        ];

        for (action, error) in cases {
            let mut attempt = game.clone();
            assert_eq!(attempt.apply(0, action), Err(error));
            assert_eq!(attempt, game);
        }
    }

    #[test]
    fn only_addressed_seats_answer_and_only_once() {
        let mut game = open_trade(Some(1));

        assert_eq!(
            game.apply(2, Action::AcceptTrade),
            Err(GameError::NotYourTurn)
        );
        assert_eq!(
            game.apply(0, Action::AcceptTrade),
            Err(GameError::NotYourTurn)
        );
        assert_eq!(game.pending_seats(), vec![1, 0]);
        game.apply(1, Action::RejectTrade).unwrap();
        assert_eq!(
            game.apply(1, Action::AcceptTrade),
            Err(GameError::InvalidTrade)
        );
        assert_eq!(game.pending_seats(), vec![0]);
    }

    #[test]
    fn accepting_without_the_cards_fails() {
        let mut game = open_trade(None);
        let held = game.players[1].hand;
        game.players[1].hand = ResourceCounts::default();
        game.bank.deposit(&held);
        let before = game.clone();

        assert_eq!(
            game.apply(1, Action::AcceptTrade),
            Err(GameError::NotEnoughResources)
        );
        assert_eq!(game, before);
        assert_eq!(game.legal_actions(1), vec![Action::RejectTrade]);
    }

    #[test]
    fn confirm_needs_an_accepting_seat_who_still_holds_the_cards() {
        let mut game = open_trade(None);
        game.apply(1, Action::AcceptTrade).unwrap();
        game.apply(2, Action::RejectTrade).unwrap();

        assert_eq!(
            game.apply(0, Action::ConfirmTrade { with: 2 }),
            Err(GameError::InvalidTrade)
        );
        assert_eq!(
            game.apply(1, Action::ConfirmTrade { with: 1 }),
            Err(GameError::NotYourTurn)
        );
        assert_eq!(
            game.legal_actions(0),
            vec![Action::ConfirmTrade { with: 1 }, Action::CancelTrade]
        );
        let held = game.players[1].hand;
        game.bank.deposit(&held);
        game.players[1].hand = ResourceCounts::default();
        assert_eq!(
            game.apply(0, Action::ConfirmTrade { with: 1 }),
            Err(GameError::NotEnoughResources)
        );
        assert_eq!(game.legal_actions(0), vec![Action::CancelTrade]);
    }

    #[test]
    fn everyone_rejecting_keeps_the_offer_open_until_cancel() {
        let mut game = open_trade(None);
        game.apply(1, Action::RejectTrade).unwrap();
        game.apply(2, Action::RejectTrade).unwrap();

        assert_eq!(game.phase, Phase::TradeOffered);
        assert_eq!(game.pending_seats(), vec![0]);
        assert_eq!(game.legal_actions(0), vec![Action::CancelTrade]);
        let events = game.apply(0, Action::CancelTrade).unwrap();
        assert!(events.contains(&Event::TradeCancelled { seat: 0 }));
        assert_eq!(game.phase, Phase::Main);
        assert_eq!(game.trade, None);
        assert_eq!(game.players[0].hand, cards(Resource::Wood, 2));
    }

    #[test]
    fn answers_without_an_open_trade_fail() {
        let mut game = bare_game(ResourceCounts::default());

        assert_eq!(
            game.apply(1, Action::AcceptTrade),
            Err(GameError::NoTradeOpen)
        );
        assert_eq!(
            game.apply(0, Action::CancelTrade),
            Err(GameError::NoTradeOpen)
        );
        assert_eq!(
            game.apply(0, Action::ConfirmTrade { with: 1 }),
            Err(GameError::NoTradeOpen)
        );
    }

    #[test]
    fn nothing_else_is_legal_while_a_trade_is_open() {
        let mut game = open_trade(None);

        assert_eq!(game.apply(0, Action::EndTurn), Err(GameError::WrongPhase));
        assert_eq!(
            game.apply(0, bank_trade_action(Resource::Wood, Resource::Ore)),
            Err(GameError::WrongPhase)
        );
    }

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(64))]

        #[test]
        fn trades_never_create_or_destroy_cards(
            hands in proptest::collection::vec(proptest::array::uniform5(0u8..4), 3),
            steps in proptest::collection::vec((0u8..3, 0usize..6, proptest::array::uniform5(0u8..3), proptest::array::uniform5(0u8..3)), 40),
        ) {
            let mut game = bare_game(ResourceCounts::default());
            for (seat, hand) in hands.into_iter().enumerate() {
                give(&mut game, seat as Seat, ResourceCounts::new(hand));
            }
            for (seat, choice, offered, wanted) in steps {
                let offer = Action::OfferTrade {
                    give: ResourceCounts::new(offered),
                    receive: ResourceCounts::new(wanted),
                    to: None,
                };
                let mut actions = game.legal_actions(seat);
                actions.push(offer);
                let action = actions[choice % actions.len()].clone();
                // Rejections are fine; only the invariants matter.
                let _ = game.apply(seat, action);
                prop_assert_eq!(total(&game), 95);
                if game.phase == Phase::Main {
                    prop_assert_eq!(&game.trade, &None);
                }
            }
        }
    }
}
