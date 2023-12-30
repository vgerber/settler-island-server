use std::{iter::repeat, rc::Rc, sync::Arc};

use rand::{seq::SliceRandom, thread_rng};

use crate::game::{
    board::{
        hexagon::{
            cube_coordinates::CubeCoordinates,
            hexagon_map::HexagonMap,
            hexagon_tile::{HexagonTile, TileType},
        },
        location::{
            dice_chip_location::DiceChipLocation,
            road_location::RoadLocation,
            robber_location::RobberLocation,
            seaport_location::SeaportLocation,
            settlement_location::{SettlementLocation, SettlementLocationId},
            settlement_map::SettlementMap,
        },
        resource::base_resource::{
            ResourcedId, RESOURCE_CLAY, RESOURCE_ORE, RESOURCE_SHEEP, RESOURCE_WHEAT, RESOURCE_WOOD,
        },
        trade_contract::AcceptsNAnyTradeContract,
        GameBoard,
    },
    state::states::development_card::{
        DevelopmentCard, DEVELOPMENT_CARD_INVENTION, DEVELOPMENT_CARD_KNIGHT,
        DEVELOPMENT_CARD_MONOPOLY, DEVELOPMENT_CARD_STREET_CONSTRUCTION,
        DEVELOPMENT_CARD_VICTORY_POINT,
    },
};

pub fn generate_board() -> Result<GameBoard, String> {
    let (mut tile_map, board_resources) = match generate_hexagon_map() {
        Ok(values) => values,
        Err(err) => return Err(err),
    };
    let dice_chips = match generate_dice_chips(&tile_map) {
        Ok(chips) => chips,
        Err(err) => return Err(err),
    };
    let robber_location = get_robber_location();
    let mut settlement_map = match generate_settlement_map(&mut tile_map) {
        Ok(map) => map,
        Err(err) => return Err(err),
    };
    if let Err(_) = generate_seaports(&mut settlement_map, &tile_map) {
        return Err(format!("Failed to generate seaports"));
    }
    let development_cards = match generate_development_cards() {
        Ok(cards) => cards,
        Err(err) => return Err(err),
    };

    Ok(GameBoard::from(
        tile_map,
        settlement_map,
        dice_chips,
        robber_location,
        board_resources,
        development_cards,
    ))
}

fn generate_hexagon_map() -> Result<(HexagonMap, Vec<ResourcedId>), String> {
    let mut hexagon_map = HexagonMap::new();
    let board_resources: Vec<ResourcedId> = vec![
        RESOURCE_CLAY.to_string(),
        RESOURCE_WOOD.to_string(),
        RESOURCE_ORE.to_string(),
        RESOURCE_SHEEP.to_string(),
        RESOURCE_WHEAT.to_string(),
    ];

    // convert resource count to repeated list of indices
    // shuffle this list to get a random resource distribution
    let board_resources_counts: Vec<(usize, usize)> =
        vec![3, 4, 3, 4, 4].into_iter().enumerate().collect();
    let mut resource_list: Vec<usize> = board_resources_counts
        .into_iter()
        .flat_map(|(index, resource_count)| repeat(index).take(resource_count))
        .collect::<Vec<usize>>();
    resource_list.shuffle(&mut thread_rng());

    let board_size = 3;
    for q in -(board_size - 1)..board_size {
        for r in -(board_size - 1)..board_size {
            let coordinates = CubeCoordinates::from_qr(q, r);
            // sea tiles are not stored
            if !is_tile_in_map(&coordinates, board_size) {
                continue;
            }

            if coordinates.q == 0 && coordinates.r == 0 && coordinates.s == 0 {
                if let Err(err) =
                    hexagon_map.add_tile(HexagonTile::from(coordinates, TileType::FillerTile()))
                {
                    return Err(err);
                }
            } else {
                let tile_resource = board_resources
                    [resource_list.pop().expect("Not enough resources generated")]
                .clone();

                if let Err(err) = hexagon_map.add_tile(HexagonTile::from(
                    coordinates,
                    TileType::ResourceTile(tile_resource),
                )) {
                    return Err(err);
                }
            }
        }
    }

    Ok((hexagon_map, board_resources))
}

