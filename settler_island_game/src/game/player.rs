use std::collections::HashMap;

use super::{board::resource::player_resources::PlayerResources, color::Color};

pub type PlayerId = usize;
pub type DevelopmentCards = HashMap<String, usize>;

pub struct Player {
    id: PlayerId,
    #[expect(dead_code, reason = "read once the rules core is redesigned")]
    user_id: Option<String>,
    #[expect(dead_code, reason = "read once the rules core is redesigned")]
    color: Color,
    resources: PlayerResources,
    development_cards: DevelopmentCards,
}

impl Player {
    pub fn get_id(&self) -> &PlayerId {
        &self.id
    }

    pub fn get_resources(&self) -> &PlayerResources {
        &self.resources
    }

    pub fn get_resources_mut(&mut self) -> &mut PlayerResources {
        &mut self.resources
    }

    pub fn get_development_cards(&self) -> &DevelopmentCards {
        &self.development_cards
    }

    pub fn get_development_cards_mut(&mut self) -> &mut DevelopmentCards {
        &mut self.development_cards
    }
}
