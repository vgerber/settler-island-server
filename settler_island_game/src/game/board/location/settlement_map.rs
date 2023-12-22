use std::{collections::HashMap, rc::Rc};

use super::{
    road_location::{RoadLocation, RoadLocationId},
    settlement_location::{SettlementLocation, SettlementLocationId},
};

pub struct SettlementMap {
    settlements: HashMap<String, SettlementLocation>,
    roads: HashMap<String, RoadLocation>,
    settlement_connections: HashMap<String, Vec<String>>,
}

impl SettlementMap {
    pub fn new() -> Self {
        SettlementMap {
            settlements: HashMap::new(),
            roads: HashMap::new(),
            settlement_connections: HashMap::new(),
        }
    }

    pub fn has_road(&self, road_id: &RoadLocationId) -> bool {
        self.roads.contains_key(road_id)
    }

    pub fn get_road(&self, road_id: &RoadLocationId) -> Option<&RoadLocation> {
        self.roads.get(road_id)
    }

    pub fn get_road_mut(&mut self, road_id: &RoadLocationId) -> Option<&mut RoadLocation> {
        self.roads.get_mut(road_id)
    }

    pub fn has_settlement(&self, settlement_id: &SettlementLocationId) -> bool {
        self.settlements.contains_key(settlement_id)
    }

    pub fn get_settlement(
        &self,
        settlement_id: &SettlementLocationId,
    ) -> Option<&SettlementLocation> {
        self.settlements.get(settlement_id)
    }

    pub fn get_settlement_mut(
        &mut self,
        settlement_id: &SettlementLocationId,
    ) -> Option<&mut SettlementLocation> {
        self.settlements.get_mut(settlement_id)
    }

    pub fn add_road(&mut self, road: RoadLocation) -> Result<(), String> {
        if self.has_road(road.get_id()) {
            return Err(format!("Road \"{}\" is already in map", road.get_id()));
        }

        if !self.has_settlement(road.get_settlement_a_id()) {
            return Err(format!(
                "Settlement \"{}\" from road \"{}\" is not in map",
                road.get_settlement_a_id(),
                road.get_id()
            ));
        }

        if !self.has_settlement(road.get_settlement_b_id()) {
            return Err(format!(
                "Settlement \"{}\" from road \"{}\" is not in map",
                road.get_settlement_b_id(),
                road.get_id()
            ));
        }

        self.roads.insert(road.get_id().clone(), road.clone());
        match self
            .settlement_connections
            .get_mut(road.get_settlement_a_id())
        {
            Some(connections) => connections.push(road.get_id().clone()),
            None => {
                self.settlement_connections.insert(
                    road.get_settlement_a_id().clone(),
                    vec![road.get_id().clone()],
                );
                ()
            }
        }

        match self
            .settlement_connections
            .get_mut(road.get_settlement_b_id())
        {
            Some(connections) => connections.push(road.get_id().clone()),
            None => {
                self.settlement_connections.insert(
                    road.get_settlement_b_id().clone(),
                    vec![road.get_id().clone()],
                );
                ()
            }
        }

        Ok(())
    }

    pub fn add_settlement(&mut self, settlement: SettlementLocation) -> Result<(), String> {
        if self.has_settlement(settlement.get_id()) {
            return Err(format!(
                "Settlement \"{}\" is already in map",
                settlement.get_id()
            ));
        }

        self.settlements
            .insert(settlement.get_id().clone(), settlement);
        Ok(())
    }

    pub fn get_settlement_roads(&self, settlement_id: &String) -> Vec<&RoadLocation> {
        self.settlement_connections
            .get(settlement_id)
            .unwrap_or(&vec![])
            .iter()
            .filter_map(|road_id| self.roads.get(road_id))
            .collect()
    }

    pub fn get_neighbor_settlements(&self, settlement_id: &String) -> Vec<&SettlementLocation> {
        self.get_settlement_roads(settlement_id)
            .iter()
            .map(|road| {
                if road.get_settlement_a_id() == settlement_id {
                    self.settlements.get(road.get_settlement_b_id()).unwrap()
                } else {
                    self.settlements.get(road.get_settlement_a_id()).unwrap()
                }
            })
            .collect()
    }

    pub fn has_settlement_player_roads(&self, settlement_id: &String, player_id: usize) -> bool {
        self.get_settlement_roads(settlement_id)
            .into_iter()
            .any(|road| match road.get_player_road() {
                None => false,
                Some(player_road) => *player_road.get_player_id() == player_id,
            })
    }

    pub fn get_player_settlements(&self, player_id: &usize) -> Vec<&SettlementLocation> {
        self.settlements
            .values()
            .into_iter()
            .filter(|settlement| settlement.is_owner(player_id))
            .collect()
    }

    pub fn any_settlement_occupied(settlements: &Vec<&SettlementLocation>) -> bool {
        settlements
            .iter()
            .any(|location| location.get_settlement().is_some())
    }
}
