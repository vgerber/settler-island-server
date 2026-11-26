mod evaluation;
mod hand;

use settler_island_game::{
    Action, OwnView, Phase, PlayerView, Purchase, Resource, ResourceCounts, Seat, TradeOffer,
    DISCARD_ABOVE_CARDS, MIN_LARGEST_ARMY,
};

use crate::Bot;
use evaluation::{
    corner_production, has_open_site, road_value, robber_blocks, robber_value, seat_production,
    site_value,
};
use hand::{bank_trade_toward, goal, keep_score, missing, offer_toward};

/// No trade partner this many points short of winning or closer.
const LEADER_MARGIN: u8 = 2;
/// Monopoly only pays when the others hold enough cards.
const MONOPOLY_MIN_CARDS: u32 = 5;

/// Places by pips and resource mix, builds city > settlement > card > road, and trades to finish builds.
pub(crate) struct HeuristicBot {
    offered_on_turn: Option<u32>,
}

impl HeuristicBot {
    pub(crate) fn new() -> HeuristicBot {
        HeuristicBot {
            offered_on_turn: None,
        }
    }

    fn decide(&mut self, view: &PlayerView, own: &OwnView, legal: &[Action]) -> Option<Action> {
        let seat = own.seat;
        match &view.phase {
            Phase::SetupSettlement { .. } => {
                let existing = seat_production(&view.board, seat);
                best(legal, |action| match action {
                    Action::PlaceSettlement { corner } => {
                        Some(site_value(&view.board, *corner, &existing))
                    }
                    _ => None,
                })
            }
            Phase::SetupRoad { .. } | Phase::RoadBuilding { .. } => best_road(view, seat, legal),
            Phase::Roll => Some(before_roll(view, seat, legal)),
            Phase::Main => Some(self.main_action(view, own, legal)),
            Phase::Discard { .. } => discard(view, own, legal),
            Phase::MoveRobber { .. } => best(legal, |action| match action {
                Action::MoveRobber { tile } => Some(robber_value(view, seat, *tile)),
                _ => None,
            }),
            Phase::Steal { .. } => steal(view, legal),
            Phase::TradeOffered { offer } => Some(answer_trade(view, own, offer, legal)),
            Phase::Finished { .. } => None,
        }
    }

    fn main_action(&mut self, view: &PlayerView, own: &OwnView, legal: &[Action]) -> Action {
        let seat = own.seat;
        let hand = own.hand;
        let target = goal(view, seat, &hand);
        let choices = [
            knight(view, seat, legal),
            best(legal, |action| match action {
                Action::BuildCity { corner } => Some(f64::from(
                    corner_production(&view.board, *corner).iter().sum::<u32>(),
                )),
                _ => None,
            }),
            best(legal, |action| match action {
                Action::BuildSettlement { corner } => Some(site_value(
                    &view.board,
                    *corner,
                    &seat_production(&view.board, seat),
                )),
                _ => None,
            }),
            year_of_plenty(&hand, target, legal),
            monopoly(view, seat, &hand, target, legal),
            expansion(view, seat, legal),
            buy_card(&hand, target, legal),
            bank_trade(view, own, &hand, target, legal),
        ];
        // The offer is tried last because it records the turn.
        choices
            .into_iter()
            .flatten()
            .next()
            .or_else(|| self.offer(view, seat, &hand, target))
            .unwrap_or(Action::EndTurn)
    }

    /// At most one offer per turn: one spare card for the last missing one, to everybody.
    fn offer(
        &mut self,
        view: &PlayerView,
        seat: Seat,
        hand: &ResourceCounts,
        target: Purchase,
    ) -> Option<Action> {
        let points = view.players.get(usize::from(seat))?.points;
        if self.offered_on_turn == Some(view.turn_number) || near_win(view, points) {
            return None;
        }
        let (give, receive) = offer_toward(hand, &target.cost())?;
        self.offered_on_turn = Some(view.turn_number);
        Some(Action::OfferTrade {
            give: ResourceCounts::single(give, 1),
            receive: ResourceCounts::single(receive, 1),
            to: None,
        })
    }
}

