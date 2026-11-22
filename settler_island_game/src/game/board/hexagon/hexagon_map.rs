use std::{cell::RefCell, collections::HashMap};

use super::{cube_coordinates::CubeCoordinates, hexagon_tile::HexagonTile};

pub struct HexagonMap {
    tiles: HashMap<CubeCoordinates, RefCell<HexagonTile>>,
}

impl Default for HexagonMap {
    fn default() -> Self {
        Self::new()
    }
}

impl HexagonMap {
    pub fn new() -> Self {
        HexagonMap {
            tiles: HashMap::new(),
        }
    }

    pub fn add_tile(&mut self, tile: HexagonTile) -> Result<(), String> {
        match self.tiles.contains_key(tile.get_coordinates()) {
            true => Err(format!(
                "Coordinates {:?} already blocked",
                tile.get_coordinates()
            )),
            false => {
                self.tiles
                    .insert(*(tile.get_coordinates()), RefCell::new(tile));
                Ok(())
            }
        }
    }

    pub fn get_tile(&self, coordinates: &CubeCoordinates) -> Option<&RefCell<HexagonTile>> {
        self.tiles.get(coordinates)
    }

    /// # Return Order (Filters non existing tiles)
    /// ```text
    ///  4 5
    /// 3 T 0
    ///  2 1
    /// ```
    pub fn get_tile_neighbors(&self, coordinates: &CubeCoordinates) -> Vec<&RefCell<HexagonTile>> {
        coordinates
            .get_neighbor_coordinates()
            .into_iter()
            .filter_map(|coordinates| self.get_tile(&coordinates))
            .collect()
    }

    pub fn get_tiles(&self) -> Vec<&RefCell<HexagonTile>> {
        self.tiles.values().collect()
    }
}
