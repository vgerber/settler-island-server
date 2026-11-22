use std::collections::VecDeque;

use settler_island_game::{
    Board, BuildingKind, CornerId, EdgeId, PlayerView, Port, Resource, Seat, TileId,
};

/// Pips are summed across corners; one new resource is worth about a mid-sized number.
const DIVERSITY_BONUS: f64 = 2.5;
const GENERIC_PORT_BONUS: f64 = 1.0;
const SPECIFIC_PORT_BONUS: f64 = 2.5;
/// A specific port pays off once its resource is produced at least this often.
const SPECIFIC_PORT_MIN_PIPS: u32 = 5;
/// Each further road on the way to a site halves its worth.
const ROAD_DECAY: f64 = 0.5;
const ROAD_SEARCH_DEPTH: u32 = 3;
/// A tile with an own building is never the robber's best choice.
const OWN_TILE_PENALTY: f64 = 1000.0;

/// Pips per resource, indexed like `Resource::ALL`.
pub(crate) type Production = [u32; 5];

pub(crate) fn slot(resource: Resource) -> usize {
    Resource::ALL
        .iter()
        .position(|candidate| *candidate == resource)
        .unwrap_or(0)
}

/// How many of the 36 dice outcomes roll this number.
pub(crate) fn pips(number: u8) -> u32 {
    match number {
        2 | 12 => 1,
        3 | 11 => 2,
        4 | 10 => 3,
        5 | 9 => 4,
        6 | 8 => 5,
        _ => 0,
    }
}

pub(crate) fn tile_pips(board: &Board, tile: TileId) -> u32 {
    board
        .tile(tile)
        .and_then(|tile| tile.number)
        .map_or(0, pips)
}

pub(crate) fn corner_production(board: &Board, corner: CornerId) -> Production {
    let mut production = [0; 5];
    let Some(location) = board.corner(corner) else {
        return production;
    };
    for tile in location.tiles.iter().filter_map(|tile| board.tile(*tile)) {
        if let (Some(resource), Some(number)) = (tile.resource, tile.number) {
            production[slot(resource)] += pips(number);
        }
    }
    production
}

/// Cities count twice.
pub(crate) fn seat_production(board: &Board, seat: Seat) -> Production {
    let mut total = [0; 5];
    for corner in board.corner_ids() {
        let Some(building) = board
            .building(corner)
            .filter(|building| building.seat == seat)
        else {
            continue;
        };
        let factor = if building.kind == BuildingKind::City {
            2
        } else {
            1
        };
        for (sum, pips) in total.iter_mut().zip(corner_production(board, corner)) {
            *sum += pips * factor;
        }
    }
    total
}

/// Pip sum, plus a bonus per resource the seat does not produce yet, plus the port's worth.
pub(crate) fn site_value(board: &Board, corner: CornerId, existing: &Production) -> f64 {
    let production = corner_production(board, corner);
    let pip_sum: u32 = production.iter().sum();
    let new_resources = production
        .iter()
        .zip(existing)
        .filter(|(added, held)| **added > 0 && **held == 0)
        .count();
    let port = board
        .corner(corner)
        .and_then(|location| location.port)
        .map_or(0.0, |port| port_value(port, &production, existing));
    f64::from(pip_sum) + DIVERSITY_BONUS * new_resources as f64 + port
}

fn port_value(port: Port, production: &Production, existing: &Production) -> f64 {
    match port {
        Port::Generic => GENERIC_PORT_BONUS,
        Port::Specific(resource) => {
            let produced = production[slot(resource)] + existing[slot(resource)];
            if produced >= SPECIFIC_PORT_MIN_PIPS {
                SPECIFIC_PORT_BONUS
            } else {
                0.0
            }
        }
    }
}

/// Empty and no building on a neighbouring corner (the distance rule).
pub(crate) fn is_free_site(board: &Board, corner: CornerId) -> bool {
    let Some(location) = board.corner(corner) else {
        return false;
    };
    board.building(corner).is_none()
        && location
            .neighbors
            .iter()
            .all(|neighbor| board.building(*neighbor).is_none())
}

fn in_network(board: &Board, seat: Seat, corner: CornerId) -> bool {
    let Some(location) = board.corner(corner) else {
        return false;
    };
    board
        .building(corner)
        .is_some_and(|building| building.seat == seat)
        || location
            .edges
            .iter()
            .any(|edge| board.road(*edge) == Some(seat))
}

