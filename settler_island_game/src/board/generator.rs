use rand::seq::SliceRandom;
use rand::Rng;
use rand_chacha::ChaCha8Rng;

use crate::board::{topology, Board, Corner, Edge, Port, Tile, TileId};
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

const PORT_COUNT: usize = 9;

/// The base board: shuffled terrain (desert anywhere), shuffled chips with no 6 or 8 touching, ports on the coast, robber on the desert.
pub(crate) fn generate(rng: &mut ChaCha8Rng) -> Board {
    let topology = topology::build(ISLAND_RADIUS);

    let mut terrains: Vec<Option<Resource>> = TERRAIN_COUNTS
        .iter()
        .flat_map(|(terrain, count)| std::iter::repeat_n(*terrain, *count))
        .collect();
    terrains.shuffle(rng);

    let mut tiles = Vec::with_capacity(topology.tiles.len());
    let mut robber = TileId(0);
    for (index, (coordinates, corners)) in topology
        .tiles
        .iter()
        .zip(topology.tile_corners.iter())
        .enumerate()
    {
        let resource = terrains.get(index).copied().flatten();
        if resource.is_none() {
            robber = TileId(index as u8);
        }
        tiles.push(Tile {
            coordinates: *coordinates,
            resource,
            number: None,
            corners: *corners,
        });
    }
    deal_chips(&mut tiles, rng);

    let mut corners = topology.corners;
    let mut edges = topology.edges;
    place_ports(&mut corners, &mut edges, rng);

    Board {
        buildings: vec![None; corners.len()],
        roads: vec![None; edges.len()],
        tiles,
        corners,
        edges,
        robber,
    }
}

/// Shuffled chips on every land tile, dealt again until no 6 or 8 touches another (base rules, variable setup).
fn deal_chips(tiles: &mut [Tile], rng: &mut ChaCha8Rng) {
    let mut chips = NUMBER_CHIPS.to_vec();
    loop {
        chips.shuffle(rng);
        let mut remaining = chips.iter().copied();
        for tile in tiles.iter_mut() {
            tile.number = tile.resource.and_then(|_| remaining.next());
        }
        if !red_numbers_touch(tiles) {
            return;
        }
    }
}

fn red_numbers_touch(tiles: &[Tile]) -> bool {
    let red: Vec<&Tile> = tiles
        .iter()
        .filter(|tile| matches!(tile.number, Some(6 | 8)))
        .collect();
    red.iter().enumerate().any(|(index, first)| {
        red[index + 1..]
            .iter()
            .any(|second| first.coordinates.distance(&second.coordinates) == 1)
    })
}

/// Coast edges (one land tile on both corners) in order around the island.
fn coast_ring(corners: &[Corner], edges: &[Edge]) -> Vec<usize> {
    let on_coast = |edge: &Edge| {
        let [first, second] = edge.corners;
        let first_tiles = &corners[usize::from(first.0)].tiles;
        let second_tiles = &corners[usize::from(second.0)].tiles;
        first_tiles
            .iter()
            .filter(|tile| second_tiles.contains(tile))
            .count()
            == 1
    };
    let coast: Vec<usize> = (0..edges.len())
        .filter(|index| on_coast(&edges[*index]))
        .collect();
    let shares_corner = |first: usize, second: usize| {
        edges[first]
            .corners
            .iter()
            .any(|corner| edges[second].corners.contains(corner))
    };

    let mut ring = vec![coast[0]];
    while ring.len() < coast.len() {
        let last = ring[ring.len() - 1];
        let next = coast
            .iter()
            .copied()
            .find(|candidate| !ring.contains(candidate) && shares_corner(last, *candidate));
        match next {
            Some(edge) => ring.push(edge),
            None => break,
        }
    }
    ring
}

