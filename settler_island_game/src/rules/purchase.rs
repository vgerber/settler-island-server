use crate::resource::{Resource, ResourceCounts};

/// Everything a player can buy; the only place costs are defined.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Purchase {
    Road,
    Settlement,
    City,
    DevelopmentCard,
}

impl Purchase {
    pub const fn cost(self) -> ResourceCounts {
        match self {
            Purchase::Road => ResourceCounts::EMPTY
                .with(Resource::Clay, 1)
                .with(Resource::Wood, 1),
            Purchase::Settlement => ResourceCounts::EMPTY
                .with(Resource::Clay, 1)
                .with(Resource::Wood, 1)
                .with(Resource::Sheep, 1)
                .with(Resource::Wheat, 1),
            Purchase::City => ResourceCounts::EMPTY
                .with(Resource::Wheat, 2)
                .with(Resource::Ore, 3),
            Purchase::DevelopmentCard => ResourceCounts::EMPTY
                .with(Resource::Sheep, 1)
                .with(Resource::Wheat, 1)
                .with(Resource::Ore, 1),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn costs_match_the_rulebook() {
        assert_eq!(Purchase::Road.cost(), ResourceCounts::new([1, 1, 0, 0, 0]));
        assert_eq!(
            Purchase::Settlement.cost(),
            ResourceCounts::new([1, 1, 1, 1, 0])
        );
        assert_eq!(Purchase::City.cost(), ResourceCounts::new([0, 0, 0, 2, 3]));
        assert_eq!(
            Purchase::DevelopmentCard.cost(),
            ResourceCounts::new([0, 0, 1, 1, 1])
        );
    }
}
