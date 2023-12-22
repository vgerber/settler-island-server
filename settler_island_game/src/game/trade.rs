use std::collections::HashMap;

use super::{board::resource::player_resources::ResourceCollection, player::PlayerId};

pub struct TradeOffer {
    pub creator: PlayerId,
    pub resource_offer: ResourceCollection,
    pub resource_receive: ResourceCollection,
    pub players_accepted: HashMap<PlayerId, bool>,
}

impl TradeOffer {
    pub fn new(
        creator: PlayerId,
        resource_offer: ResourceCollection,
        resource_receive: ResourceCollection,
        players: Vec<PlayerId>,
    ) -> Self {
        let mut players_accepted = HashMap::<PlayerId, bool>::new();
        players.into_iter().for_each(|player_id| {
            if creator == player_id {
                panic!("Cannot add creator as trade acceptee");
            }
            players_accepted.insert(player_id, false);
        });

        TradeOffer {
            creator: creator,
            resource_offer: resource_offer,
            resource_receive: resource_receive,
            players_accepted: players_accepted,
        }
    }
}
