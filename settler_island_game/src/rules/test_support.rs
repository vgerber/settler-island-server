use crate::board::{Building, BuildingKind, CornerId, EdgeId, TileId};
use crate::game::{Game, GameSettings, Seat};
use crate::phase::Phase;
use crate::resource::{Resource, ResourceCounts};

pub(crate) fn new_game(seats: u8, seed: u64) -> Game {
    Game::new(GameSettings {
        seats,
        points_to_win: 10,
        seed,
    })
    .unwrap()
}

/// Plays the setup by always taking the first legal action; ends in `Roll` for seat 0.
pub(crate) fn after_setup(seats: u8, seed: u64) -> Game {
    let mut game = new_game(seats, seed);
    while game.phase != Phase::Roll {
        let seat = game.current;
        let action = game.legal_actions(seat)[0].clone();
        game.apply(seat, action).unwrap();
    }
    game
}

/// After setup, in `Main` for seat 0, with every hand returned to the bank.
pub(crate) fn main_phase_game(seats: u8, seed: u64) -> Game {
    let mut game = after_setup(seats, seed);
    for player in &mut game.players {
        game.bank.deposit(&player.hand);
        player.hand = ResourceCounts::default();
    }
    game.phase = Phase::Main;
    game
}

/// Moves `resources` from the bank to the seat's hand, keeping the total at 95.
pub(crate) fn give(game: &mut Game, seat: Seat, resources: ResourceCounts) {
    game.bank.try_remove(&resources).unwrap();
    game.players[usize::from(seat)].hand.deposit(&resources);
}

pub(crate) fn put_road(game: &mut Game, seat: Seat, first: CornerId, second: CornerId) {
    let edge = edge_between(game, first, second);
    game.board.set_road(edge, seat);
}

pub(crate) fn put_settlement(game: &mut Game, seat: Seat, corner: CornerId) {
    let building = Building {
        seat,
        kind: BuildingKind::Settlement,
    };
    game.board.set_building(corner, building);
}

pub(crate) fn edge_between(game: &Game, first: CornerId, second: CornerId) -> EdgeId {
    game.board
        .edge_ids()
        .find(|edge| {
            let corners = game.board.edge(*edge).unwrap().corners;
            corners.contains(&first) && corners.contains(&second)
        })
        .unwrap()
}

pub(crate) fn tile_with_number(game: &Game, number: u8) -> (TileId, Resource) {
    game.board
        .tile_ids()
        .find_map(|id| {
            let tile = game.board.tile(id).unwrap();
            (tile.number == Some(number)).then(|| (id, tile.resource.unwrap()))
        })
        .unwrap()
}