impl Bot for HeuristicBot {
    fn choose(&mut self, view: &PlayerView, legal: &[Action]) -> Action {
        let fallback = legal.first().cloned().unwrap_or(Action::EndTurn);
        let Some(own) = &view.own else {
            return fallback;
        };
        match self.decide(view, own, legal) {
            Some(action @ Action::OfferTrade { .. }) => action,
            Some(action) if legal.contains(&action) => action,
            decision => {
                // A decision outside the legal list means the bot's model of the rules drifted.
                debug_assert!(decision.is_none(), "illegal bot decision {decision:?}");
                fallback
            }
        }
    }
}

/// The legal action with the highest score; actions scored `None` are skipped.
fn best(legal: &[Action], score: impl Fn(&Action) -> Option<f64>) -> Option<Action> {
    legal
        .iter()
        .filter_map(|action| score(action).map(|value| (action, value)))
        .max_by(|first, second| first.1.total_cmp(&second.1))
        .map(|(action, _)| action.clone())
}

fn best_road(view: &PlayerView, seat: Seat, legal: &[Action]) -> Option<Action> {
    best(legal, |action| match action {
        Action::PlaceRoad { edge } | Action::BuildRoad { edge } => {
            Some(road_value(&view.board, seat, *edge))
        }
        _ => None,
    })
}

fn before_roll(view: &PlayerView, seat: Seat, legal: &[Action]) -> Action {
    if legal.contains(&Action::PlayKnight) && robber_blocks(&view.board, seat) {
        return Action::PlayKnight;
    }
    Action::RollDice
}

/// Against a blocked own tile, or when one more knight takes the largest army.
fn knight(view: &PlayerView, seat: Seat, legal: &[Action]) -> Option<Action> {
    if !legal.contains(&Action::PlayKnight) {
        return None;
    }
    let mine = view.players.get(usize::from(seat))?.knights_played + 1;
    let others_best = view
        .players
        .iter()
        .filter(|player| player.seat != seat)
        .map(|player| player.knights_played)
        .max()
        .unwrap_or(0);
    let takes_army =
        view.largest_army != Some(seat) && mine >= MIN_LARGEST_ARMY && mine > others_best;
    (takes_army || robber_blocks(&view.board, seat)).then_some(Action::PlayKnight)
}

/// Only when the two cards complete the goal.
fn year_of_plenty(hand: &ResourceCounts, target: Purchase, legal: &[Action]) -> Option<Action> {
    legal
        .iter()
        .find(|action| {
            let Action::PlayYearOfPlenty { first, second } = action else {
                return false;
            };
            let mut gained = *hand;
            gained.set(*first, gained.get(*first).saturating_add(1));
            gained.set(*second, gained.get(*second).saturating_add(1));
            !missing(hand, &target.cost()).is_empty() && missing(&gained, &target.cost()).is_empty()
        })
        .cloned()
}

/// Takes the goal's most-missing resource when the others hold enough cards.
fn monopoly(
    view: &PlayerView,
    seat: Seat,
    hand: &ResourceCounts,
    target: Purchase,
    legal: &[Action],
) -> Option<Action> {
    let others: u32 = view
        .players
        .iter()
        .filter(|player| player.seat != seat)
        .map(|player| u32::from(player.resource_count))
        .sum();
    if others < MONOPOLY_MIN_CARDS {
        return None;
    }
    let needed = missing(hand, &target.cost());
    let resource = Resource::ALL
        .into_iter()
        .filter(|resource| needed.get(*resource) > 0)
        .max_by_key(|resource| needed.get(*resource))?;
    let action = Action::PlayMonopoly { resource };
    legal.contains(&action).then_some(action)
}

/// Roads (bought or from the card) only while no free site touches an own road.
fn expansion(view: &PlayerView, seat: Seat, legal: &[Action]) -> Option<Action> {
    let player = view.players.get(usize::from(seat))?;
    if player.settlements_left == 0 || has_open_site(&view.board, seat) {
        return None;
    }
    let road = best(legal, |action| match action {
        Action::BuildRoad { edge } => {
            Some(road_value(&view.board, seat, *edge)).filter(|value| *value > 0.0)
        }
        _ => None,
    });
    let card = (player.roads_left >= 2 && legal.contains(&Action::PlayRoadBuilding))
        .then_some(Action::PlayRoadBuilding);
    card.or(road)
}

