use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

use crate::board::{CornerId, TileId};
use crate::game::Seat;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "type")]
pub enum Phase {
    SetupSettlement {
        round: u8,
    },
    SetupRoad {
        round: u8,
        settlement: CornerId,
    },
    Roll,
    Main,
    /// Seats that still have to discard and how many cards each (step 2d).
    Discard {
        remaining: Vec<(Seat, u8)>,
    },
    /// After a 7 or a knight.
    MoveRobber {
        then_steal: bool,
    },
    /// Step 2d.
    Steal {
        tile: TileId,
    },
    /// Step 2b.
    RoadBuilding {
        roads_left: u8,
    },
    /// A player trade is open (step 2a).
    TradeOffered,
    Finished {
        winner: Seat,
    },
}
