use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

use crate::board::{CornerId, TileId};
use crate::game::{Seat, TradeOffer};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "type")]
pub enum Phase {
    SetupSettlement {
        round: SetupRound,
    },
    SetupRoad {
        round: SetupRound,
        settlement: CornerId,
    },
    Roll,
    Main,
    /// Seats that still have to discard, one entry per seat (step 2d).
    Discard {
        owed: Vec<OwedDiscard>,
    },
    /// After a 7 or a knight.
    MoveRobber {
        then_steal: bool,
        resume: Resume,
    },
    /// Step 2d.
    Steal {
        tile: TileId,
        resume: Resume,
    },
    /// Step 2b.
    RoadBuilding {
        roads_left: u8,
        resume: Resume,
    },
    /// A player trade is open (step 2a).
    TradeOffered {
        offer: TradeOffer,
    },
    Finished {
        winner: Seat,
    },
}

/// The first round places in seat order, the second in reverse order and yields resources.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub enum SetupRound {
    First,
    Second,
}

/// The turn phase an interruption returns to; a card played before the roll returns to `Roll`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub enum Resume {
    Roll,
    Main,
}

impl Resume {
    /// The resume point for an interruption that starts in `phase`.
    pub(crate) fn from_phase(phase: &Phase) -> Resume {
        match phase {
            Phase::Roll => Resume::Roll,
            _ => Resume::Main,
        }
    }

    pub(crate) fn phase(self) -> Phase {
        match self {
            Resume::Roll => Phase::Roll,
            Resume::Main => Phase::Main,
        }
    }
}

/// A seat that has to discard `cards` cards after a 7.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub struct OwedDiscard {
    pub seat: Seat,
    pub cards: u8,
}

impl Phase {
    /// How many cards `seat` still has to discard, if any.
    pub fn owed_discard(&self, seat: Seat) -> Option<u8> {
        let Phase::Discard { owed } = self else {
            return None;
        };
        owed.iter()
            .find(|entry| entry.seat == seat)
            .map(|entry| entry.cards)
    }

    /// The open player trade, which exists only in `TradeOffered`.
    pub fn trade_offer(&self) -> Option<&TradeOffer> {
        match self {
            Phase::TradeOffered { offer } => Some(offer),
            _ => None,
        }
    }
}
