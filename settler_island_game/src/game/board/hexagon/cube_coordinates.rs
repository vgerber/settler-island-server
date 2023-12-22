use std::ops::{Add, AddAssign};

use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct CubeCoordinates {
    pub q: i32,
    pub r: i32,
    pub s: i32,
}

impl CubeCoordinates {
    pub fn from(q: i32, r: i32, s: i32) -> Self {
        CubeCoordinates { q: q, r: r, s: s }
    }

    pub fn from_rs(r: i32, s: i32) -> Self {
        CubeCoordinates::from(-r - s, r, s)
    }

    pub fn from_qs(q: i32, s: i32) -> Self {
        CubeCoordinates::from(q, -q - s, s)
    }

    pub fn from_qr(q: i32, r: i32) -> Self {
        CubeCoordinates::from(q, r, -q - r)
    }

    ///
    /// # Return Order
    /// ```
    ///  4 5
    /// 3 T 0
    ///  2 1
    /// ```
    pub fn get_neighbor_coordinates(&self) -> Vec<CubeCoordinates> {
        vec![
            CubeCoordinates::from(1, 0, -1),
            CubeCoordinates::from(0, 1, -1),
            CubeCoordinates::from(-1, 1, 0),
            CubeCoordinates::from(-1, 0, 1),
            CubeCoordinates::from(0, -1, 1),
            CubeCoordinates::from(1, -1, 0),
        ]
        .into_iter()
        .map(|coordinates| coordinates + *self)
        .collect()
    }

    pub fn min(coordinates: &Vec<CubeCoordinates>) -> CubeCoordinates {
        if coordinates.is_empty() {
            panic!("Empty cube coordinates passed")
        }

        CubeCoordinates {
            q: coordinates.iter().map(|c| c.q).min().unwrap(),
            r: coordinates.iter().map(|c| c.r).min().unwrap(),
            s: coordinates.iter().map(|c| c.s).min().unwrap(),
        }
    }

    pub fn max(coordinates: &Vec<CubeCoordinates>) -> CubeCoordinates {
        if coordinates.is_empty() {
            panic!("Empty cube coordinates passed")
        }

        CubeCoordinates {
            q: coordinates.iter().map(|c| c.q).max().unwrap(),
            r: coordinates.iter().map(|c| c.r).max().unwrap(),
            s: coordinates.iter().map(|c| c.s).max().unwrap(),
        }
    }
}

impl AddAssign for CubeCoordinates {
    fn add_assign(&mut self, rhs: Self) {
        *self = Self {
            q: self.q + rhs.q,
            r: self.r + rhs.r,
            s: self.s + rhs.s,
        };
    }
}

impl Add for CubeCoordinates {
    type Output = Self;

    fn add(self, rhs: Self) -> Self {
        CubeCoordinates {
            q: self.q + rhs.q,
            r: self.r + rhs.r,
            s: self.s + rhs.s,
        }
    }
}

impl ToString for CubeCoordinates {
    fn to_string(&self) -> String {
        format!("({},{},{})", self.q, self.r, self.s)
    }
}
