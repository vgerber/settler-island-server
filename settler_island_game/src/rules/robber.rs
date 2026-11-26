use crate::action::Action;
use crate::board::TileId;
use crate::error::GameError;
use crate::event::Event;
use crate::game::{Game, Holder, Seat};
use crate::phase::{OwedDiscard, Phase};
use rand::Rng;

use crate::resource::{Resource, ResourceCounts};

/// A seat with more cards than this discards half of them on a 7.
pub const DISCARD_ABOVE_CARDS: u32 = 7;

/// Moves the robber to another tile. With `then_steal` and a victim on the tile the turn goes to `Steal`;
/// otherwise the steal is skipped and the turn continues in `Main`.
pub(crate) fn move_robber(
    game: &mut Game,
    seat: Seat,
    tile: TileId,
) -> Result<Vec<Event>, GameError> {
    check_move(game, seat, tile)?;
    let then_steal = matches!(game.phase, Phase::MoveRobber { then_steal: true });
    game.board.set_robber(tile);
    let next = if then_steal && !victims(game, seat, tile).is_empty() {
        Phase::Steal { tile }
    } else {
        game.turn_phase()
    };
    Ok(vec![Event::RobberMoved { seat, tile }, game.enter(next)])
}

pub(crate) fn legal_moves(game: &Game, seat: Seat) -> Vec<Action> {
    game.board
        .tile_ids()
        .filter(|tile| check_move(game, seat, *tile).is_ok())
        .map(|tile| Action::MoveRobber { tile })
        .collect()
}

/// A rolled 7: seats above the hand limit discard half (rounded down), then the roller moves the robber.
pub(crate) fn on_seven(game: &mut Game, _seat: Seat) -> Vec<Event> {
    let owed: Vec<OwedDiscard> = (0..game.settings.seats)
        .filter_map(|seat| {
            let total = game.player(seat).ok()?.hand.total();
            (total > DISCARD_ABOVE_CARDS).then(|| OwedDiscard {
                seat,
                cards: u8::try_from(total / 2).unwrap_or(u8::MAX),
            })
        })
        .collect();
    let phase = if owed.is_empty() {
        Phase::MoveRobber { then_steal: true }
    } else {
        Phase::Discard { owed }
    };
    vec![game.enter(phase)]
}

/// Returns exactly the owed number of cards to the bank. Seats discard in any order.
pub(crate) fn discard(
    game: &mut Game,
    seat: Seat,
    resources: ResourceCounts,
) -> Result<Vec<Event>, GameError> {
    let Phase::Discard { owed } = &game.phase else {
        return Err(GameError::WrongPhase);
    };
    let cards = game
        .phase
        .owed_discard(seat)
        .ok_or(GameError::NotYourTurn)?;
    if resources.total() != u32::from(cards) {
        return Err(GameError::InvalidDiscard);
    }
    let left: Vec<OwedDiscard> = owed
        .iter()
        .filter(|entry| entry.seat != seat)
        .copied()
        .collect();
    game.move_resources(Holder::Seat(seat), Holder::Bank, resources)?;

    let mut events = vec![Event::CardsDiscarded { seat, resources }];
    let next = if left.is_empty() {
        Phase::MoveRobber { then_steal: true }
    } else {
        Phase::Discard { owed: left }
    };
    events.push(game.enter(next));
    Ok(events)
}

/// Takes one random card from the victim; the roller or knight player is `game.current`.
pub(crate) fn steal(game: &mut Game, seat: Seat, victim: Seat) -> Result<Vec<Event>, GameError> {
    game.require_turn(seat)?;
    let Phase::Steal { tile } = game.phase else {
        return Err(GameError::WrongPhase);
    };
    if !victims(game, seat, tile).contains(&victim) {
        return Err(GameError::InvalidVictim);
    }
    let hand = game.player(victim)?.hand;
    let mut pick = game.rng.random_range(0..hand.total());
    let resource = Resource::ALL
        .into_iter()
        .find(|resource| {
            let count = u32::from(hand.get(*resource));
            if pick < count {
                return true;
            }
            pick -= count;
            false
        })
        .ok_or(GameError::InvalidVictim)?;
    game.move_resources(
        Holder::Seat(victim),
        Holder::Seat(seat),
        ResourceCounts::single(resource, 1),
    )?;
    Ok(vec![
        Event::ResourceStolen {
            thief: seat,
            victim,
            resource: Some(resource),
        },
        game.enter(game.turn_phase()),
    ])
}

