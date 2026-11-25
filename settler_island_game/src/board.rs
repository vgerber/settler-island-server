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
