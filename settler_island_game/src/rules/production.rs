use crate::board::{BuildingKind, CornerId};
use crate::event::Event;
use crate::game::{Game, Seat};
use crate::resource::{Resource, ResourceCounts};

/// Cards a city yields per producing tile; a settlement yields one.
pub const CITY_PRODUCTION_FACTOR: u8 = 2;

/// Pays every tile showing `number` that does not hold the robber: 1 per settlement, 2 per city.
pub(crate) fn produce(game: &mut Game, number: u8) -> Vec<Event> {
    let mut owed = vec![ResourceCounts::default(); game.players.len()];
    let producing = game
        .board
        .tile_ids()
        .filter(|tile| *tile != game.board.robber())
        .filter_map(|tile| game.board.tile(tile))
        .filter(|tile| tile.number == Some(number));
    for tile in producing {
        let Some(resource) = tile.resource else {
            continue;
        };
        for corner in tile.corners {
            add_building_yield(game, corner, resource, &mut owed);
        }
    }
    distribute(game, &owed)
}

/// What the second setup settlement yields: one of each adjacent resource.
pub(crate) fn settlement_yield(game: &Game, corner: CornerId) -> ResourceCounts {
    let mut resources = ResourceCounts::default();
    let tiles = game
        .board
        .corner(corner)
        .map(|corner| corner.tiles.as_slice())
        .unwrap_or_default();
    for tile in tiles {
        if let Some(resource) = game.board.tile(*tile).and_then(|tile| tile.resource) {
            resources.set(resource, resources.get(resource) + 1);
        }
    }
    resources
}

fn add_building_yield(
    game: &Game,
    corner: CornerId,
    resource: Resource,
    owed: &mut [ResourceCounts],
) {
    let Some(building) = game.board.building(corner) else {
        return;
    };
    let Some(counts) = owed.get_mut(usize::from(building.seat)) else {
        return;
    };
    let amount = match building.kind {
        BuildingKind::Settlement => 1,
        BuildingKind::City => CITY_PRODUCTION_FACTOR,
    };
    counts.set(resource, counts.get(resource) + amount);
}

/// Pays `owed[seat]` from the bank. If the bank cannot cover a resource for everyone, nobody gets it, unless only
/// one seat is owed it: that seat gets what is left.
pub(crate) fn distribute(game: &mut Game, owed: &[ResourceCounts]) -> Vec<Event> {
    let mut paid = vec![ResourceCounts::default(); owed.len()];
    for resource in Resource::ALL {
        let available = game.bank.get(resource);
        let total: u32 = owed
            .iter()
            .map(|counts| u32::from(counts.get(resource)))
            .sum();
        let receivers = owed
            .iter()
            .filter(|counts| counts.get(resource) > 0)
            .count();
        if total > u32::from(available) && receivers > 1 {
            continue;
        }
        for (counts, payment) in owed.iter().zip(paid.iter_mut()) {
            let amount = counts.get(resource).min(game.bank.get(resource));
            payment.set(resource, amount);
            game.bank.set(resource, game.bank.get(resource) - amount);
        }
    }

    let mut events = Vec::new();
    for (seat, payment) in paid.iter().enumerate() {
        if payment.is_empty() {
            continue;
        }
        if let Some(player) = game.players.get_mut(seat) {
            player.hand.deposit(payment);
        }
        events.push(Event::ResourcesProduced {
            seat: seat as Seat,
            resources: *payment,
        });
    }
    events
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::board::Building;
    use crate::rules::test_support::{new_game, tile_with_number};

    #[test]
    fn cities_pay_double_and_the_robber_blocks_its_tile() {
        let mut game = new_game(4, 11);
        // 12 is on exactly one tile, so nothing else produces.
        let (tile, resource) = tile_with_number(&game, 12);
        let corners = game.board.tiles()[usize::from(tile.0)].corners;
        let settlement = Building {
            seat: 1,
            kind: BuildingKind::Settlement,
        };
        let city = Building {
            seat: 2,
            kind: BuildingKind::City,
        };
        game.board.set_building(corners[0], settlement);
        game.board.set_building(corners[3], city);

        let events = produce(&mut game, 12);

        let expected = vec![
            Event::ResourcesProduced {
                seat: 1,
                resources: ResourceCounts::single(resource, 1),
            },
            Event::ResourcesProduced {
                seat: 2,
                resources: ResourceCounts::single(resource, 2),
            },
        ];
        assert_eq!(events, expected);
        assert_eq!(game.bank.get(resource), 19 - 3);

        game.board.set_robber(tile);
        assert_eq!(produce(&mut game, 12), Vec::new());
        assert_eq!(game.bank.get(resource), 19 - 3);
    }

    #[test]
    fn bank_shortage_pays_nobody_when_several_are_owed() {
        let mut game = new_game(4, 3);
        game.bank.set(Resource::Ore, 2);
        let owed = [
            ResourceCounts::new([1, 0, 0, 0, 2]),
            ResourceCounts::new([0, 0, 0, 0, 1]),
            ResourceCounts::default(),
            ResourceCounts::default(),
        ];

        let events = distribute(&mut game, &owed);

        assert_eq!(game.players[0].hand, ResourceCounts::new([1, 0, 0, 0, 0]));
        assert_eq!(game.players[1].hand, ResourceCounts::default());
        assert_eq!(game.bank.get(Resource::Ore), 2);
        assert_eq!(events.len(), 1);
    }

    #[test]
    fn bank_shortage_gives_a_single_receiver_what_is_left() {
        let mut game = new_game(3, 3);
        game.bank.set(Resource::Wheat, 1);
        let owed = [
            ResourceCounts::default(),
            ResourceCounts::single(Resource::Wheat, 2),
            ResourceCounts::default(),
        ];

        distribute(&mut game, &owed);

        assert_eq!(
            game.players[1].hand,
            ResourceCounts::single(Resource::Wheat, 1)
        );
        assert_eq!(game.bank.get(Resource::Wheat), 0);
    }
}