/// Every exact-count sub-multiset of the hand.
pub(crate) fn legal_discards(game: &Game, seat: Seat) -> Vec<Action> {
    let Some(cards) = game.phase.owed_discard(seat) else {
        return Vec::new();
    };
    let Ok(player) = game.player(seat) else {
        return Vec::new();
    };
    let hand = player.hand;
    let mut found = Vec::new();
    sub_multisets(&hand, 0, cards, ResourceCounts::default(), &mut found);
    found
        .into_iter()
        .map(|resources| Action::Discard { resources })
        .collect()
}

fn sub_multisets(
    hand: &ResourceCounts,
    index: usize,
    owed: u8,
    chosen: ResourceCounts,
    found: &mut Vec<ResourceCounts>,
) {
    let Some(resource) = Resource::ALL.get(index).copied() else {
        if owed == 0 {
            found.push(chosen);
        }
        return;
    };
    for take in 0..=hand.get(resource).min(owed) {
        let mut next = chosen;
        next.set(resource, take);
        sub_multisets(hand, index + 1, owed - take, next, found);
    }
}

pub(crate) fn legal_steals(game: &Game, seat: Seat) -> Vec<Action> {
    let Phase::Steal { tile } = game.phase else {
        return Vec::new();
    };
    victims(game, seat, tile)
        .into_iter()
        .map(|victim| Action::Steal { victim })
        .collect()
}

/// Other seats with a building on the tile and at least one card, in seat order.
fn victims(game: &Game, thief: Seat, tile: TileId) -> Vec<Seat> {
    let Some(tile) = game.board.tile(tile) else {
        return Vec::new();
    };
    let mut seats: Vec<Seat> = tile
        .corners
        .iter()
        .filter_map(|corner| game.board.building(*corner))
        .map(|building| building.seat)
        .filter(|seat| *seat != thief)
        .filter(|seat| {
            game.player(*seat)
                .is_ok_and(|player| player.hand.total() > 0)
        })
        .collect();
    seats.sort_unstable();
    seats.dedup();
    seats
}

