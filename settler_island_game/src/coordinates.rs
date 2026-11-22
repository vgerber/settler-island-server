use std::ops::Add;

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

/// Hex cube coordinates; `q + r + s == 0` always holds.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, JsonSchema,
)]
pub struct CubeCoordinates {
    pub q: i32,
    pub r: i32,
    pub s: i32,
}

const DIRECTIONS: [CubeCoordinates; 6] = [
    CubeCoordinates { q: 1, r: 0, s: -1 },
    CubeCoordinates { q: 0, r: 1, s: -1 },
    CubeCoordinates { q: -1, r: 1, s: 0 },
    CubeCoordinates { q: -1, r: 0, s: 1 },
    CubeCoordinates { q: 0, r: -1, s: 1 },
    CubeCoordinates { q: 1, r: -1, s: 0 },
];

impl CubeCoordinates {
    pub const ORIGIN: CubeCoordinates = CubeCoordinates { q: 0, r: 0, s: 0 };

    pub fn from_qr(q: i32, r: i32) -> Self {
        CubeCoordinates { q, r, s: -q - r }
    }

    /// The six neighbours, going around the hexagon so that consecutive entries are neighbours too.
    pub fn neighbors(&self) -> [CubeCoordinates; 6] {
        DIRECTIONS.map(|direction| *self + direction)
    }

    pub fn distance(&self, other: &CubeCoordinates) -> i32 {
        ((self.q - other.q).abs() + (self.r - other.r).abs() + (self.s - other.s).abs()) / 2
    }
}

impl Add for CubeCoordinates {
    type Output = Self;

    fn add(self, other: Self) -> Self {
        CubeCoordinates {
            q: self.q + other.q,
            r: self.r + other.r,
            s: self.s + other.s,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn neighbors_are_at_distance_one_and_consecutive_ones_touch() {
        let center = CubeCoordinates::from_qr(1, -2);
        let neighbors = center.neighbors();

        for (index, neighbor) in neighbors.iter().enumerate() {
            assert_eq!(neighbor.q + neighbor.r + neighbor.s, 0);
            assert_eq!(center.distance(neighbor), 1);
            assert_eq!(neighbor.distance(&neighbors[(index + 1) % 6]), 1);
        }
    }

    #[test]
    fn distance_counts_hex_steps() {
        let far = CubeCoordinates::from_qr(2, -1);

        assert_eq!(CubeCoordinates::ORIGIN.distance(&far), 2);
        assert_eq!(far.distance(&CubeCoordinates::from_qr(-2, 2)), 4);
    }
}
