use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

use crate::board::{CornerId, EdgeId, TileId};
use crate::game::{DevelopmentCard, Seat};
use crate::phase::Phase;
use crate::resource::{Resource, ResourceCounts};

/// What happened; random outcomes (dice, stolen card, drawn card) are events so a record replays without the seed.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "type")]
pub enum Event {
    SettlementPlaced {
        seat: Seat,
        corner: CornerId,
    },
    RoadPlaced {
        seat: Seat,
        edge: EdgeId,
    },
    CityBuilt {
        seat: Seat,
        corner: CornerId,
    },
    DiceRolled {
        seat: Seat,
        first: u8,
        second: u8,
    },
    ResourcesProduced {
        seat: Seat,
        resources: ResourceCounts,
    },
    ResourcesPaid {
        seat: Seat,
        resources: ResourceCounts,
    },
    RobberMoved {
        seat: Seat,
        tile: TileId,
    },
    CardsDiscarded {
        seat: Seat,
        resources: ResourceCounts,
    },
    ResourceStolen {
        thief: Seat,
        victim: Seat,
        resource: Option<Resource>,
    },
    BankTraded {
        seat: Seat,
        gave: ResourceCounts,
        received: ResourceCounts,
    },
    TradeOffered {
        seat: Seat,
        give: ResourceCounts,
        receive: ResourceCounts,
        to: Option<Seat>,
    },
    TradeAnswered {
        seat: Seat,
        accepted: bool,
    },
    TradeCompleted {
        seat: Seat,
        with: Seat,
        gave: ResourceCounts,
        received: ResourceCounts,
    },
    TradeCancelled {
        seat: Seat,
    },
    DevelopmentCardBought {
        seat: Seat,
        card: Option<DevelopmentCard>,
    },
    DevelopmentCardPlayed {
        seat: Seat,
        card: DevelopmentCard,
    },
    MonopolyTaken {
        seat: Seat,
        resource: Resource,
        amount: u8,
    },
    YearOfPlentyTaken {
        seat: Seat,
        resources: ResourceCounts,
    },
    LongestRoadChanged {
        holder: Option<Seat>,
        length: u8,
    },
    LargestArmyChanged {
        holder: Option<Seat>,
        knights: u8,
    },
    TurnEnded {
        seat: Seat,
    },
    TurnStarted {
        seat: Seat,
    },
    PhaseChanged {
        phase: Phase,
    },
    GameWon {
        seat: Seat,
        points: u8,
    },
}

impl Event {
    /// The event as `viewer` may see it (`None` is a spectator): stolen resources and bought cards are hidden from
    /// everyone not involved.
    pub fn visible_to(&self, viewer: Option<Seat>) -> Event {
        match self {
            Event::ResourceStolen { thief, victim, .. }
                if viewer != Some(*thief) && viewer != Some(*victim) =>
            {
                Event::ResourceStolen {
                    thief: *thief,
                    victim: *victim,
                    resource: None,
                }
            }
            Event::DevelopmentCardBought { seat, .. } if viewer != Some(*seat) => {
                Event::DevelopmentCardBought {
                    seat: *seat,
                    card: None,
                }
            }
            other => other.clone(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stolen_resource_is_visible_only_to_thief_and_victim() {
        let stolen = Event::ResourceStolen {
            thief: 0,
            victim: 2,
            resource: Some(Resource::Ore),
        };
        let hidden = Event::ResourceStolen {
            thief: 0,
            victim: 2,
            resource: None,
        };

        assert_eq!(stolen.visible_to(Some(0)), stolen);
        assert_eq!(stolen.visible_to(Some(2)), stolen);
        assert_eq!(stolen.visible_to(Some(1)), hidden);
        assert_eq!(stolen.visible_to(None), hidden);
    }

    #[test]
    fn bought_card_is_visible_only_to_the_buyer() {
        let bought = Event::DevelopmentCardBought {
            seat: 1,
            card: Some(DevelopmentCard::Knight),
        };

        assert_eq!(bought.visible_to(Some(1)), bought);
        assert_eq!(
            bought.visible_to(Some(0)),
            Event::DevelopmentCardBought {
                seat: 1,
                card: None
            }
        );
    }
}
