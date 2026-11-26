use crate::action::Action;
use crate::board::{Board, Building, BuildingKind, CornerId, EdgeId};
use crate::error::GameError;
use crate::event::Event;
use crate::game::{Game, Seat};
use crate::resource::ResourceCounts;
use crate::rules::purchase::Purchase;

pub(crate) fn build_road(
    game: &mut Game,
    seat: Seat,
    edge: EdgeId,
) -> Result<Vec<Event>, GameError> {
    check_road(game, seat, edge)?;
    let mut events = vec![game.pay_to_bank(seat, Purchase::Road.cost())?];
    events.push(place_road(game, seat, edge));
    Ok(events)
}

pub(crate) fn build_settlement(
    game: &mut Game,
    seat: Seat,
    corner: CornerId,
) -> Result<Vec<Event>, GameError> {
    check_settlement(game, seat, corner)?;
    let mut events = vec![game.pay_to_bank(seat, Purchase::Settlement.cost())?];
    events.push(place_settlement(game, seat, corner));
    Ok(events)
}

pub(crate) fn build_city(
    game: &mut Game,
    seat: Seat,
    corner: CornerId,
) -> Result<Vec<Event>, GameError> {
    check_city(game, seat, corner)?;
    let mut events = vec![game.pay_to_bank(seat, Purchase::City.cost())?];
    // Paying resolved the seat, so this lookup cannot fail after the payment.
    let player = game.player_mut(seat)?;
    player.cities_left -= 1;
    player.settlements_left += 1;
    game.board.set_building(
        corner,
        Building {
            seat,
            kind: BuildingKind::City,
        },
    );
    events.push(Event::CityBuilt { seat, corner });
    Ok(events)
}

/// Cities first, then settlements, then roads, so a first-action player makes progress.
pub(crate) fn legal_builds(game: &Game, seat: Seat) -> Vec<Action> {
    let cities = game
        .board
        .corner_ids()
        .filter(|corner| check_city(game, seat, *corner).is_ok())
        .map(|corner| Action::BuildCity { corner });
    let settlements = game
        .board
        .corner_ids()
        .filter(|corner| check_settlement(game, seat, *corner).is_ok())
        .map(|corner| Action::BuildSettlement { corner });
    let roads = game
        .board
        .edge_ids()
        .filter(|edge| check_road(game, seat, *edge).is_ok())
        .map(|edge| Action::BuildRoad { edge });
    cities.chain(settlements).chain(roads).collect()
}

/// Puts a settlement down and takes it from the supply; callers have validated the corner.
pub(crate) fn place_settlement(game: &mut Game, seat: Seat, corner: CornerId) -> Event {
    let player = game.player_mut(seat);
    debug_assert!(player.is_ok(), "settlement placed for unknown seat {seat}");
    if let Ok(player) = player {
        player.settlements_left -= 1;
    }
    game.board.set_building(
        corner,
        Building {
            seat,
            kind: BuildingKind::Settlement,
        },
    );
    Event::SettlementPlaced { seat, corner }
}

/// Puts a road down and takes it from the supply; callers have validated the edge.
pub(crate) fn place_road(game: &mut Game, seat: Seat, edge: EdgeId) -> Event {
    let player = game.player_mut(seat);
    debug_assert!(player.is_ok(), "road placed for unknown seat {seat}");
    if let Ok(player) = player {
        player.roads_left -= 1;
    }
    game.board.set_road(edge, seat);
    Event::RoadPlaced { seat, edge }
}

/// The corner exists, is free and no neighbouring corner holds a building (distance rule).
pub(crate) fn check_settlement_site(board: &Board, corner: CornerId) -> Result<(), GameError> {
    let location = board.corner(corner).ok_or(GameError::InvalidLocation)?;
    if board.building(corner).is_some() {
        return Err(GameError::Occupied);
    }
    if location
        .neighbors
        .iter()
        .any(|neighbor| board.building(*neighbor).is_some())
    {
        return Err(GameError::TooClose);
    }
    Ok(())
}

/// The edge exists and holds no road.
pub(crate) fn check_road_site(board: &Board, edge: EdgeId) -> Result<[CornerId; 2], GameError> {
    let location = board.edge(edge).ok_or(GameError::InvalidLocation)?;
    if board.road(edge).is_some() {
        return Err(GameError::Occupied);
    }
    Ok(location.corners)
}

fn check_road(game: &Game, seat: Seat, edge: EdgeId) -> Result<(), GameError> {
    game.require_main_turn(seat)?;
    check_road_placement(game, seat, edge)?;
    require_resources(&game.player(seat)?.hand, &Purchase::Road.cost())
}

