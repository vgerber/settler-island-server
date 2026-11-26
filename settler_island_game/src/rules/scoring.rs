use crate::board::{Board, BuildingKind, CornerId, EdgeId};
use crate::event::Event;
use crate::game::{DevelopmentCard, Game, PlayerState, Seat};
use crate::phase::Phase;

const MIN_LONGEST_ROAD: u8 = 5;
/// Knights a player needs to hold the largest army.
pub const MIN_LARGEST_ARMY: u8 = 3;
const AWARD_POINTS: u8 = 2;

/// Points everyone can see: buildings and awards, without hidden victory point cards.
pub(crate) fn public_points(game: &Game, seat: Seat) -> u8 {
    let buildings: u8 = game
        .board
        .buildings_of(seat)
        .map(|(_, building)| match building.kind {
            BuildingKind::Settlement => 1,
            BuildingKind::City => 2,
        })
        .sum();
    let awards = [game.longest_road, game.largest_army]
        .into_iter()
        .filter(|holder| *holder == Some(seat))
        .count() as u8;
    buildings + awards * AWARD_POINTS
}

/// Public points plus the seat's hidden victory point cards.
pub(crate) fn total_points(game: &Game, seat: Seat) -> u8 {
    let cards = game
        .players
        .get(usize::from(seat))
        .map_or(0, victory_point_cards);
    public_points(game, seat) + cards
}

fn victory_point_cards(player: &PlayerState) -> u8 {
    player
        .development_cards
        .iter()
        .chain(&player.new_development_cards)
        .filter(|card| **card == DevelopmentCard::VictoryPoint)
        .count() as u8
}

/// Runs after every accepted action: awards, then the win check for the seat whose turn it is.
pub(crate) fn after_action(game: &mut Game) -> Vec<Event> {
    if matches!(game.phase, Phase::Finished { .. }) {
        return Vec::new();
    }
    let mut events = update_longest_road(game);
    events.extend(update_largest_army(game));
    let seat = game.current;
    events.extend(check_winner(game, seat));
    events
}

fn update_longest_road(game: &mut Game) -> Vec<Event> {
    let lengths: Vec<u8> = (0..game.settings.seats)
        .map(|seat| road_length(&game.board, seat))
        .collect();
    let holder = longest_road_holder(game.longest_road, &lengths);
    if holder == game.longest_road {
        return Vec::new();
    }
    game.longest_road = holder;
    let length = holder.map_or(0, |seat| lengths[usize::from(seat)]);
    vec![Event::LongestRoadChanged { holder, length }]
}

/// The holder keeps the award while tied for the lead; otherwise it goes to the unique leader, or nobody on a tie.
fn longest_road_holder(holder: Option<Seat>, lengths: &[u8]) -> Option<Seat> {
    let longest = lengths.iter().copied().max().unwrap_or(0);
    if longest < MIN_LONGEST_ROAD {
        return None;
    }
    let leaders: Vec<Seat> = (0..lengths.len() as Seat)
        .filter(|seat| lengths[usize::from(*seat)] == longest)
        .collect();
    if holder.is_some_and(|seat| leaders.contains(&seat)) {
        return holder;
    }
    match leaders.as_slice() {
        [leader] => Some(*leader),
        _ => None,
    }
}

fn update_largest_army(game: &mut Game) -> Vec<Event> {
    let knights = |seat: Seat| game.players[usize::from(seat)].knights_played;
    let mut holder = game.largest_army;
    for seat in 0..game.settings.seats {
        let needed = holder.map_or(MIN_LARGEST_ARMY, |current| {
            knights(current).saturating_add(1)
        });
        if knights(seat) >= needed.max(MIN_LARGEST_ARMY) {
            holder = Some(seat);
        }
    }
    if holder == game.largest_army {
        return Vec::new();
    }
    game.largest_army = holder;
    let knights = holder.map_or(0, knights);
    vec![Event::LargestArmyChanged { holder, knights }]
}

/// Longest trail in the seat's road network: each road used once, corners may repeat, never passing a corner that
/// holds an opponent's building.
pub(crate) fn road_length(board: &Board, seat: Seat) -> u8 {
    board
        .corner_ids()
        .map(|corner| longest_trail_from(board, seat, corner, 0))
        .max()
        .unwrap_or(0)
}

/// `used` has one bit per edge id; the board has 72 edges.
fn longest_trail_from(board: &Board, seat: Seat, corner: CornerId, used: u128) -> u8 {
    let Some(data) = board.corner(corner) else {
        return 0;
    };
    data.edges
        .iter()
        .filter(|edge| board.road(**edge) == Some(seat) && used & edge_bit(**edge) == 0)
        .filter_map(|edge| Some((*edge, board.edge(*edge)?.other_end(corner)?)))
        .map(|(edge, next)| {
            if blocks(board, seat, next) {
                return 1;
            }
            1 + longest_trail_from(board, seat, next, used | edge_bit(edge))
        })
        .max()
        .unwrap_or(0)
}