/// When the card is the goal, or when paying for it leaves the goal no further away.
fn buy_card(hand: &ResourceCounts, target: Purchase, legal: &[Action]) -> Option<Action> {
    if !legal.contains(&Action::BuyDevelopmentCard) {
        return None;
    }
    let mut after = *hand;
    after.try_remove(&Purchase::DevelopmentCard.cost()).ok()?;
    let keeps_goal =
        missing(&after, &target.cost()).total() == missing(hand, &target.cost()).total();
    (target == Purchase::DevelopmentCard || keeps_goal).then_some(Action::BuyDevelopmentCard)
}

/// Trades that finish the goal, or any step toward it while a seven would cost cards.
fn bank_trade(
    view: &PlayerView,
    own: &OwnView,
    hand: &ResourceCounts,
    target: Purchase,
    legal: &[Action],
) -> Option<Action> {
    let complete_only = hand.total() <= DISCARD_ABOVE_CARDS;
    let (give, receive) = bank_trade_toward(
        hand,
        &target.cost(),
        &own.bank_rates,
        &view.bank,
        complete_only,
    )?;
    let action = Action::BankTrade { give, receive };
    legal.contains(&action).then_some(action)
}

fn discard(view: &PlayerView, own: &OwnView, legal: &[Action]) -> Option<Action> {
    let target = goal(view, own.seat, &own.hand);
    let scored = legal.iter().filter_map(|action| {
        let Action::Discard { resources } = action else {
            return None;
        };
        let mut kept = own.hand;
        kept.try_remove(resources).ok()?;
        Some((action, keep_score(&kept, target)))
    });
    scored
        .max_by_key(|(_, score)| *score)
        .map(|(action, _)| action.clone())
}

/// From the seat with the most public points, then the most cards.
fn steal(view: &PlayerView, legal: &[Action]) -> Option<Action> {
    legal
        .iter()
        .filter_map(|action| match action {
            Action::Steal { victim } => view
                .players
                .get(usize::from(*victim))
                .map(|player| (action, (player.points, player.resource_count))),
            _ => None,
        })
        .max_by_key(|(_, rank)| *rank)
        .map(|(action, _)| action.clone())
}

/// Too close to the win target to help.
fn near_win(view: &PlayerView, points: u8) -> bool {
    points >= view.points_to_win.saturating_sub(LEADER_MARGIN)
}

/// Own offers settle with the weakest accepting seat; foreign offers are accepted when they help the goal.
fn answer_trade(view: &PlayerView, own: &OwnView, offer: &TradeOffer, legal: &[Action]) -> Action {
    let partner = legal
        .iter()
        .filter_map(|action| match action {
            Action::ConfirmTrade { with } => view.players.get(usize::from(*with)),
            _ => None,
        })
        .filter(|player| !near_win(view, player.points))
        .min_by_key(|player| player.points);
    if let Some(player) = partner {
        return Action::ConfirmTrade { with: player.seat };
    }
    if legal.contains(&Action::CancelTrade) {
        return Action::CancelTrade;
    }
    if legal.contains(&Action::AcceptTrade) && helps_goal(view, own, offer) {
        return Action::AcceptTrade;
    }
    Action::RejectTrade
}

/// We receive `give` and pay `receive`: accept when that closes the gap to the goal without opening another.
fn helps_goal(view: &PlayerView, own: &OwnView, offer: &TradeOffer) -> bool {
    let Some(offerer) = view.players.get(usize::from(offer.offerer)) else {
        return false;
    };
    let mut after = own.hand;
    if after.try_remove(&offer.receive).is_err() || near_win(view, offerer.points) {
        return false;
    }
    for resource in Resource::ALL {
        after.set(
            resource,
            after.get(resource).saturating_add(offer.give.get(resource)),
        );
    }
    let cost = goal(view, own.seat, &own.hand).cost();
    let (before, now) = (missing(&own.hand, &cost), missing(&after, &cost));
    let opens_gap = Resource::ALL
        .into_iter()
        .any(|resource| now.get(resource) > before.get(resource));
    now.total() < before.total() && !opens_gap
}

#[cfg(test)]
mod tests {
    use super::*;
    use settler_island_game::{BuildingKind, CornerId, Game, GameSettings, OwedDiscard, TileId};

