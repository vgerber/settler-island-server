use super::settlement_location::SettlementLocationId;

pub type RoadLocationId = String;

#[derive(Debug, Clone)]
pub struct PlayerRoad {
    player_id: usize,
}

#[derive(Debug, Clone)]
pub struct RoadLocation {
    id: RoadLocationId,
    player_road: Option<PlayerRoad>,
    settlement_a_id: String,
    settlement_b_id: String,
}

impl PlayerRoad {
    pub fn from(player_id: usize) -> Self {
        PlayerRoad {
            player_id: player_id,
        }
    }

    pub fn get_player_id(&self) -> &usize {
        &self.player_id
    }
}

impl RoadLocation {
    pub fn from(
        settlement_a_id: SettlementLocationId,
        settlement_b_id: SettlementLocationId,
    ) -> Self {
        RoadLocation {
            id: format!(
                "({})-({})",
                settlement_a_id.clone(),
                settlement_b_id.clone()
            ),
            player_road: None,
            settlement_a_id: settlement_a_id,
            settlement_b_id: settlement_b_id,
        }
    }

    pub fn has_road(&self) -> bool {
        self.player_road.is_some()
    }

    pub fn build_road(&mut self, road: PlayerRoad) -> Result<(), String> {
        if self.has_road() {
            return Err(format!("Road is already built {:?}", self.player_road));
        }

        self.player_road = Some(road);
        Ok(())
    }

    pub fn get_id(&self) -> &SettlementLocationId {
        &self.id
    }

    pub fn get_settlement_a_id(&self) -> &String {
        &self.settlement_a_id
    }

    pub fn get_settlement_b_id(&self) -> &String {
        &self.settlement_b_id
    }

    pub fn get_player_road(&self) -> &Option<PlayerRoad> {
        &self.player_road
    }
}
