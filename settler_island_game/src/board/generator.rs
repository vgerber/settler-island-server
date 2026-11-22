use rand::seq::SliceRandom;
use rand_chacha::ChaCha8Rng;

use crate::board::{topology, Board, Tile, TileId};
use crate::resource::Resource;

const ISLAND_RADIUS: i32 = 2;
const NUMBER_CHIPS: [u8; 18] = [2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11, 12];
const TERRAIN_COUNTS: [(Option<Resource>, usize); 6] = [
    (Some(Resource::Wood), 4),
    (Some(Resource::Sheep), 4),
    (Some(Resource::Wheat), 4),
    (Some(Resource::Clay), 3),
    (Some(Resource::Ore), 3),
    (None, 1),
];

/// The base board: shuffled terrain (desert anywhere), shuffled chips, robber on the desert.
pub(crate) fn generate(rng: &mut ChaCha8Rng) -> Board {
    let topology = topology::build(ISLAND_RADIUS);

    let mut terrains: Vec<Option<Resource>> = TERRAIN_COUNTS
        .iter()
        .flat_map(|(terrain, count)| std::iter::repeat_n(*terrain, *count))
        .collect();
    terrains.shuffle(rng);
    let mut chips = NUMBER_CHIPS.to_vec();
    chips.shuffle(rng);

    let mut tiles = Vec::with_capacity(topology.tiles.len());
    let mut robber = TileId(0);
    for (index, (coordinates, corners)) in topology
        .tiles
        .iter()
        .zip(topology.tile_corners.iter())
        .enumerate()
    {
        let resource = terrains.get(index).copied().flatten();
        let number = resource.and_then(|_| chips.pop());
        if resource.is_none() {
            robber = TileId(index as u8);
        }
        tiles.push(Tile {
            coordinates: *coordinates,
            resource,
            number,
            corners: *corners,
        });
    }

    Board {
        buildings: vec![None; topology.corners.len()],
        roads: vec![None; topology.edges.len()],
        tiles,
        corners: topology.corners,
        edges: topology.edges,
        robber,
    }
}

#[cfg(test)]
mod tests {
    use rand::SeedableRng;

    use super::*;

    fn board_for(seed: u64) -> Board {
        generate(&mut ChaCha8Rng::seed_from_u64(seed))
    }

    #[test]
    fn chips_and_terrain_are_exactly_the_base_set() {
        let board = board_for(7);
        let mut chips: Vec<u8> = board
            .tiles()
            .iter()
            .filter_map(|tile| tile.number)
            .collect();
        chips.sort();
        let count = |resource: Option<Resource>| {
            board
                .tiles()
                .iter()
                .filter(|tile| tile.resource == resource)
                .count()
        };

        assert_eq!(chips, NUMBER_CHIPS.to_vec());
        for (terrain, expected) in TERRAIN_COUNTS {
            assert_eq!(count(terrain), expected);
        }
    }

    #[test]
    fn robber_starts_on_the_desert_which_has_no_chip() {
        for seed in 0..20 {
            let board = board_for(seed);
            let desert = board.tile(board.robber());

            assert_eq!(desert.map(|tile| tile.resource), Some(None));
            assert_eq!(desert.and_then(|tile| tile.number), None);
        }
    }

    #[test]
    fn same_seed_same_board_different_seed_different_board() {
        assert_eq!(board_for(42), board_for(42));
        assert_ne!(board_for(42), board_for(43));
    }

    #[test]
    fn desert_is_not_always_in_the_centre() {
        let desert_positions: Vec<TileId> = (0..20).map(|seed| board_for(seed).robber()).collect();

        assert!(desert_positions
            .iter()
            .any(|position| *position != desert_positions[0]));
    }
}