    /// A real board after four heuristic bots placed their setup pieces.
    fn after_setup(seed: u64) -> Game {
        let settings = GameSettings {
            seats: 4,
            points_to_win: 10,
            seed,
        };
        let mut game = Game::new(settings).unwrap();
        let mut bots: Vec<HeuristicBot> = (0..4).map(|_| HeuristicBot::new()).collect();
        while *game.phase() != Phase::Roll {
            let seat = game.current_seat();
            let action =
                bots[usize::from(seat)].choose(&game.view(Some(seat)), &game.legal_actions(seat));
            game.apply(seat, action).unwrap();
        }
        game
    }

    fn view_with(game: &Game, phase: Phase, hand: ResourceCounts) -> PlayerView {
        let mut view = game.view(Some(0));
        view.phase = phase;
        if let Some(own) = view.own.as_mut() {
            own.hand = hand;
        }
        view
    }

    fn settlements_of(view: &PlayerView, seat: Seat) -> Vec<CornerId> {
        view.board
            .corner_ids()
            .filter(|corner| {
                view.board.building(*corner).is_some_and(|building| {
                    building.seat == seat && building.kind == BuildingKind::Settlement
                })
            })
            .collect()
    }

    fn seats_on(view: &PlayerView, tile: TileId) -> Vec<Seat> {
        view.board
            .tile(tile)
            .unwrap()
            .corners
            .iter()
            .filter_map(|corner| view.board.building(*corner))
            .map(|building| building.seat)
            .collect()
    }

    #[test]
    fn first_settlement_is_close_to_the_most_pips() {
        let pips = |view: &PlayerView, corner: CornerId| -> u32 {
            corner_production(&view.board, corner).iter().sum()
        };
        for seed in 0..20 {
            let game = Game::new(GameSettings {
                seats: 4,
                points_to_win: 10,
                seed,
            })
            .unwrap();
            let view = game.view(Some(0));
            let legal = game.legal_actions(0);
            let most = view
                .board
                .corner_ids()
                .map(|corner| pips(&view, corner))
                .max()
                .unwrap();

            let Action::PlaceSettlement { corner } = HeuristicBot::new().choose(&view, &legal)
            else {
                panic!("no settlement placed");
            };

            // Resource mix and ports may cost a few pips, never more.
            let taken = pips(&view, corner);
            assert!(taken + 5 >= most, "seed {seed}: {taken} of {most} pips");
        }
    }

    #[test]
    fn robber_hits_the_leader_and_spares_own_tiles() {
        let game = after_setup(3);
        let phase = Phase::MoveRobber { then_steal: true };
        let mut view = view_with(&game, phase, ResourceCounts::default());
        view.players[2].points = 6;
        let legal: Vec<Action> = view
            .board
            .tile_ids()
            .filter(|tile| *tile != view.board.robber())
            .map(|tile| Action::MoveRobber { tile })
            .collect();

        let Action::MoveRobber { tile } = HeuristicBot::new().choose(&view, &legal) else {
            panic!("no robber move");
        };

        let seats = seats_on(&view, tile);
        assert!(seats.contains(&2), "{seats:?}");
        assert!(!seats.contains(&0), "{seats:?}");
    }

    #[test]
    fn steals_from_the_seat_with_most_points() {
        let game = after_setup(1);
        let phase = Phase::Steal { tile: TileId(0) };
        let mut view = view_with(&game, phase, ResourceCounts::default());
        view.players[3].points = 5;
        let legal = vec![Action::Steal { victim: 1 }, Action::Steal { victim: 3 }];

        assert_eq!(
            HeuristicBot::new().choose(&view, &legal),
            Action::Steal { victim: 3 }
        );
    }

    #[test]
    fn discard_keeps_the_city_cards() {
        let game = after_setup(2);
        let hand = ResourceCounts::new([0, 2, 2, 2, 3]);
        let phase = Phase::Discard {
            owed: vec![OwedDiscard { seat: 0, cards: 4 }],
        };
        let view = view_with(&game, phase, hand);
        let legal: Vec<Action> = [
            [0, 2, 0, 2, 0],
            [0, 1, 1, 0, 2],
            [0, 2, 2, 0, 0],
            [0, 0, 2, 2, 0],
        ]
        .into_iter()
        .map(|counts| Action::Discard {
            resources: ResourceCounts::new(counts),
        })
        .collect();

        assert_eq!(HeuristicBot::new().choose(&view, &legal), legal[2]);
    }

