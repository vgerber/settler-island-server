use serde::Serialize;

use crate::game::board::hexagon::cube_coordinates::CubeCoordinates;

#[derive(Serialize, Debug, Clone, Copy)]
pub struct RobberLocation {
    assigned_tile: CubeCoordinates,
}

impl RobberLocation {
    pub fn from(assigned_tile: CubeCoordinates) -> Self {
        RobberLocation {
            assigned_tile: assigned_tile,
        }
    }

    pub fn get_assigned_tile(&self) -> &CubeCoordinates {
        &self.assigned_tile
    }
}