fn edge_bit(edge: EdgeId) -> u128 {
    1 << edge.0
}

fn blocks(board: &Board, seat: Seat, corner: CornerId) -> bool {
    board
        .building(corner)
        .is_some_and(|building| building.seat != seat)
}

/// Ends the game when `seat` reached the target during its own turn.
fn check_winner(game: &mut Game, seat: Seat) -> Vec<Event> {
    let points = total_points(game, seat);
    if points < game.settings.points_to_win {
        return Vec::new();
    }
    vec![
        Event::GameWon { seat, points },
        game.enter(Phase::Finished { winner: seat }),
    ]
}

#[cfg(test)]
mod tests {
    use proptest::prelude::*;

    use super::*;
    use crate::board::Building;
    use crate::coordinates::CubeCoordinates;
    use crate::rules::test_support::{new_game, put_road, put_settlement};

    /// A clean board (no pieces) in `Main` for seat 0.
    fn scoring_game() -> Game {
        let mut game = new_game(3, 7);
        game.phase = Phase::Main;
        game
    }

    fn ring(game: &Game, q: i32, r: i32) -> [CornerId; 6] {
        let coordinates = CubeCoordinates::from_qr(q, r);
        game.board
            .tiles()
            .iter()
            .find(|tile| tile.coordinates == coordinates)
            .unwrap()
            .corners
    }

    /// A simple path of `length` roads from `start`, stepping to the lowest corner not yet used or avoided.
    fn line(game: &Game, start: CornerId, length: usize, avoid: &[CornerId]) -> Vec<CornerId> {
        let mut path = vec![start];
        for _ in 0..length {
            let last = *path.last().unwrap();
            let next = game
                .board
                .corner(last)
                .unwrap()
                .neighbors
                .iter()
                .copied()
                .find(|corner| !path.contains(corner) && !avoid.contains(corner));
            path.push(next.unwrap());
        }
        path
    }

    fn put_path(game: &mut Game, seat: Seat, corners: &[CornerId]) {
        for pair in corners.windows(2) {
            put_road(game, seat, pair[0], pair[1]);
        }
    }

    fn put_city(game: &mut Game, seat: Seat, corner: CornerId) {
        let building = Building {
            seat,
            kind: BuildingKind::City,
        };
        game.board.set_building(corner, building);
    }

    fn closed(ring: [CornerId; 6]) -> Vec<CornerId> {
        let mut corners = ring.to_vec();
        corners.push(ring[0]);
        corners
    }

    fn longest_road_events(events: &[Event]) -> Vec<Event> {
        events
            .iter()
            .filter(|event| matches!(event, Event::LongestRoadChanged { .. }))
            .cloned()
            .collect()
    }

    #[test]
    fn branch_counts_the_longest_path_not_every_road() {
        let mut game = scoring_game();
        let center = ring(&game, 0, 0);
        put_path(&mut game, 0, &center);
        let spur = line(&game, center[2], 3, &center);
        put_path(&mut game, 0, &spur);

        assert_eq!(road_length(&game.board, 0), 6);
    }

    #[test]
    fn cycle_with_a_tail_reuses_the_corner_where_the_tail_joins() {
        let mut game = scoring_game();
        let center = ring(&game, 0, 0);
        put_path(&mut game, 0, &closed(center));
        assert_eq!(road_length(&game.board, 0), 6);

        let tail = line(&game, center[0], 1, &center);
        put_path(&mut game, 0, &tail);
        assert_eq!(road_length(&game.board, 0), 7);
    }

    #[test]
    fn two_rings_sharing_a_road_form_one_trail() {
        let mut game = scoring_game();
        let piece = closed(ring(&game, 0, 0));
        put_path(&mut game, 0, &piece);
        let piece = closed(ring(&game, 1, 0));
        put_path(&mut game, 0, &piece);

        assert_eq!(road_length(&game.board, 0), 11);
    }