    #[test]
    fn city_comes_before_settlement_and_card() {
        let game = after_setup(4);
        let view = view_with(&game, Phase::Main, ResourceCounts::new([1, 1, 1, 3, 3]));
        let corner = settlements_of(&view, 0)[0];
        let legal = vec![
            Action::BuyDevelopmentCard,
            Action::BuildSettlement {
                corner: CornerId(0),
            },
            Action::BuildCity { corner },
            Action::EndTurn,
        ];

        assert_eq!(
            HeuristicBot::new().choose(&view, &legal),
            Action::BuildCity { corner }
        );
    }

    #[test]
    fn offers_a_held_card_once_per_turn() {
        let game = after_setup(5);
        let view = view_with(&game, Phase::Main, ResourceCounts::new([1, 0, 0, 2, 2]));
        let legal = vec![Action::EndTurn];
        let mut bot = HeuristicBot::new();

        let first = bot.choose(&view, &legal);
        let second = bot.choose(&view, &legal);

        assert_eq!(
            first,
            Action::OfferTrade {
                give: ResourceCounts::single(Resource::Clay, 1),
                receive: ResourceCounts::single(Resource::Ore, 1),
                to: None,
            }
        );
        assert_eq!(second, Action::EndTurn);
    }

    #[test]
    fn knight_before_the_roll_only_when_the_robber_blocks_an_own_tile() {
        let legal = vec![Action::RollDice, Action::PlayKnight];
        let mut game = after_setup(6);
        let mut bots: Vec<HeuristicBot> = (0..4).map(|_| HeuristicBot::new()).collect();
        let mut seen_blocked = false;
        let mut seen_free = false;
        while !(seen_blocked && seen_free) {
            let seat = game.pending_seats()[0];
            let view = game.view(Some(seat));
            if view.phase == Phase::Roll {
                let blocked = robber_blocks(&view.board, seat);
                let expected = if blocked {
                    Action::PlayKnight
                } else {
                    Action::RollDice
                };
                assert_eq!(HeuristicBot::new().choose(&view, &legal), expected);
                seen_blocked |= blocked;
                seen_free |= !blocked;
            }
            let action = bots[usize::from(seat)].choose(&view, &game.legal_actions(seat));
            game.apply(seat, action).unwrap();
        }
    }

    /// Seat 1 offers `give` for `receive` to us; our hand saves for a city (one ore short).
    fn offered_view(give: Resource, receive: Resource, offerer_points: u8) -> PlayerView {
        let game = after_setup(7);
        let hand = ResourceCounts::new([1, 0, 0, 2, 2]);
        let offer = TradeOffer {
            offerer: 1,
            give: ResourceCounts::single(give, 1),
            receive: ResourceCounts::single(receive, 1),
            addressed: None,
            answers: Vec::new(),
        };
        let mut view = view_with(&game, Phase::TradeOffered { offer }, hand);
        view.players[1].points = offerer_points;
        view
    }

    fn answer(view: &PlayerView) -> Action {
        let legal = vec![Action::AcceptTrade, Action::RejectTrade];
        HeuristicBot::new().choose(view, &legal)
    }

    #[test]
    fn accepts_an_offer_that_completes_the_build() {
        let view = offered_view(Resource::Ore, Resource::Clay, 3);

        assert_eq!(answer(&view), Action::AcceptTrade);
    }

    #[test]
    fn rejects_an_offer_that_takes_a_needed_card() {
        let view = offered_view(Resource::Ore, Resource::Wheat, 3);

        assert_eq!(answer(&view), Action::RejectTrade);
    }

    #[test]
    fn rejects_an_offer_that_does_not_help() {
        let view = offered_view(Resource::Sheep, Resource::Clay, 3);

        assert_eq!(answer(&view), Action::RejectTrade);
    }

    #[test]
    fn rejects_a_good_offer_from_a_seat_near_the_win() {
        let mut view = offered_view(Resource::Ore, Resource::Clay, 8);
        assert_eq!(answer(&view), Action::RejectTrade);

        view.points_to_win = 15;
        assert_eq!(answer(&view), Action::AcceptTrade);
    }
}
