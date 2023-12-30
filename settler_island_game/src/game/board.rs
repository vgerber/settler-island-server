use std::{any, cell::RefCell, sync::Arc};

use rand::{
    distributions::{Distribution, Standard},
    rngs::ThreadRng,
    Rng,
};

use self::{
    hexagon::{hexagon_map::HexagonMap, hexagon_tile::HexagonTile},
    location::{
        dice_chip_location::DiceChipLocation, robber_location::RobberLocation,
        settlement_map::SettlementMap,
    },
    resource::base_resource::ResourcedId,
};

use super::state::states::development_card::DevelopmentCard;

pub mod generator;
pub mod hexagon;
pub mod location;
pub mod resource;
pub mod trade_contract;

pub struct DoubleDiceRoll {
    dice_a: u8,
    dice_b: u8,
}

impl DoubleDiceRoll {
    pub fn get_total(&self) -> u8 {
        self.dice_a + self.dice_b
    }

    pub fn get_a(&self) -> &u8 {
        &self.dice_a
    }

    pub fn get_b(&self) -> &u8 {
        &self.dice_b
    }
}

impl Distribution<DoubleDiceRoll> for Standard {
    fn sample<R: Rng + ?Sized>(&self, rng: &mut R) -> DoubleDiceRoll {
        DoubleDiceRoll {
            dice_a: rng.gen_range(1..=6),
            dice_b: rng.gen_range(1..=6),
        }
    }
}

pub struct GameBoard {
    rng: ThreadRng,
    tile_map: HexagonMap,
    settlement_map: SettlementMap,
    dice_chips: Vec<DiceChipLocation>,
    robber: RobberLocation,
    board_resources: Vec<ResourcedId>,
    development_cards: Vec<DevelopmentCard>,
}

impl GameBoard {
    pub fn from(
        tile_map: HexagonMap,
        settlement_map: SettlementMap,
        dice_chips: Vec<DiceChipLocation>,
        robber_location: RobberLocation,
        board_resources: Vec<ResourcedId>,
        development_cards: Vec<DevelopmentCard>,
    ) -> Self {
        GameBoard {
            rng: rand::thread_rng(),
            tile_map: tile_map,
            settlement_map: settlement_map,
            dice_chips: dice_chips,
            robber: robber_location,
            board_resources: board_resources,
            development_cards: development_cards,
        }
    }

    pub fn get_tile_map(&self) -> &HexagonMap {
        &self.tile_map
    }

    pub fn get_settlement_map(&self) -> &SettlementMap {
        &self.settlement_map
    }

    pub fn get_settlement_map_mut(&mut self) -> &mut SettlementMap {
        &mut self.settlement_map
    }

    pub fn roll_dice(&mut self) -> DoubleDiceRoll {
        self.rng.gen()
    }

    pub fn get_dice_chips_by_number(&self, number: &u8) -> Vec<&DiceChipLocation> {
        self.dice_chips
            .iter()
            .filter(|&chip| chip.get_dice_value() == number)
            .collect()
    }

    pub fn get_tiles_by_dice_value(&self, number: &u8) -> Vec<&RefCell<HexagonTile>> {
        self.get_dice_chips_by_number(number)
            .into_iter()
            .filter_map(|chip| self.tile_map.get_tile(chip.get_assigned_tile()))
            .collect()
    }

    pub fn get_robber(&self) -> &RobberLocation {
        &self.robber
    }

    pub fn get_development_cards_left(&self) -> usize {
        self.development_cards.len()
    }

    pub fn draw_development_card(&mut self) -> Option<DevelopmentCard> {
        self.development_cards.pop()
    }
}