fn check_move(game: &Game, seat: Seat, tile: TileId) -> Result<(), GameError> {
    game.require_turn(seat)?;
    if !matches!(game.phase, Phase::MoveRobber { .. }) {
        return Err(GameError::WrongPhase);
    }
    if game.board.tile(tile).is_none() || tile == game.board.robber() {
        return Err(GameError::InvalidLocation);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rules::test_support::{give, main_phase_game, put_settlement};

    fn hand(game: &Game, seat: Seat) -> ResourceCounts {
        game.player(seat).unwrap().hand
    }

    fn total_cards(game: &Game) -> u32 {
        game.bank.total() + game.players.iter().map(|p| p.hand.total()).sum::<u32>()
    }

    fn cards(counts: [u8; 5]) -> ResourceCounts {
        ResourceCounts::new(counts)
    }

    /// Main-phase game in `MoveRobber`; seats 1, 2 and the mover 0 have settlements on the returned tile.
    /// Hands are empty.
    fn robber_game(seed: u64) -> (Game, TileId) {
        let mut game = main_phase_game(4, seed);
        let tile = game
            .board
            .tile_ids()
            .find(|tile| *tile != game.board.robber())
            .unwrap();
        let corners = game.board.tile(tile).unwrap().corners;
        put_settlement(&mut game, 1, corners[0]);
        put_settlement(&mut game, 2, corners[2]);
        put_settlement(&mut game, 0, corners[4]);
        game.phase = Phase::MoveRobber { then_steal: true };
        (game, tile)
    }

    #[test]
    fn robber_must_leave_its_tile() {
        let mut game = main_phase_game(4, 12);
        game.phase = Phase::MoveRobber { then_steal: true };
        let seat = game.current;
        let start = game.board.robber();

        let before = game.clone();
        assert_eq!(
            game.apply(seat, Action::MoveRobber { tile: start }),
            Err(GameError::InvalidLocation)
        );
        assert_eq!(
            game.apply(seat, Action::MoveRobber { tile: TileId(19) }),
            Err(GameError::InvalidLocation)
        );
        assert_eq!(game, before);

        let target = TileId((start.0 + 1) % 19);
        let events = game
            .apply(seat, Action::MoveRobber { tile: target })
            .unwrap();
        assert_eq!(events[0], Event::RobberMoved { seat, tile: target });
        assert_eq!(game.board.robber(), target);
    }

    #[test]
    fn seven_with_at_most_seven_cards_skips_the_discard() {
        let mut game = main_phase_game(4, 1);
        give(&mut game, 1, cards([2, 2, 1, 1, 1]));
        give(&mut game, 2, cards([1, 0, 0, 0, 0]));

        on_seven(&mut game, 0);

        assert_eq!(game.phase, Phase::MoveRobber { then_steal: true });
        assert_eq!(game.pending_seats(), vec![0]);
    }

    #[test]
    fn eight_or_more_cards_discard_half_rounded_down() {
        let mut game = main_phase_game(4, 1);
        give(&mut game, 0, cards([2, 2, 2, 2, 0])); // 8 -> 4
        give(&mut game, 1, cards([3, 3, 3, 0, 0])); // 9 -> 4
        give(&mut game, 2, cards([4, 4, 2, 1, 1])); // 12 -> 6
        give(&mut game, 3, cards([2, 2, 2, 1, 0])); // 7 -> nothing

        let events = on_seven(&mut game, 0);

        assert_eq!(
            game.phase,
            Phase::Discard {
                owed: vec![
                    OwedDiscard { seat: 0, cards: 4 },
                    OwedDiscard { seat: 1, cards: 4 },
                    OwedDiscard { seat: 2, cards: 6 },
                ]
            }
        );
        assert_eq!(events.len(), 1);
        assert_eq!(game.pending_seats(), vec![0, 1, 2]);
        assert!(game.legal_actions(3).is_empty());
    }

    #[test]
    fn seats_discard_in_any_order_then_the_robber_moves() {
        let mut game = main_phase_game(4, 1);
        give(&mut game, 1, cards([3, 3, 2, 0, 0])); // 8 -> 4
        give(&mut game, 2, cards([4, 0, 0, 0, 4])); // 8 -> 4
        on_seven(&mut game, 0);

        let events = game
            .apply(
                2,
                Action::Discard {
                    resources: cards([2, 0, 0, 0, 2]),
                },
            )
            .unwrap();
        assert_eq!(
            events[0],
            Event::CardsDiscarded {
                seat: 2,
                resources: cards([2, 0, 0, 0, 2])
            }
        );
        assert_eq!(hand(&game, 2), cards([2, 0, 0, 0, 2]));
        assert_eq!(game.bank.get(Resource::Ore), 19 - 4 + 2);
        assert_eq!(
            game.phase,
            Phase::Discard {
                owed: vec![OwedDiscard { seat: 1, cards: 4 }]
            }
        );
        assert_eq!(game.pending_seats(), vec![1]);

        game.apply(
            1,
            Action::Discard {
                resources: cards([1, 1, 2, 0, 0]),
            },
        )
        .unwrap();
        assert_eq!(game.phase, Phase::MoveRobber { then_steal: true });
        assert_eq!(game.pending_seats(), vec![0]);
        assert_eq!(total_cards(&game), 95);
    }

    #[test]
    fn invalid_discards_are_rejected_and_change_nothing() {
        let mut game = main_phase_game(4, 1);
        give(&mut game, 1, cards([3, 3, 2, 0, 0])); // owes 4
        give(&mut game, 2, cards([1, 0, 0, 0, 0]));
        on_seven(&mut game, 0);
        let before = game.clone();

        let attempts = [
            (1, cards([1, 1, 1, 0, 0]), GameError::InvalidDiscard), // too few
            (1, cards([2, 2, 1, 0, 0]), GameError::InvalidDiscard), // too many
            (1, ResourceCounts::default(), GameError::InvalidDiscard),
            (1, cards([0, 0, 0, 4, 0]), GameError::NotEnoughResources), // not in hand
            (1, cards([4, 0, 0, 0, 0]), GameError::NotEnoughResources), // only 3 clay
            (2, cards([1, 0, 0, 0, 0]), GameError::NotYourTurn),        // owes nothing
            (0, ResourceCounts::default(), GameError::NotYourTurn),
            (9, ResourceCounts::default(), GameError::NotYourTurn),
        ];
        for (seat, resources, error) in attempts {
            assert_eq!(
                game.apply(seat, Action::Discard { resources }),
                Err(error),
                "seat {seat} {resources:?}"
            );
            assert_eq!(game, before);
        }
    }

    #[test]
    fn discard_outside_the_discard_phase_is_wrong_phase() {
        let mut game = main_phase_game(4, 1);
        give(&mut game, 0, cards([1, 0, 0, 0, 0]));
        assert_eq!(
            game.apply(
                0,
                Action::Discard {
                    resources: cards([1, 0, 0, 0, 0])
                }
            ),
            Err(GameError::WrongPhase)
        );
    }

    #[test]
    fn legal_discards_are_every_exact_multiset_and_all_accepted() {
        let mut game = main_phase_game(4, 1);
        give(&mut game, 1, cards([3, 3, 2, 0, 0])); // owes 4
        on_seven(&mut game, 0);

        let legal = game.legal_actions(1);

        let mut expected = 0;
        for clay in 0..=3u8 {
            for wood in 0..=3u8 {
                for sheep in 0..=2u8 {
                    if clay + wood + sheep == 4 {
                        expected += 1;
                    }
                }
            }
        }
        assert_eq!(legal.len(), expected);
        let distinct: std::collections::BTreeSet<String> =
            legal.iter().map(|action| format!("{action:?}")).collect();
        assert_eq!(distinct.len(), legal.len());
        for action in legal {
            game.clone().apply(1, action).unwrap();
        }
        assert!(game.legal_actions(0).is_empty());
    }

    #[test]
    fn large_hands_enumerate_exact_counts() {
        let mut game = main_phase_game(4, 1);
        give(&mut game, 1, cards([5, 5, 5, 5, 0]));
        on_seven(&mut game, 0);

        let legal = game.legal_actions(1);

        assert!(legal.len() > 100);
        assert!(legal.iter().all(|action| matches!(
            action,
            Action::Discard { resources } if resources.total() == 10
        )));
    }

    #[test]
    fn moving_next_to_cardholding_victims_goes_to_steal() {
        let (mut game, tile) = robber_game(3);
        give(&mut game, 1, cards([0, 0, 0, 0, 1]));
        give(&mut game, 0, cards([1, 0, 0, 0, 0]));

        let events = game.apply(0, Action::MoveRobber { tile }).unwrap();

        assert_eq!(game.phase, Phase::Steal { tile });
        assert_eq!(
            events.last(),
            Some(&Event::PhaseChanged {
                phase: Phase::Steal { tile }
            })
        );
        // Seat 2 has no cards and seat 0 is the mover: only seat 1 is offered.
        assert_eq!(game.legal_actions(0), vec![Action::Steal { victim: 1 }]);
    }

    #[test]
    fn a_victim_with_two_buildings_on_the_tile_is_offered_once() {
        let (mut game, tile) = robber_game(3);
        let corners = game.board.tile(tile).unwrap().corners;
        put_settlement(&mut game, 1, corners[3]);
        give(&mut game, 1, cards([1, 0, 0, 0, 0]));

        game.apply(0, Action::MoveRobber { tile }).unwrap();

        assert_eq!(game.legal_actions(0), vec![Action::Steal { victim: 1 }]);
    }

    #[test]
    fn no_victim_skips_the_steal() {
        // Seats 1 and 2 are next to the tile but empty-handed; the mover has cards.
        let (mut game, tile) = robber_game(3);
        give(&mut game, 0, cards([2, 0, 0, 0, 0]));
        game.apply(0, Action::MoveRobber { tile }).unwrap();
        assert_eq!(game.phase, Phase::Main);

        // A tile without any building skips too, although a card holder exists elsewhere.
        let (mut game, _) = robber_game(3);
        give(&mut game, 1, cards([1, 0, 0, 0, 0]));
        let lonely = game
            .board
            .tile_ids()
            .find(|candidate| {
                *candidate != game.board.robber()
                    && game
                        .board
                        .tile(*candidate)
                        .unwrap()
                        .corners
                        .iter()
                        .all(|corner| game.board.building(*corner).is_none())
            })
            .unwrap();
        game.apply(0, Action::MoveRobber { tile: lonely }).unwrap();
        assert_eq!(game.phase, Phase::Main);
    }

    #[test]
    fn knight_before_the_roll_returns_to_the_roll() {
        let (mut game, tile) = robber_game(3);
        game.dice_rolled = false;
        give(&mut game, 1, cards([0, 0, 0, 0, 1]));
        game.apply(0, Action::MoveRobber { tile }).unwrap();
        let victim = game.legal_actions(0)[0].clone();
        game.apply(0, victim).unwrap();
        assert_eq!(game.phase, Phase::Roll);

        let (mut game, tile) = robber_game(3);
        game.dice_rolled = false;
        game.apply(0, Action::MoveRobber { tile }).unwrap();
        assert_eq!(game.phase, Phase::Roll);
    }

    #[test]
    fn without_then_steal_the_turn_continues() {
        let (mut game, tile) = robber_game(3);
        give(&mut game, 1, cards([0, 0, 0, 0, 1]));
        game.phase = Phase::MoveRobber { then_steal: false };

        game.apply(0, Action::MoveRobber { tile }).unwrap();

        assert_eq!(game.phase, Phase::Main);
    }

    #[test]
    fn steal_takes_one_card_and_only_from_offered_victims() {
        let (mut game, tile) = robber_game(3);
        give(&mut game, 1, cards([0, 0, 0, 0, 3]));
        give(&mut game, 2, cards([1, 0, 0, 0, 0]));
        game.apply(0, Action::MoveRobber { tile }).unwrap();
        assert_eq!(
            game.legal_actions(0),
            vec![Action::Steal { victim: 1 }, Action::Steal { victim: 2 }]
        );
        let before = game.clone();

        for victim in [0, 3, 9] {
            assert_eq!(
                game.apply(0, Action::Steal { victim }),
                Err(GameError::InvalidVictim)
            );
        }
        assert_eq!(
            game.apply(1, Action::Steal { victim: 2 }),
            Err(GameError::NotYourTurn)
        );
        assert_eq!(game, before);

        let events = game.apply(0, Action::Steal { victim: 1 }).unwrap();

        assert_eq!(
            events[0],
            Event::ResourceStolen {
                thief: 0,
                victim: 1,
                resource: Some(Resource::Ore)
            }
        );
        assert_eq!(hand(&game, 1), cards([0, 0, 0, 0, 2]));
        assert_eq!(hand(&game, 0), cards([0, 0, 0, 0, 1]));
        assert_eq!(hand(&game, 2), cards([1, 0, 0, 0, 0]));
        assert_eq!(game.phase, Phase::Main);
        assert_eq!(total_cards(&game), 95);
        assert_eq!(
            events[0].visible_to(Some(3)),
            Event::ResourceStolen {
                thief: 0,
                victim: 1,
                resource: None
            }
        );
    }

    #[test]
    fn steal_outside_the_steal_phase_is_wrong_phase() {
        let (mut game, _) = robber_game(3);
        give(&mut game, 1, cards([0, 0, 0, 0, 1]));
        assert_eq!(
            game.apply(0, Action::Steal { victim: 1 }),
            Err(GameError::WrongPhase)
        );
        game.phase = Phase::Main;
        assert_eq!(
            game.apply(0, Action::Steal { victim: 1 }),
            Err(GameError::WrongPhase)
        );
    }

    #[test]
    fn stolen_card_is_random_but_seeded() {
        let steal_with = |seed: u64| {
            let (mut game, tile) = robber_game(3);
            game.rng = rand::SeedableRng::seed_from_u64(seed);
            give(&mut game, 1, cards([1, 1, 1, 1, 1]));
            game.apply(0, Action::MoveRobber { tile }).unwrap();
            let events = game.apply(0, Action::Steal { victim: 1 }).unwrap();
            events[0].clone()
        };

        let kinds: std::collections::BTreeSet<String> = (0..40)
            .map(|seed| format!("{:?}", steal_with(seed)))
            .collect();
        assert!(kinds.len() >= 4, "{kinds:?}");
        assert_eq!(steal_with(7), steal_with(7));
    }

    #[test]
    fn a_seven_plays_through_discard_move_and_steal() {
        let (mut game, tile) = robber_game(5);
        give(&mut game, 1, cards([2, 2, 2, 2, 0])); // owes 4
        game.phase = Phase::Roll;

        let events = on_seven(&mut game, 0);
        assert!(matches!(
            events[0],
            Event::PhaseChanged {
                phase: Phase::Discard { .. }
            }
        ));
        game.apply(
            1,
            Action::Discard {
                resources: cards([1, 1, 1, 1, 0]),
            },
        )
        .unwrap();
        game.apply(0, Action::MoveRobber { tile }).unwrap();
        assert_eq!(game.legal_actions(0), vec![Action::Steal { victim: 1 }]);
        game.apply(0, Action::Steal { victim: 1 }).unwrap();

        assert_eq!(game.phase, Phase::Main);
        assert_eq!(hand(&game, 1).total(), 3);
        assert_eq!(hand(&game, 0).total(), 1);
    }
}
