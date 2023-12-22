use crate::game::board::{
    location::settlement_location::SettlementLocationId, resource::base_resource::ResourcedId,
};

use super::cube_coordinates::CubeCoordinates;

pub enum TileType {
    FillerTile(),
    ResourceTile(ResourcedId),
}

pub struct HexagonTile {
    coordinates: CubeCoordinates,
    tile_type: TileType,
    corner_settlements: Vec<SettlementLocationId>,
}

impl HexagonTile {
    pub fn from(coordinates: CubeCoordinates, tile_type: TileType) -> Self {
        HexagonTile {
            coordinates: coordinates,
            tile_type: tile_type,
            corner_settlements: vec![],
        }
    }

    pub fn get_coordinates(&self) -> &CubeCoordinates {
        &self.coordinates
    }

    pub fn get_type(&self) -> &TileType {
        &self.tile_type
    }

    pub fn get_corner_settlement_ids(&self) -> &Vec<SettlementLocationId> {
        &self.corner_settlements
    }

    pub fn add_corner_settlement(
        &mut self,
        settlement_id: SettlementLocationId,
    ) -> Result<(), String> {
        if self.corner_settlements.contains(&settlement_id) {
            return Err(format!("{} already in corner settlements", &settlement_id));
        }
        self.corner_settlements.push(settlement_id);
        Ok(())
    }
}
