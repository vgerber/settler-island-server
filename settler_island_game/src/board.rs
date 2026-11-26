mod generator;
mod topology;

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

use crate::coordinates::CubeCoordinates;
use crate::game::Seat;
use crate::resource::Resource;

pub(crate) use generator::generate;

#[derive(
    Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, JsonSchema,
)]
pub struct TileId(pub u8);

#[derive(
    Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, JsonSchema,
)]
pub struct CornerId(pub u8);

#[derive(
    Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, JsonSchema,
)]
pub struct EdgeId(pub u8);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub enum Port {
    /// Trades 3:1 for any resource.
    Generic,
    /// Trades 2:1 for this resource.
    Specific(Resource),
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct Tile {
    pub coordinates: CubeCoordinates,
    /// `None` is the desert.
    pub resource: Option<Resource>,
    pub number: Option<u8>,
    /// Corners going around the tile; corner `i` lies between neighbour `i` and `i + 1`.
    pub corners: [CornerId; 6],
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct Corner {
    /// Land tiles touching this corner (1 to 3).
    pub tiles: Vec<TileId>,
    pub neighbors: Vec<CornerId>,
    pub edges: Vec<EdgeId>,
    pub port: Option<Port>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct Edge {
    pub corners: [CornerId; 2],
    /// The port this coast edge holds; both its corners trade at that port.
    #[serde(default)]
    pub port: Option<Port>,
}

impl Edge {
    /// The corner at the other end, or `None` when `corner` is not an end of this edge.
    pub fn other_end(&self, corner: CornerId) -> Option<CornerId> {
        let [first, second] = self.corners;
        if corner == first {
            return Some(second);
        }
        (corner == second).then_some(first)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub enum BuildingKind {
    Settlement,
    City,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub struct Building {
    pub seat: Seat,
    pub kind: BuildingKind,
}

/// The layout plus the pieces on it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct Board {
    tiles: Vec<Tile>,
    corners: Vec<Corner>,
    edges: Vec<Edge>,
    buildings: Vec<Option<Building>>,
    roads: Vec<Option<Seat>>,
    robber: TileId,
}

impl Board {
    pub fn tiles(&self) -> &[Tile] {
        &self.tiles
    }

    pub fn corners(&self) -> &[Corner] {
        &self.corners
    }

    pub fn edges(&self) -> &[Edge] {
        &self.edges
    }

    pub fn tile(&self, id: TileId) -> Option<&Tile> {
        self.tiles.get(usize::from(id.0))
    }

    pub fn corner(&self, id: CornerId) -> Option<&Corner> {
        self.corners.get(usize::from(id.0))
    }

    pub fn edge(&self, id: EdgeId) -> Option<&Edge> {
        self.edges.get(usize::from(id.0))
    }

    pub fn building(&self, id: CornerId) -> Option<Building> {
        self.buildings.get(usize::from(id.0)).copied().flatten()
    }

    /// The corner exists, is empty and no neighbouring corner holds a building (the distance rule).
    pub fn is_settlement_site(&self, id: CornerId) -> bool {
        let Some(location) = self.corner(id) else {
            return false;
        };
        self.building(id).is_none()
            && location
                .neighbors
                .iter()
                .all(|neighbor| self.building(*neighbor).is_none())
    }

    /// The seat's buildings with their corners, in corner order.
    pub fn buildings_of(&self, seat: Seat) -> impl Iterator<Item = (CornerId, Building)> + '_ {
        self.corner_ids().filter_map(move |corner| {
            let building = self.building(corner)?;
            (building.seat == seat).then_some((corner, building))
        })
    }

    /// The corner exists and one of its edges holds a road of `seat`.
    pub fn touches_road(&self, seat: Seat, id: CornerId) -> bool {
        self.corner(id).is_some_and(|location| {
            location
                .edges
                .iter()
                .any(|edge| self.road(*edge) == Some(seat))
        })
    }

    pub fn road(&self, id: EdgeId) -> Option<Seat> {
        self.roads.get(usize::from(id.0)).copied().flatten()
    }

    pub fn robber(&self) -> TileId {
        self.robber
    }

    pub fn tile_ids(&self) -> impl Iterator<Item = TileId> + '_ {
        (0..self.tiles.len()).map(|index| TileId(index as u8))
    }

    pub fn corner_ids(&self) -> impl Iterator<Item = CornerId> + '_ {
        (0..self.corners.len()).map(|index| CornerId(index as u8))
    }

    pub fn edge_ids(&self) -> impl Iterator<Item = EdgeId> + '_ {
        (0..self.edges.len()).map(|index| EdgeId(index as u8))
    }

    /// Callers validate `id` first; an unknown id changes nothing.
    pub(crate) fn set_building(&mut self, id: CornerId, building: Building) {
        if let Some(slot) = self.buildings.get_mut(usize::from(id.0)) {
            *slot = Some(building);
        }
    }

    /// Callers validate `id` first; an unknown id changes nothing.
    pub(crate) fn set_road(&mut self, id: EdgeId, seat: Seat) {
        if let Some(slot) = self.roads.get_mut(usize::from(id.0)) {
            *slot = Some(seat);
        }
    }

    pub(crate) fn set_robber(&mut self, id: TileId) {
        self.robber = id;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rules::test_support::{new_game, put_road, put_settlement};

    #[test]
    fn other_end_returns_the_far_corner_only_for_an_end() {
        let game = new_game(3, 7);
        let edge = &game.board.edges()[0];
        let [first, second] = edge.corners;
        assert_eq!(edge.other_end(first), Some(second));
        assert_eq!(edge.other_end(second), Some(first));
        let stranger = game
            .board
            .corner_ids()
            .find(|corner| *corner != first && *corner != second)
            .unwrap();
        assert_eq!(edge.other_end(stranger), None);
    }

    #[test]
    fn buildings_of_lists_only_the_seats_buildings() {
        let mut game = new_game(3, 7);
        let corners: Vec<CornerId> = game.board.corner_ids().take(20).step_by(7).collect();
        put_settlement(&mut game, 0, corners[0]);
        put_settlement(&mut game, 1, corners[1]);
        put_settlement(&mut game, 0, corners[2]);
        let own: Vec<CornerId> = game
            .board
            .buildings_of(0)
            .map(|(corner, _)| corner)
            .collect();
        assert_eq!(own, vec![corners[0], corners[2]]);
    }

    #[test]
    fn touches_road_needs_the_seats_own_road_at_the_corner() {
        let mut game = new_game(3, 7);
        let edge = game.board.edges()[0].clone();
        let [first, second] = edge.corners;
        put_road(&mut game, 0, first, second);
        assert!(game.board.touches_road(0, first));
        assert!(game.board.touches_road(0, second));
        assert!(!game.board.touches_road(1, first));
    }
}
