use std::collections::HashMap;

use super::{
    board::resource::player_resources::PlayerResources, color::Color,
    state::states::development_card::DevelopmentCard,
};

pub type PlayerId = usize;
pub type DevelopmentCards = HashMap<String, usize>;

pub struct Player {
    id: PlayerId,
    user_id: Option<String>,
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
