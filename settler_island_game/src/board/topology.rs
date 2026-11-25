use crate::board::{Corner, CornerId, Edge, EdgeId, TileId};
use crate::coordinates::CubeCoordinates;

/// The board geometry without terrain: tiles, corners and edges with dense ids ordered by coordinates.
pub(crate) struct Topology {
    pub tiles: Vec<CubeCoordinates>,
    pub tile_corners: Vec<[CornerId; 6]>,
    pub corners: Vec<Corner>,
    pub edges: Vec<Edge>,
}

/// A corner is identified by the three hexes (land or sea) that meet there, sorted.
type CornerKey = [CubeCoordinates; 3];

/// Builds a hexagonal island whose tiles are at most `radius` steps from the centre.
pub(crate) fn build(radius: i32) -> Topology {
    let tiles = tile_coordinates(radius);
    let corner_keys = corner_keys(&tiles);
    let tile_corners: Vec<[CornerId; 6]> = tiles
        .iter()
        .map(|tile| tile_corner_keys(tile).map(|key| position_of(&corner_keys, &key)))
        .collect();
    let edge_pairs = edge_pairs(&tile_corners);

    let mut corners: Vec<Corner> = corner_keys
        .iter()
        .map(|key| Corner {
            tiles: land_tiles(&tiles, key),
            neighbors: Vec::new(),
            edges: Vec::new(),
            port: None,
        })
        .collect();
    for (index, [first, second]) in edge_pairs.iter().enumerate() {
        let edge = EdgeId(index as u8);
        corners[usize::from(first.0)].edges.push(edge);
        corners[usize::from(first.0)].neighbors.push(*second);
        corners[usize::from(second.0)].edges.push(edge);
        corners[usize::from(second.0)].neighbors.push(*first);
    }

    let edges = edge_pairs
        .into_iter()
        .map(|corners| Edge {
            corners,
            port: None,
        })
        .collect();
    Topology {
        tiles,
        tile_corners,
        corners,
        edges,
    }
}

fn tile_coordinates(radius: i32) -> Vec<CubeCoordinates> {
    let mut tiles: Vec<CubeCoordinates> = (-radius..=radius)
        .flat_map(|q| (-radius..=radius).map(move |r| CubeCoordinates::from_qr(q, r)))
        .filter(|coordinates| CubeCoordinates::ORIGIN.distance(coordinates) <= radius)
        .collect();
    tiles.sort();
    tiles
}

fn tile_corner_keys(tile: &CubeCoordinates) -> [CornerKey; 6] {
    let neighbors = tile.neighbors();
    std::array::from_fn(|index| {
        let mut key = [*tile, neighbors[index], neighbors[(index + 1) % 6]];
        key.sort();
        key
    })
}

fn corner_keys(tiles: &[CubeCoordinates]) -> Vec<CornerKey> {
    let mut keys: Vec<CornerKey> = tiles.iter().flat_map(tile_corner_keys).collect();
    keys.sort();
    keys.dedup();
    keys
}

/// Index of `key` in the sorted `keys`; `key` is always present because both come from the same tiles.
fn position_of(keys: &[CornerKey], key: &CornerKey) -> CornerId {
    CornerId(keys.partition_point(|candidate| candidate < key) as u8)
}

fn edge_pairs(tile_corners: &[[CornerId; 6]]) -> Vec<[CornerId; 2]> {
    let mut pairs: Vec<[CornerId; 2]> = tile_corners
        .iter()
        .flat_map(|corners| {
            (0..6).map(move |index| {
                let mut pair = [corners[index], corners[(index + 1) % 6]];
                pair.sort();
                pair
            })
        })
        .collect();
    pairs.sort();
    pairs.dedup();
    pairs
}

fn land_tiles(tiles: &[CubeCoordinates], key: &CornerKey) -> Vec<TileId> {
    key.iter()
        .filter_map(|coordinates| tiles.binary_search(coordinates).ok())
        .map(|index| TileId(index as u8))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base_island_has_19_tiles_54_corners_72_edges() {
        let topology = build(2);

        assert_eq!(topology.tiles.len(), 19);
        assert_eq!(topology.corners.len(), 54);
        assert_eq!(topology.edges.len(), 72);
    }

    #[test]
    fn corner_degrees_match_a_hexagonal_island() {
        let topology = build(2);
        let count_with = |tile_count: usize, neighbor_count: usize| {
            topology
                .corners
                .iter()
                .filter(|corner| corner.tiles.len() == tile_count)
                .inspect(|corner| assert_eq!(corner.neighbors.len(), neighbor_count))
                .count()
        };

        assert_eq!(count_with(3, 3), 24);
        assert_eq!(count_with(2, 3), 12);
        assert_eq!(count_with(1, 2), 18);
    }

    #[test]
    fn tile_corners_are_distinct_and_list_the_tile() {
        let topology = build(2);

        for (tile_index, corners) in topology.tile_corners.iter().enumerate() {
            let mut sorted = corners.to_vec();
            sorted.sort();
            sorted.dedup();
            assert_eq!(sorted.len(), 6);
            for corner in corners {
                let tiles = &topology.corners[usize::from(corner.0)].tiles;
                assert!(tiles.contains(&TileId(tile_index as u8)));
            }
        }
    }

    #[test]
    fn edges_join_neighboring_corners() {
        let topology = build(2);

        for (index, edge) in topology.edges.iter().enumerate() {
            let [first, second] = edge.corners;
            let first_corner = &topology.corners[usize::from(first.0)];
            assert!(first_corner.neighbors.contains(&second));
            assert!(first_corner.edges.contains(&EdgeId(index as u8)));
        }
    }
}
