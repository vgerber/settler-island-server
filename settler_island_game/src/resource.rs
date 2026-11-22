use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

use crate::error::GameError;

#[derive(
    Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, JsonSchema,
)]
pub enum Resource {
    Clay,
    Wood,
    Sheep,
    Wheat,
    Ore,
}

impl Resource {
    pub const ALL: [Resource; 5] = [
        Resource::Clay,
        Resource::Wood,
        Resource::Sheep,
        Resource::Wheat,
        Resource::Ore,
    ];

    fn index(self) -> usize {
        match self {
            Resource::Clay => 0,
            Resource::Wood => 1,
            Resource::Sheep => 2,
            Resource::Wheat => 3,
            Resource::Ore => 4,
        }
    }
}

/// Counts per resource, in the order of `Resource::ALL`.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize, JsonSchema)]
pub struct ResourceCounts([u8; 5]);

impl ResourceCounts {
    pub const fn new(counts: [u8; 5]) -> Self {
        ResourceCounts(counts)
    }

    pub fn single(resource: Resource, amount: u8) -> Self {
        let mut counts = ResourceCounts::default();
        counts.set(resource, amount);
        counts
    }

    pub fn get(&self, resource: Resource) -> u8 {
        self.0[resource.index()]
    }

    pub fn set(&mut self, resource: Resource, amount: u8) {
        self.0[resource.index()] = amount;
    }

    pub fn total(&self) -> u32 {
        self.0.iter().map(|count| u32::from(*count)).sum()
    }

    pub fn is_empty(&self) -> bool {
        self.total() == 0
    }

    pub fn contains(&self, other: &ResourceCounts) -> bool {
        Resource::ALL
            .iter()
            .all(|resource| self.get(*resource) >= other.get(*resource))
    }

    pub fn checked_add(&self, other: &ResourceCounts) -> Option<ResourceCounts> {
        let mut sum = *self;
        for resource in Resource::ALL {
            sum.set(
                resource,
                self.get(resource).checked_add(other.get(resource))?,
            );
        }
        Some(sum)
    }

    /// Removes all of `other` or nothing.
    pub fn try_remove(&mut self, other: &ResourceCounts) -> Result<(), GameError> {
        if !self.contains(other) {
            return Err(GameError::NotEnoughResources);
        }
        for resource in Resource::ALL {
            self.set(resource, self.get(resource) - other.get(resource));
        }
        Ok(())
    }

    /// Adds `other`; saturates, which cannot happen in a game because only 95 cards exist.
    pub(crate) fn deposit(&mut self, other: &ResourceCounts) {
        for resource in Resource::ALL {
            self.set(
                resource,
                self.get(resource).saturating_add(other.get(resource)),
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn try_remove_is_all_or_nothing() {
        let mut hand = ResourceCounts::new([1, 1, 0, 0, 0]);
        let cost = ResourceCounts::new([1, 1, 1, 0, 0]);

        assert_eq!(hand.try_remove(&cost), Err(GameError::NotEnoughResources));
        assert_eq!(hand, ResourceCounts::new([1, 1, 0, 0, 0]));

        hand.set(Resource::Sheep, 2);
        assert_eq!(hand.try_remove(&cost), Ok(()));
        assert_eq!(hand, ResourceCounts::new([0, 0, 1, 0, 0]));
    }

    #[test]
    fn checked_add_rejects_overflow_in_any_resource() {
        let full_ore = ResourceCounts::single(Resource::Ore, u8::MAX);

        assert_eq!(
            full_ore.checked_add(&ResourceCounts::single(Resource::Ore, 1)),
            None
        );
        assert_eq!(
            full_ore.checked_add(&ResourceCounts::single(Resource::Clay, 1)),
            Some(ResourceCounts::new([1, 0, 0, 0, u8::MAX]))
        );
    }
}