fn generate_dice_chips(hexagon_map: &HexagonMap) -> Result<Vec<DiceChipLocation>, String> {
    let mut dice_chip_values = vec![1, 2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 12];
    dice_chip_values.shuffle(&mut thread_rng());

    let tiles = hexagon_map.get_tiles();
    if dice_chip_values.len() != (tiles.len() - 1) {
        return Err("Dice chip and resource tile count do not match".to_string());
    }

    let mut dice_chips: Vec<DiceChipLocation> = Vec::new();

    for tile in tiles {
        match tile.borrow().get_type() {
            TileType::ResourceTile(_) => dice_chips.push(DiceChipLocation::from(
                dice_chip_values
                    .pop()
                    .expect("Popped to many dice chip values"),
                *tile.borrow().get_coordinates(),
            )),
            _ => continue,
        }
    }

    Ok(dice_chips)
}

fn generate_settlement_map(hexagon_map: &mut HexagonMap) -> Result<SettlementMap, String> {
    let mut settlement_map = SettlementMap::new();

    for map_tile in hexagon_map.get_tiles() {
        let mut tile = map_tile.borrow_mut();
        let tile_neighbors = tile.get_coordinates().get_neighbor_coordinates();
        let mut corner_settlements = Vec::<SettlementLocationId>::new();
        for tile_neighbor_index in 0..tile_neighbors.len() {
            let tile_neighbor_1 = tile_neighbors[tile_neighbor_index];
            let tile_neighbor_2 = tile_neighbors[(tile_neighbor_index + 1) % tile_neighbors.len()];
            let neighbor_tiles = vec![*tile.get_coordinates(), tile_neighbor_1, tile_neighbor_2];

            let mut seaport: Option<SeaportLocation> = None;
            if is_any_sea_tile(&neighbor_tiles, 3) {
                // TODO generate seaport
                seaport = Some(SeaportLocation::new(Rc::new(
                    AcceptsNAnyTradeContract::new(1, 3),
                )));
            }

            let settlement = SettlementLocation::from(neighbor_tiles, seaport);

            if settlement_map.get_settlement(settlement.get_id()).is_none() {
                if let Err(err) = settlement_map.add_settlement(settlement.clone()) {
                    return Err(err);
                }
            }

            corner_settlements.push(settlement.get_id().clone());
            tile.add_corner_settlement(settlement.get_id().clone());
        }

        for corner_location_index in 0..corner_settlements.len() {
            let settlement_a_id = &corner_settlements[corner_location_index];
            let settlement_b_id =
                &corner_settlements[(corner_location_index + 1) % corner_settlements.len()];
            let road_a = RoadLocation::from(settlement_a_id.clone(), settlement_b_id.clone());
            let road_b = RoadLocation::from(settlement_b_id.clone(), settlement_a_id.clone());
            if settlement_map.has_road(road_a.get_id()) || settlement_map.has_road(road_b.get_id())
            {
                continue;
            }
            if let Err(err) = settlement_map.add_road(road_a) {
                return Err(err);
            }
        }
    }

    Ok(settlement_map)
}

fn get_robber_location() -> RobberLocation {
    RobberLocation::from(CubeCoordinates::from(0, 0, 0))
}

fn is_tile_in_map(coordinates: &CubeCoordinates, board_size: i32) -> bool {
    coordinates.q.abs() < board_size
        && coordinates.r.abs() < board_size
        && coordinates.s.abs() < board_size
}

fn is_any_sea_tile(coordinates: &Vec<CubeCoordinates>, board_size: i32) -> bool {
    coordinates
        .iter()
        .any(|coordinates| is_tile_in_map(coordinates, board_size))
}

fn generate_development_cards() -> Result<Vec<DevelopmentCard>, String> {
    let mut card_ids: Vec<DevelopmentCard> = vec![
        DEVELOPMENT_CARD_KNIGHT,
        DEVELOPMENT_CARD_INVENTION,
        DEVELOPMENT_CARD_STREET_CONSTRUCTION,
        DEVELOPMENT_CARD_MONOPOLY,
        DEVELOPMENT_CARD_VICTORY_POINT,
    ];
    let mut card_frequencies: Vec<usize> = vec![14, 2, 2, 2, 5];
    let mut cards: Vec<DevelopmentCard> = card_frequencies
        .into_iter()
        .enumerate()
        .flat_map(|(index, frequency)| repeat(index).take(frequency))
        .map(|card_index| card_ids[card_index])
        .collect();
    cards.shuffle(&mut thread_rng());
    Ok(cards)
}

fn generate_seaports(settlement_map: &mut SettlementMap, tile_map: &HexagonMap) -> Result<(), ()> {
    Err(())
}
