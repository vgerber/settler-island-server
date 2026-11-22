use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

use crate::board::{CornerId, EdgeId, TileId};
use crate::game::Seat;
use crate::resource::{Resource, ResourceCounts};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "type")]
pub enum Action {
    /// Setup phase.
    PlaceSettlement {
        corner: CornerId,
    },
    /// Setup phase.
    PlaceRoad {
        edge: EdgeId,
    },
    RollDice,
    EndTurn,
    BuildRoad {
        edge: EdgeId,
    },
    BuildSettlement {
        corner: CornerId,
    },
    BuildCity {
        corner: CornerId,
    },
    MoveRobber {
        tile: TileId,
    },
    Steal {
        victim: Seat,
    },
    Discard {
        resources: ResourceCounts,
    },
    /// The rate comes from the seat's ports, 4:1 by default.
    BankTrade {
        give: Resource,
        receive: Resource,
    },
    OfferTrade {
        give: ResourceCounts,
        receive: ResourceCounts,
        to: Option<Seat>,
    },
    AcceptTrade,
    RejectTrade,
    ConfirmTrade {
        with: Seat,
    },
    CancelTrade,
    BuyDevelopmentCard,
    PlayKnight,
    PlayRoadBuilding,
    PlayYearOfPlenty {
        first: Resource,
        second: Resource,
    },
    PlayMonopoly {
        resource: Resource,
    },
}