/// 4 generic and one specific port per resource on shuffled coast edges with at least one free coast edge between.
fn place_ports(corners: &mut [Corner], edges: &mut [Edge], rng: &mut ChaCha8Rng) {
    let ring = coast_ring(corners, edges);
    let mut ports: Vec<Port> = std::iter::repeat_n(Port::Generic, 4)
        .chain(Resource::ALL.into_iter().map(Port::Specific))
        .collect();
    ports.shuffle(rng);

    // Every port is followed by one free edge; the leftover free edges go to random gaps.
    let mut gaps = vec![1usize; PORT_COUNT];
    for _ in 0..ring.len().saturating_sub(PORT_COUNT * 2) {
        gaps[rng.random_range(0..PORT_COUNT)] += 1;
    }
    let mut position = rng.random_range(0..ring.len());
    for (port, gap) in ports.into_iter().zip(gaps) {
        let edge = &mut edges[ring[position % ring.len()]];
        edge.port = Some(port);
        for corner in edge.corners {
            corners[usize::from(corner.0)].port = Some(port);
        }
        position += 1 + gap;
    }
}

#[cfg(test)]
mod tests {
    use rand::SeedableRng;

    use super::*;
    use crate::board::CornerId;

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
    fn port_edges_name_exactly_the_port_corners() {
        for seed in 0..50 {
            let board = board_for(seed);
            let port_edges: Vec<&Edge> = board
                .edges()
                .iter()
                .filter(|edge| edge.port.is_some())
                .collect();
            assert_eq!(port_edges.len(), PORT_COUNT);
            let mut from_edges: Vec<CornerId> = Vec::new();
            for edge in &port_edges {
                for corner in edge.corners {
                    assert_eq!(
                        board.corner(corner).and_then(|corner| corner.port),
                        edge.port
                    );
                    from_edges.push(corner);
                }
            }
            from_edges.sort();
            let from_corners: Vec<CornerId> =
                port_corners(&board).into_iter().map(|(id, _)| id).collect();
            assert_eq!(from_edges, from_corners, "seed {seed}");
        }
    }

    #[test]
    fn red_numbers_never_touch() {
        for seed in 0..300 {
            let board = board_for(seed);
            let red: Vec<&Tile> = board
                .tiles()
                .iter()
                .filter(|tile| matches!(tile.number, Some(6 | 8)))
                .collect();
            for (index, first) in red.iter().enumerate() {
                for second in &red[index + 1..] {
                    assert!(
                        first.coordinates.distance(&second.coordinates) > 1,
                        "seed {seed}: a 6 or 8 touches another"
                    );
                }
            }
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

    fn port_corners(board: &Board) -> Vec<(CornerId, Port)> {
        board
            .corner_ids()
            .filter_map(|id| Some((id, board.corner(id)?.port?)))
            .collect()
    }

    #[test]
    fn nine_ports_of_the_right_kinds_on_the_coast() {
        for seed in 0..50 {
            let board = board_for(seed);
            let corners = port_corners(&board);
            let count = |wanted: Port| corners.iter().filter(|(_, port)| *port == wanted).count();

            // Two corners per port; 18 distinct corners also means no two ports share a corner.
            assert_eq!(corners.len(), 18, "seed {seed}");
            assert_eq!(count(Port::Generic), 8, "seed {seed}");
            for resource in Resource::ALL {
                assert_eq!(count(Port::Specific(resource)), 2, "seed {seed}");
            }
            for (corner, _) in &corners {
                assert!(
                    board.corner(*corner).unwrap().tiles.len() < 3,
                    "seed {seed}"
                );
            }
        }
    }

    #[test]
    fn both_corners_of_a_port_are_joined_by_a_coast_edge() {
        for seed in 0..50 {
            let board = board_for(seed);
            let joined = |corner: CornerId, port: Port| {
                board
                    .corner(corner)
                    .unwrap()
                    .neighbors
                    .iter()
                    .any(|other| board.corner(*other).unwrap().port == Some(port))
            };

            for (corner, port) in port_corners(&board) {
                assert!(joined(corner, port), "seed {seed} corner {corner:?}");
            }
        }
    }

    #[test]
    fn ports_vary_with_the_seed() {
        assert_ne!(port_corners(&board_for(1)), port_corners(&board_for(2)));
    }
}
