use serde::{Deserialize, Serialize};

use crate::game::board::hexagon::cube_coordinates::CubeCoordinates;

use super::seaport_location::SeaportLocation;

pub type SettlementLocationId = String;

#[derive(Debug, Clone, Copy, Deserialize, Serialize)]
pub enum SettlementType {
    Village,
    City,
}

#[derive(Debug, Clone)]
pub struct PlayerSettlement {
    player_id: usize,
    settlement_type: SettlementType,
}

#[derive(Clone)]
pub struct SettlementLocation {
    id: SettlementLocationId,
    neighbor_tiles: Vec<CubeCoordinates>,
    settlement: Option<PlayerSettlement>,
    seaport: Option<SeaportLocation>,
}

impl SettlementLocation {
    pub fn from(neighbor_tiles: Vec<CubeCoordinates>, seaport: Option<SeaportLocation>) -> Self {
        SettlementLocation {
            id: SettlementLocation::id_from_tiles(&neighbor_tiles),
            neighbor_tiles: neighbor_tiles,
            settlement: None,
            seaport: seaport,
        }
    }

    fn id_from_tiles(tiles: &Vec<CubeCoordinates>) -> SettlementLocationId {
        let min = CubeCoordinates::min(tiles);
        let max = CubeCoordinates::max(tiles);
        format!("{}-{}", min.to_string(), max.to_string())
    }

    pub fn get_id(&self) -> &SettlementLocationId {
        &self.id
    }

    pub fn get_settlement(&self) -> &Option<PlayerSettlement> {
        &self.settlement
    }

    pub fn destroy_settlement(&mut self) {
        self.settlement = None
    }

    pub fn build_settlement(
        &mut self,
        settlement_type: SettlementType,
        player_id: &usize,
    ) -> Result<(), String> {
        match settlement_type {
            SettlementType::Village => self.build_village(player_id),
            SettlementType::City => self.build_city(player_id),
        }
    }

    fn build_village(&mut self, player_id: &usize) -> Result<(), String> {
        if self.settlement.is_some() {
            return Err(format!(
                "{} cannot claim the location. Settlement is already assigned to {}",
                player_id,
                self.settlement.as_ref().unwrap().get_player_id()
            ));
        }

        match self.settlement {
            Some(_) => Err(format!(
                "{} cannot claim settlement. Settlement has already a {:?}",
                player_id, self.settlement
            )),
            None => {
                self.settlement = Some(PlayerSettlement::from(*player_id));
                Ok(())
            }
        }
    }

    fn build_city(&mut self, player_id: &usize) -> Result<(), String> {
        if !self.is_owner(player_id) {
            return Err(format!(
                "Cities can only be placed in \"{}\" owned settlements",
                player_id,
            ));
        }

        match self.settlement.as_mut() {
            None => return Err("Cities can only built from villages".to_string()),
            Some(settlement) => match settlement.get_settlement_type() {
                SettlementType::City => return Err("Settlement is a city already".to_string()),
                SettlementType::Village => settlement.build_city(),
            },
        }
    }

    pub fn is_owner(&self, player_id: &usize) -> bool {
        match self.settlement.as_ref() {
            Some(settlement) => settlement.get_player_id() == player_id,
            None => false,
        }
    }
}

impl PlayerSettlement {
    pub fn from(player_id: usize) -> Self {
        PlayerSettlement {
            player_id: player_id,
            settlement_type: SettlementType::Village,
        }
    }

    pub fn get_player_id(&self) -> &usize {
        &self.player_id
    }

    pub fn get_settlement_type(&self) -> &SettlementType {
        &self.settlement_type
    }

    pub fn build_city(&mut self) -> Result<(), String> {
        match self.settlement_type {
            SettlementType::Village => {
                self.settlement_type = SettlementType::City;
                Ok(())
            }
            SettlementType::City => Err("Settlement is a city already".to_string()),
        }
    }
}