    #[test]
    fn opponent_settlement_breaks_the_road_only_in_the_middle() {
        let mut game = scoring_game();
        let center = ring(&game, 0, 0);
        put_path(&mut game, 0, &center);
        let events = after_action(&mut game);
        assert_eq!(
            longest_road_events(&events),
            vec![Event::LongestRoadChanged {
                holder: Some(0),
                length: 5
            }]
        );

        put_settlement(&mut game, 0, center[3]);
        put_settlement(&mut game, 1, center[0]);
        assert!(after_action(&mut game).is_empty());
        assert_eq!(road_length(&game.board, 0), 5);

        put_settlement(&mut game, 1, center[2]);
        let events = after_action(&mut game);
        assert_eq!(road_length(&game.board, 0), 3);
        assert_eq!(
            longest_road_events(&events),
            vec![Event::LongestRoadChanged {
                holder: None,
                length: 0
            }]
        );
        assert_eq!(game.longest_road, None);
    }

    #[test]
    fn tie_keeps_the_holder_and_a_longer_road_takes_over() {
        let mut game = scoring_game();
        let center = ring(&game, 0, 0);
        let far = ring(&game, 2, -2);
        put_path(&mut game, 0, &center);
        after_action(&mut game);
        put_path(&mut game, 1, &far);

        assert!(after_action(&mut game).is_empty());
        assert_eq!(game.longest_road, Some(0));
        assert_eq!(public_points(&game, 0), 2);

        put_path(&mut game, 1, &[far[5], far[0]]);
        let events = after_action(&mut game);
        assert_eq!(
            events,
            vec![Event::LongestRoadChanged {
                holder: Some(1),
                length: 6
            }]
        );
        assert_eq!(public_points(&game, 0), 0);
        assert_eq!(public_points(&game, 1), 2);
    }

    #[test]
    fn broken_holder_with_a_tie_behind_leaves_nobody_then_a_unique_leader_takes_it() {
        let mut game = scoring_game();
        let first = ring(&game, 2, -2);
        let second = ring(&game, -2, 2);
        let center = ring(&game, 0, 0);
        let mut holder_road = center.to_vec();
        let avoid: Vec<CornerId> = first
            .iter()
            .chain(&second)
            .chain(&center)
            .copied()
            .collect();
        holder_road.extend(line(&game, center[5], 2, &avoid).into_iter().skip(1));
        put_path(&mut game, 0, &holder_road);
        put_path(&mut game, 1, &first);
        put_path(&mut game, 2, &second);
        after_action(&mut game);
        assert_eq!(game.longest_road, Some(0));
        assert_eq!(road_length(&game.board, 0), 7);

        put_settlement(&mut game, 1, holder_road[3]);
        let events = after_action(&mut game);
        assert_eq!(
            events,
            vec![Event::LongestRoadChanged {
                holder: None,
                length: 0
            }]
        );

        put_path(&mut game, 2, &[second[5], second[0]]);
        after_action(&mut game);
        assert_eq!(game.longest_road, Some(2));
    }

    #[test]
    fn broken_holder_still_tied_keeps_the_award() {
        let mut game = scoring_game();
        let center = ring(&game, 0, 0);
        let far = ring(&game, 2, -2);
        put_path(&mut game, 0, &center);
        let piece = line(&game, center[5], 1, &center);
        put_path(&mut game, 0, &piece);
        after_action(&mut game);
        put_path(&mut game, 1, &far);
        put_settlement(&mut game, 1, center[1]);
        assert_eq!(road_length(&game.board, 0), 5);

        assert!(after_action(&mut game).is_empty());
        assert_eq!(game.longest_road, Some(0));
    }

    #[test]
    fn largest_army_needs_three_and_strictly_more_to_take_over() {
        let mut game = scoring_game();
        game.players[1].knights_played = 2;
        assert!(after_action(&mut game).is_empty());

        game.players[1].knights_played = 3;
        assert_eq!(
            after_action(&mut game),
            vec![Event::LargestArmyChanged {
                holder: Some(1),
                knights: 3
            }]
        );

        game.players[2].knights_played = 3;
        assert!(after_action(&mut game).is_empty());
        assert_eq!(game.largest_army, Some(1));

        game.players[2].knights_played = 4;
        assert_eq!(
            after_action(&mut game),
            vec![Event::LargestArmyChanged {
                holder: Some(2),
                knights: 4
            }]
        );
        assert_eq!(public_points(&game, 2), 2);
        assert_eq!(public_points(&game, 1), 0);
    }