/// Free edge, connected to the own network, and a road left in the supply; bought and free roads share it.
pub(crate) fn check_road_placement(game: &Game, seat: Seat, edge: EdgeId) -> Result<(), GameError> {
    let corners = check_road_site(&game.board, edge)?;
    if !corners
        .iter()
        .any(|corner| road_continues_from(&game.board, seat, *corner, edge))
    {
        return Err(GameError::NotConnected);
    }
    if game.player(seat)?.roads_left == 0 {
        return Err(GameError::NoPiecesLeft);
    }
    Ok(())
}

/// A road may start at an own building, or at an own road unless an opponent's building sits on the corner.
fn road_continues_from(board: &Board, seat: Seat, corner: CornerId, new_edge: EdgeId) -> bool {
    if let Some(building) = board.building(corner) {
        return building.seat == seat;
    }
    let Some(location) = board.corner(corner) else {
        return false;
    };
    location
        .edges
        .iter()
        .any(|edge| *edge != new_edge && board.road(*edge) == Some(seat))
}

fn check_settlement(game: &Game, seat: Seat, corner: CornerId) -> Result<(), GameError> {
    game.require_main_turn(seat)?;
    check_settlement_site(&game.board, corner)?;
    let touches_own_road = game.board.corner(corner).is_some_and(|location| {
        location
            .edges
            .iter()
            .any(|edge| game.board.road(*edge) == Some(seat))
    });
    if !touches_own_road {
        return Err(GameError::NotConnected);
    }
    let player = game.player(seat)?;
    if player.settlements_left == 0 {
        return Err(GameError::NoPiecesLeft);
    }
    require_resources(&player.hand, &Purchase::Settlement.cost())
}

fn check_city(game: &Game, seat: Seat, corner: CornerId) -> Result<(), GameError> {
    game.require_main_turn(seat)?;
    let own_settlement = Building {
        seat,
        kind: BuildingKind::Settlement,
    };
    if game.board.building(corner) != Some(own_settlement) {
        return Err(GameError::InvalidLocation);
    }
    let player = game.player(seat)?;
    if player.cities_left == 0 {
        return Err(GameError::NoPiecesLeft);
    }
    require_resources(&player.hand, &Purchase::City.cost())
}