/// A free site touching an own road: a settlement can go there once it is paid.
pub(crate) fn has_open_site(board: &Board, seat: Seat) -> bool {
    board.corner_ids().any(|corner| {
        is_free_site(board, corner)
            && board.corner(corner).is_some_and(|location| {
                location
                    .edges
                    .iter()
                    .any(|edge| board.road(*edge) == Some(seat))
            })
    })
}

/// Worth of the best free site reachable from the new end of `edge`, halved per extra road.
pub(crate) fn road_value(board: &Board, seat: Seat, edge: EdgeId) -> f64 {
    let Some(location) = board.edge(edge) else {
        return 0.0;
    };
    let mut starts: Vec<CornerId> = location
        .corners
        .iter()
        .copied()
        .filter(|corner| !in_network(board, seat, *corner))
        .collect();
    if starts.is_empty() {
        starts = location.corners.to_vec();
    }
    let existing = seat_production(board, seat);
    reachable_sites(board, seat, edge, &starts)
        .into_iter()
        .map(|(corner, distance)| {
            site_value(board, corner, &existing) * ROAD_DECAY.powi(distance as i32)
        })
        .fold(0.0, f64::max)
}

/// Breadth-first over empty edges, never through another seat's building.
fn reachable_sites(
    board: &Board,
    seat: Seat,
    built: EdgeId,
    starts: &[CornerId],
) -> Vec<(CornerId, u32)> {
    let mut distance = vec![None; board.corners().len()];
    let mut queue = VecDeque::new();
    for start in starts {
        distance[usize::from(start.0)] = Some(0);
        queue.push_back(*start);
    }
    let mut sites = Vec::new();
    while let Some(corner) = queue.pop_front() {
        let here = distance[usize::from(corner.0)].unwrap_or(0);
        if is_free_site(board, corner) {
            sites.push((corner, here));
        }
        let blocked = board
            .building(corner)
            .is_some_and(|building| building.seat != seat);
        if blocked || here >= ROAD_SEARCH_DEPTH {
            continue;
        }
        for next in open_neighbors(board, corner, built) {
            let slot = &mut distance[usize::from(next.0)];
            if slot.is_none() {
                *slot = Some(here + 1);
                queue.push_back(next);
            }
        }
    }
    sites
}

fn open_neighbors(board: &Board, corner: CornerId, built: EdgeId) -> Vec<CornerId> {
    let Some(location) = board.corner(corner) else {
        return Vec::new();
    };
    location
        .edges
        .iter()
        .filter(|edge| **edge != built && board.road(**edge).is_none())
        .filter_map(|edge| board.edge(*edge))
        .filter_map(|edge| edge.corners.iter().copied().find(|end| *end != corner))
        .collect()
}

/// Whether the robber stands on a numbered tile next to an own building.
pub(crate) fn robber_blocks(board: &Board, seat: Seat) -> bool {
    let robber = board.robber();
    tile_pips(board, robber) > 0 && tile_seats(board, robber).contains(&seat)
}

/// Seats with a building on the tile, one entry per building, cities twice.
fn tile_seats(board: &Board, tile: TileId) -> Vec<Seat> {
    let Some(location) = board.tile(tile) else {
        return Vec::new();
    };
    location
        .corners
        .iter()
        .filter_map(|corner| board.building(*corner))
        .flat_map(|building| {
            let count = if building.kind == BuildingKind::City {
                2
            } else {
                1
            };
            std::iter::repeat_n(building.seat, count)
        })
        .collect()
}

/// Lost pips on the tile, weighted by the square of each victim's points so the leader is hit.
pub(crate) fn robber_value(view: &PlayerView, seat: Seat, tile: TileId) -> f64 {
    let seats = tile_seats(&view.board, tile);
    if seats.contains(&seat) {
        return -OWN_TILE_PENALTY;
    }
    let pips = f64::from(tile_pips(&view.board, tile));
    seats
        .iter()
        .filter_map(|victim| view.players.get(usize::from(*victim)))
        .map(|victim| {
            let points = f64::from(victim.points) + 1.0;
            let steal = if victim.resource_count > 0 { 1.0 } else { 0.0 };
            (pips + steal) * points * points
        })
        .sum()
}
