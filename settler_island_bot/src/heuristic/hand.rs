use settler_island_game::{BuildingKind, PlayerView, Purchase, Resource, ResourceCounts, Seat};

use super::evaluation::has_open_site;

/// A seven takes half of a hand above this size.
/// The goal's missing cards weigh more than those of the other builds when discarding.
const GOAL_WEIGHT: u32 = 10;
const OTHER_WEIGHT: u32 = 2;

const PURCHASES: [Purchase; 4] = [
    Purchase::City,
    Purchase::Settlement,
    Purchase::Road,
    Purchase::DevelopmentCard,
];

pub(crate) fn missing(hand: &ResourceCounts, cost: &ResourceCounts) -> ResourceCounts {
    let mut result = ResourceCounts::default();
    for resource in Resource::ALL {
        result.set(
            resource,
            cost.get(resource).saturating_sub(hand.get(resource)),
        );
    }
    result
}

pub(crate) fn spare(hand: &ResourceCounts, cost: &ResourceCounts) -> ResourceCounts {
    missing(cost, hand)
}

/// The build to save for: the cheaper of city and settlement, else a road to a new site, else a card.
pub(crate) fn goal(view: &PlayerView, seat: Seat, hand: &ResourceCounts) -> Purchase {
    let Some(player) = view.players.get(usize::from(seat)) else {
        return Purchase::DevelopmentCard;
    };
    let has_settlement = view.board.corner_ids().any(|corner| {
        view.board.building(corner).is_some_and(|building| {
            building.seat == seat && building.kind == BuildingKind::Settlement
        })
    });
    let open_site = player.settlements_left > 0 && has_open_site(&view.board, seat);
    let mut candidates = Vec::new();
    if player.cities_left > 0 && has_settlement {
        candidates.push(Purchase::City);
    }
    if open_site {
        candidates.push(Purchase::Settlement);
    }
    let cheapest = candidates
        .into_iter()
        .min_by_key(|build| missing(hand, &build.cost()).total());
    if let Some(build) = cheapest {
        return build;
    }
    if player.settlements_left > 0 && player.roads_left > 0 {
        return Purchase::Road;
    }
    Purchase::DevelopmentCard
}

/// One bank trade of spare cards toward `cost`; with `complete_only`, only when trades can cover all of it.
pub(crate) fn bank_trade_toward(
    hand: &ResourceCounts,
    cost: &ResourceCounts,
    rates: &ResourceCounts,
    bank: &ResourceCounts,
    complete_only: bool,
) -> Option<(Resource, Resource)> {
    let needed = missing(hand, cost);
    let extra = spare(hand, cost);
    let tradeable: u32 = Resource::ALL
        .iter()
        .map(|resource| u32::from(extra.get(*resource) / rates.get(*resource)))
        .sum();
    if needed.is_empty() || (complete_only && tradeable < needed.total()) {
        return None;
    }
    let give = Resource::ALL
        .into_iter()
        .filter(|resource| extra.get(*resource) >= rates.get(*resource))
        .max_by_key(|resource| extra.get(*resource) / rates.get(*resource))?;
    let receive = Resource::ALL
        .into_iter()
        .filter(|resource| needed.get(*resource) > 0 && bank.get(*resource) > 0)
        .max_by_key(|resource| needed.get(*resource))?;
    Some((give, receive))
}

/// One spare card for the single card that is still missing.
pub(crate) fn offer_toward(
    hand: &ResourceCounts,
    cost: &ResourceCounts,
) -> Option<(Resource, Resource)> {
    let needed = missing(hand, cost);
    if needed.total() != 1 {
        return None;
    }
    let extra = spare(hand, cost);
    let give = Resource::ALL
        .into_iter()
        .filter(|resource| extra.get(*resource) > 0)
        .max_by_key(|resource| extra.get(*resource))?;
    let receive = Resource::ALL
        .into_iter()
        .find(|resource| needed.get(*resource) > 0)?;
    Some((give, receive))
}

/// Higher is better: few missing cards for the goal, then for the other builds.
pub(crate) fn keep_score(kept: &ResourceCounts, goal: Purchase) -> i64 {
    let penalty: u32 = PURCHASES
        .iter()
        .map(|build| {
            let weight = if *build == goal {
                GOAL_WEIGHT
            } else {
                OTHER_WEIGHT
            };
            weight * missing(kept, &build.cost()).total()
        })
        .sum();
    -i64::from(penalty)
}

#[cfg(test)]
mod tests {
    use super::*;

    const NO_PORTS: ResourceCounts = ResourceCounts::new([4; 5]);
    const FULL_BANK: ResourceCounts = ResourceCounts::new([19; 5]);

    #[test]
    fn bank_trade_only_when_it_completes_the_build() {
        let city = Purchase::City.cost();
        let one_short = ResourceCounts::new([0, 4, 0, 2, 2]);
        let two_short = ResourceCounts::new([0, 4, 0, 1, 2]);

        assert_eq!(
            bank_trade_toward(&one_short, &city, &NO_PORTS, &FULL_BANK, true),
            Some((Resource::Wood, Resource::Ore))
        );
        assert_eq!(
            bank_trade_toward(&two_short, &city, &NO_PORTS, &FULL_BANK, true),
            None
        );
        assert!(bank_trade_toward(&two_short, &city, &NO_PORTS, &FULL_BANK, false).is_some());
    }

    #[test]
    fn bank_trade_never_gives_cards_the_build_needs_and_uses_port_rates() {
        let settlement = Purchase::Settlement.cost();
        let hand = ResourceCounts::new([1, 1, 3, 0, 0]);
        let sheep_port = NO_PORTS.with(Resource::Sheep, 2);

        assert_eq!(
            bank_trade_toward(&hand, &settlement, &NO_PORTS, &FULL_BANK, false),
            None
        );
        assert_eq!(
            bank_trade_toward(&hand, &settlement, &sheep_port, &FULL_BANK, true),
            Some((Resource::Sheep, Resource::Wheat))
        );
        let empty_wheat_bank = ResourceCounts::new([19, 19, 19, 0, 19]);
        assert_eq!(
            bank_trade_toward(&hand, &settlement, &sheep_port, &empty_wheat_bank, true),
            None
        );
    }

    #[test]
    fn offer_gives_a_spare_card_for_the_single_missing_one() {
        let settlement = Purchase::Settlement.cost();

        assert_eq!(
            offer_toward(&ResourceCounts::new([1, 1, 1, 0, 2]), &settlement),
            Some((Resource::Ore, Resource::Wheat))
        );
        assert_eq!(
            offer_toward(&ResourceCounts::new([1, 1, 0, 0, 2]), &settlement),
            None
        );
        assert_eq!(
            offer_toward(&ResourceCounts::new([1, 1, 1, 0, 0]), &settlement),
            None
        );
    }

    #[test]
    fn keep_score_prefers_the_goal_over_other_builds() {
        let city_kept = ResourceCounts::new([0, 0, 0, 2, 3]);
        let road_kept = ResourceCounts::new([1, 1, 0, 1, 2]);

        assert!(keep_score(&city_kept, Purchase::City) > keep_score(&road_kept, Purchase::City));
        assert!(keep_score(&road_kept, Purchase::Road) > keep_score(&city_kept, Purchase::Road));
    }
}