fn require_resources(hand: &ResourceCounts, cost: &ResourceCounts) -> Result<(), GameError> {
    if !hand.contains(cost) {
        return Err(GameError::NotEnoughResources);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::phase::Phase;
    use crate::rules::test_support::{
        edge_between, give, main_phase_game, put_road, put_settlement,
    };

    /// A corner with three neighbours, so a path `start - middle - far` exists along edges.
    fn path(game: &Game) -> (CornerId, CornerId, CornerId) {
        let board = &game.board;
        let free = |corner: &CornerId| {
            check_settlement_site(board, *corner).is_ok()
                && board.corner(*corner).is_some_and(|location| {
                    location
                        .neighbors
                        .iter()
                        .all(|neighbor| check_settlement_site(board, *neighbor).is_ok())
                })
        };
        let middle = board
            .corner_ids()
            .find(|corner| {
                free(corner)
                    && board
                        .corner(*corner)
                        .is_some_and(|location| location.neighbors.len() == 3)
            })
            .unwrap();
        let neighbors = &board.corner(middle).unwrap().neighbors;
        (neighbors[0], middle, neighbors[1])
    }

    #[test]
    fn road_may_end_at_but_not_pass_through_an_opponent_settlement() {
        let mut game = main_phase_game(4, 5);
        let seat = game.current;
        let opponent = (seat + 1) % 4;
        let (start, middle, far) = path(&game);
        put_road(&mut game, seat, start, middle);
        give(&mut game, seat, Purchase::Road.cost());
        let beyond = edge_between(&game, middle, far);

        let mut ending_at_opponent = game.clone();
        put_settlement(&mut ending_at_opponent, opponent, far);
        assert!(ending_at_opponent
            .apply(seat, Action::BuildRoad { edge: beyond })
            .is_ok());

        put_settlement(&mut game, opponent, middle);
        let before = game.clone();
        assert_eq!(
            game.apply(seat, Action::BuildRoad { edge: beyond }),
            Err(GameError::NotConnected)
        );
        assert_eq!(game, before);
    }

    #[test]
    fn road_must_touch_own_network() {
        let mut game = main_phase_game(3, 8);
        let seat = game.current;
        let (start, middle, _) = path(&game);
        give(&mut game, seat, Purchase::Road.cost());

        assert_eq!(
            game.apply(
                seat,
                Action::BuildRoad {
                    edge: edge_between(&game, start, middle)
                }
            ),
            Err(GameError::NotConnected)
        );
    }

    #[test]
    fn settlement_needs_own_road_and_respects_distance() {
        let mut game = main_phase_game(4, 21);
        let seat = game.current;
        let (start, middle, far) = path(&game);
        give(&mut game, seat, Purchase::Settlement.cost());

        assert_eq!(
            game.clone()
                .apply(seat, Action::BuildSettlement { corner: middle }),
            Err(GameError::NotConnected)
        );
        put_road(&mut game, seat, start, middle);
        put_road(&mut game, seat, middle, far);
        put_settlement(&mut game, (seat + 1) % 4, far);
        assert_eq!(
            game.clone()
                .apply(seat, Action::BuildSettlement { corner: middle }),
            Err(GameError::TooClose)
        );
        assert_eq!(
            game.clone()
                .apply(seat, Action::BuildSettlement { corner: far }),
            Err(GameError::Occupied)
        );
        assert!(game
            .apply(seat, Action::BuildSettlement { corner: start })
            .is_ok());
    }

    #[test]
    fn piece_limits_are_enforced() {
        let mut game = main_phase_game(4, 2);
        let seat = game.current;
        let own_settlement = game
            .board
            .corner_ids()
            .find(|corner| {
                game.board
                    .building(*corner)
                    .is_some_and(|building| building.seat == seat)
            })
            .unwrap();
        let free_edge = game
            .board
            .edge_ids()
            .find(|edge| check_road(&game, seat, *edge) == Err(GameError::NotEnoughResources))
            .unwrap();
        give(
            &mut game,
            seat,
            Purchase::Road
                .cost()
                .checked_add(&Purchase::City.cost())
                .unwrap(),
        );
        game.players[usize::from(seat)].roads_left = 0;
        game.players[usize::from(seat)].cities_left = 0;

        assert_eq!(
            game.apply(seat, Action::BuildRoad { edge: free_edge }),
            Err(GameError::NoPiecesLeft)
        );
        assert_eq!(
            game.apply(
                seat,
                Action::BuildCity {
                    corner: own_settlement
                }
            ),
            Err(GameError::NoPiecesLeft)
        );
    }

    #[test]
    fn city_replaces_own_settlement_and_returns_it_to_the_supply() {
        let mut game = main_phase_game(3, 4);
        let seat = game.current;
        let settlements = |game: &Game, owner: Seat| {
            game.board
                .corner_ids()
                .filter(|corner| {
                    game.board
                        .building(*corner)
                        .is_some_and(|building| building.seat == owner)
                })
                .collect::<Vec<_>>()
        };
        let own = settlements(&game, seat)[0];
        let foreign = settlements(&game, (seat + 1) % 3)[0];
        give(&mut game, seat, Purchase::City.cost());
        let settlements_left = game.players[usize::from(seat)].settlements_left;

        assert_eq!(
            game.clone()
                .apply(seat, Action::BuildCity { corner: foreign }),
            Err(GameError::InvalidLocation)
        );
        let events = game.apply(seat, Action::BuildCity { corner: own }).unwrap();

        assert!(events.contains(&Event::CityBuilt { seat, corner: own }));
        assert_eq!(
            game.board.building(own),
            Some(Building {
                seat,
                kind: BuildingKind::City
            })
        );
        assert_eq!(
            game.players[usize::from(seat)].settlements_left,
            settlements_left + 1
        );
        assert_eq!(game.players[usize::from(seat)].cities_left, 3);
        assert_eq!(
            game.players[usize::from(seat)].hand,
            ResourceCounts::default()
        );
        assert_eq!(
            game.clone().apply(seat, Action::BuildCity { corner: own }),
            Err(GameError::InvalidLocation)
        );
    }

    #[test]
    fn reaching_the_target_on_own_turn_wins() {
        let mut game = main_phase_game(3, 4);
        game.settings.points_to_win = 3;
        let seat = game.current;
        let own = game
            .board
            .corner_ids()
            .find(|corner| {
                game.board
                    .building(*corner)
                    .is_some_and(|building| building.seat == seat)
            })
            .unwrap();
        give(&mut game, seat, Purchase::City.cost());

        let events = game.apply(seat, Action::BuildCity { corner: own }).unwrap();

        assert_eq!(
            events.last(),
            Some(&Event::PhaseChanged {
                phase: Phase::Finished { winner: seat }
            })
        );
        assert!(events.contains(&Event::GameWon { seat, points: 3 }));
        assert_eq!(
            game.apply(seat, Action::EndTurn),
            Err(GameError::GameFinished)
        );
    }

    #[test]
    fn failed_build_keeps_the_cards() {
        let mut game = main_phase_game(4, 9);
        let seat = game.current;
        let (start, middle, _) = path(&game);
        give(&mut game, seat, Purchase::Settlement.cost());
        let before = game.clone();

        assert_eq!(
            game.apply(seat, Action::BuildSettlement { corner: middle }),
            Err(GameError::NotConnected)
        );
        assert_eq!(
            game.apply(
                seat,
                Action::BuildRoad {
                    edge: edge_between(&game, start, middle)
                }
            ),
            Err(GameError::NotConnected)
        );
        assert_eq!(game, before);
    }
}
