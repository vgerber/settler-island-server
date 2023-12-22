use serde::Serialize;

use crate::game::board::hexagon::cube_coordinates::CubeCoordinates;

#[derive(Serialize, Debug, Clone, Copy)]
pub struct DiceChipLocation {
    dice_value: u8,
    assigned_tile: CubeCoordinates,
}

impl DiceChipLocation {
    pub fn from(device_value: u8, assigned_tile: CubeCoordinates) -> Self {
        DiceChipLocation {
            dice_value: device_value,
            assigned_tile: assigned_tile,
        }
    }

    pub fn get_dice_value(&self) -> &u8 {
        &self.dice_value
    }

    pub fn get_assigned_tile(&self) -> &CubeCoordinates {
        &self.assigned_tile
    }
}