    #[test]
    fn hidden_cards_count_only_for_the_own_view_and_win_only_on_own_turn() {
        let mut game = scoring_game();
        let center = ring(&game, 0, 0);
        for corner in [center[0], center[2], center[4]] {
            put_city(&mut game, 1, corner);
        }
        let piece = ring(&game, 2, -2)[0];
        put_settlement(&mut game, 1, piece);
        let piece = ring(&game, -2, 2)[0];
        put_settlement(&mut game, 1, piece);
        game.players[1].development_cards =
            vec![DevelopmentCard::VictoryPoint, DevelopmentCard::Knight];
        game.players[1].new_development_cards = vec![DevelopmentCard::VictoryPoint];

        assert!(after_action(&mut game).is_empty());
        assert_eq!(game.phase, Phase::Main);
        assert_eq!(game.view(Some(2)).players[1].points, 8);
        assert_eq!(game.view(None).players[1].points, 8);
        assert_eq!(game.view(Some(1)).players[1].points, 10);

        game.current = 1;
        assert_eq!(
            after_action(&mut game),
            vec![
                Event::GameWon {
                    seat: 1,
                    points: 10
                },
                Event::PhaseChanged {
                    phase: Phase::Finished { winner: 1 }
                },
            ]
        );
    }

    #[test]
    fn award_gained_by_the_action_counts_for_the_win() {
        let mut game = scoring_game();
        let far = ring(&game, 2, -2);
        for corner in [far[0], far[2], far[4]] {
            put_city(&mut game, 0, corner);
        }
        let piece = ring(&game, -2, 2)[0];
        put_settlement(&mut game, 0, piece);
        let piece = ring(&game, 0, 2)[0];
        put_settlement(&mut game, 0, piece);
        let piece = ring(&game, 0, 0);
        put_path(&mut game, 0, &piece);

        let events = after_action(&mut game);
        assert!(events.contains(&Event::GameWon {
            seat: 0,
            points: 10
        }));
        assert_eq!(game.phase, Phase::Finished { winner: 0 });
    }

    /// Brute force: the largest road subset that is one connected trail once every opponent-held corner is split into
    /// one dead end per road (Euler: at most two odd corners).
    fn brute_force_length(board: &Board, seat: Seat) -> u8 {
        let roads: Vec<EdgeId> = board
            .edge_ids()
            .filter(|edge| board.road(*edge) == Some(seat))
            .collect();
        let ends = |edge: EdgeId| -> [(CornerId, Option<EdgeId>); 2] {
            board.edge(edge).unwrap().corners.map(|corner| {
                let split = blocks(board, seat, corner).then_some(edge);
                (corner, split)
            })
        };
        (0u32..1 << roads.len())
            .filter_map(|mask| {
                let chosen: Vec<EdgeId> = (0..roads.len())
                    .filter(|bit| mask & (1 << bit) != 0)
                    .map(|bit| roads[bit])
                    .collect();
                is_trail(&chosen, ends).then_some(chosen.len() as u8)
            })
            .max()
            .unwrap_or(0)
    }

    fn is_trail(
        chosen: &[EdgeId],
        ends: impl Fn(EdgeId) -> [(CornerId, Option<EdgeId>); 2],
    ) -> bool {
        let mut vertices: Vec<(CornerId, Option<EdgeId>)> =
            chosen.iter().flat_map(|edge| ends(*edge)).collect();
        vertices.sort();
        let odd = vertices
            .chunk_by(PartialEq::eq)
            .filter(|group| group.len() % 2 == 1)
            .count();
        vertices.dedup();
        let mut reached: Vec<(CornerId, Option<EdgeId>)> =
            vertices.first().copied().into_iter().collect();
        // Each pass grows the reached set by at least one road while the chosen roads are connected.
        for _ in chosen {
            let touching: Vec<(CornerId, Option<EdgeId>)> = chosen
                .iter()
                .map(|edge| ends(*edge))
                .filter(|pair| pair.iter().any(|vertex| reached.contains(vertex)))
                .flatten()
                .collect();
            reached.extend(touching);
            reached.sort();
            reached.dedup();
        }
        odd <= 2 && reached.len() == vertices.len()
    }

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(256))]

        #[test]
        fn road_length_matches_brute_force(
            start in 0usize..54,
            steps in proptest::collection::vec((any::<usize>(), any::<usize>()), 1..11),
            blockers in proptest::collection::vec(any::<usize>(), 0..3),
        ) {
            let mut game = scoring_game();
            let mut touched = vec![CornerId(start as u8)];
            for (corner_choice, edge_choice) in steps {
                let corner = touched[corner_choice % touched.len()];
                let edges = &game.board.corner(corner).unwrap().edges;
                let edge = edges[edge_choice % edges.len()];
                game.board.set_road(edge, 0);
                for next in game.board.edge(edge).unwrap().corners {
                    if !touched.contains(&next) {
                        touched.push(next);
                    }
                }
            }
            for choice in blockers {
                put_settlement(&mut game, 1, touched[choice % touched.len()]);
            }

            prop_assert_eq!(road_length(&game.board, 0), brute_force_length(&game.board, 0));
        }
    }
}
