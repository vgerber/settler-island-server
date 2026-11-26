use crate::action::Action;
use crate::board::EdgeId;
use crate::error::GameError;
use crate::event::Event;
use crate::game::{DevelopmentCard, Game, Holder, Seat};
use crate::phase::Phase;
use crate::resource::{Resource, ResourceCounts};
use crate::rules::building;
use crate::rules::purchase::Purchase;

const FREE_ROADS: u8 = 2;

pub(crate) fn buy(game: &mut Game, seat: Seat) -> Result<Vec<Event>, GameError> {
    check_buy(game, seat)?;
    let card = *game.deck.last().ok_or(GameError::NoCard)?;
    let paid = game.pay_to_bank(seat, Purchase::DevelopmentCard.cost())?;
    // The deck was checked above and paying resolved the seat, so nothing below can fail.
    game.deck.truncate(game.deck.len().saturating_sub(1));
    game.player_mut(seat)?.new_development_cards.push(card);
    Ok(vec![
        paid,
        Event::DevelopmentCardBought {
            seat,
            card: Some(card),
        },
    ])
}

pub(crate) fn play_knight(game: &mut Game, seat: Seat) -> Result<Vec<Event>, GameError> {
    check_play(game, seat, DevelopmentCard::Knight)?;
    let mut events = vec![spend_card(game, seat, DevelopmentCard::Knight)?];
    let player = game.player_mut(seat)?;
    player.knights_played = player.knights_played.saturating_add(1);
    events.push(game.enter(Phase::MoveRobber { then_steal: true }));
    Ok(events)
}

pub(crate) fn play_road_building(game: &mut Game, seat: Seat) -> Result<Vec<Event>, GameError> {
    check_play(game, seat, DevelopmentCard::RoadBuilding)?;
    let mut events = vec![spend_card(game, seat, DevelopmentCard::RoadBuilding)?];
    let phase = road_phase(game, seat, FREE_ROADS);
    events.push(game.enter(phase));
    Ok(events)
}

pub(crate) fn play_year_of_plenty(
    game: &mut Game,
    seat: Seat,
    first: Resource,
    second: Resource,
) -> Result<Vec<Event>, GameError> {
    check_play(game, seat, DevelopmentCard::YearOfPlenty)?;
    let wanted = year_of_plenty_take(game, first, second)?;
    let mut events = vec![spend_card(game, seat, DevelopmentCard::YearOfPlenty)?];
    game.move_resources(Holder::Bank, Holder::Seat(seat), wanted)?;
    events.push(Event::YearOfPlentyTaken {
        seat,
        resources: wanted,
    });
    Ok(events)
}

pub(crate) fn play_monopoly(
    game: &mut Game,
    seat: Seat,
    resource: Resource,
) -> Result<Vec<Event>, GameError> {
    check_play(game, seat, DevelopmentCard::Monopoly)?;
    let held_before = game.player(seat)?.hand.get(resource);
    let taken = (0..game.settings.seats)
        .filter(|other| *other != seat)
        .map(|other| {
            let held = game.player(other)?.hand.get(resource);
            Ok((other, ResourceCounts::single(resource, held)))
        })
        .collect::<Result<Vec<_>, GameError>>()?;
    let mut events = vec![spend_card(game, seat, DevelopmentCard::Monopoly)?];
    for (other, amount) in taken {
        game.move_resources(Holder::Seat(other), Holder::Seat(seat), amount)?;
    }
    let amount = game
        .player(seat)?
        .hand
        .get(resource)
        .saturating_sub(held_before);
    events.push(Event::MonopolyTaken {
        seat,
        resource,
        amount,
    });
    Ok(events)
}

/// A free road in `Phase::RoadBuilding`.
pub(crate) fn build_free_road(
    game: &mut Game,
    seat: Seat,
    edge: EdgeId,
) -> Result<Vec<Event>, GameError> {
    let Phase::RoadBuilding { roads_left } = game.phase else {
        return Err(GameError::WrongPhase);
    };
    check_free_road(game, seat, edge)?;
    let mut events = vec![building::place_road(game, seat, edge)];
    let phase = road_phase(game, seat, roads_left.saturating_sub(1));
    events.push(game.enter(phase));
    Ok(events)
}

/// Bought cards become playable and the one-card limit resets.
pub(crate) fn on_turn_end(game: &mut Game, seat: Seat) -> Result<(), GameError> {
    let player = game.player_mut(seat)?;
    let bought = std::mem::take(&mut player.new_development_cards);
    player.development_cards.extend(bought);
    player.played_development_card_this_turn = false;
    Ok(())
}

/// A knight before rolling.
pub(crate) fn legal_before_roll(game: &Game, seat: Seat) -> Vec<Action> {
    if check_play(game, seat, DevelopmentCard::Knight).is_ok() {
        return vec![Action::PlayKnight];
    }
    Vec::new()
}

/// Buy and play in `Phase::Main`.
pub(crate) fn legal_main(game: &Game, seat: Seat) -> Vec<Action> {
    let playable = |card| check_play(game, seat, card).is_ok();
    let mut actions = Vec::new();
    if check_buy(game, seat).is_ok() {
        actions.push(Action::BuyDevelopmentCard);
    }
    if playable(DevelopmentCard::Knight) {
        actions.push(Action::PlayKnight);
    }
    if playable(DevelopmentCard::RoadBuilding) {
        actions.push(Action::PlayRoadBuilding);
    }
    if playable(DevelopmentCard::YearOfPlenty) {
        actions.extend(year_of_plenty_choices(game));
    }
    if playable(DevelopmentCard::Monopoly) {
        actions.extend(
            Resource::ALL
                .into_iter()
                .map(|resource| Action::PlayMonopoly { resource }),
        );
    }
    actions
}

/// Free roads in `Phase::RoadBuilding`.
pub(crate) fn legal_free_roads(game: &Game, seat: Seat) -> Vec<Action> {
    game.board
        .edge_ids()
        .filter(|edge| check_free_road(game, seat, *edge).is_ok())
        .map(|edge| Action::BuildRoad { edge })
        .collect()
}

fn check_buy(game: &Game, seat: Seat) -> Result<(), GameError> {
    game.require_main_turn(seat)?;
    if game.deck.is_empty() {
        return Err(GameError::NoCard);
    }
    if !game
        .player(seat)?
        .hand
        .contains(&Purchase::DevelopmentCard.cost())
    {
        return Err(GameError::NotEnoughResources);
    }
    Ok(())
}

/// Turn, phase, one card per turn, and the card was bought on an earlier turn.
fn check_play(game: &Game, seat: Seat, card: DevelopmentCard) -> Result<(), GameError> {
    game.require_turn(seat)?;
    let before_roll = card == DevelopmentCard::Knight && game.phase == Phase::Roll;
    if game.phase != Phase::Main && !before_roll {
        return Err(GameError::WrongPhase);
    }
    let player = game.player(seat)?;
    if !player.development_cards.contains(&card) {
        let bought_now = player.new_development_cards.contains(&card);
        return Err(if bought_now {
            GameError::CardNotPlayable
        } else {
            GameError::NoCard
        });
    }
    if player.played_development_card_this_turn {
        return Err(GameError::CardNotPlayable);
    }
    Ok(())
}

fn spend_card(game: &mut Game, seat: Seat, card: DevelopmentCard) -> Result<Event, GameError> {
    let player = game.player_mut(seat)?;
    let position = player
        .development_cards
        .iter()
        .position(|held| *held == card)
        .ok_or(GameError::NoCard)?;
    player.development_cards.remove(position);
    player.played_development_card_this_turn = true;
    Ok(Event::DevelopmentCardPlayed { seat, card })
}

/// The two cards as one amount, when the bank holds both.
fn year_of_plenty_take(
    game: &Game,
    first: Resource,
    second: Resource,
) -> Result<ResourceCounts, GameError> {
    let wanted = ResourceCounts::single(first, 1)
        .checked_add(&ResourceCounts::single(second, 1))
        .ok_or(GameError::BankEmpty)?;
    if !game.bank.contains(&wanted) {
        return Err(GameError::BankEmpty);
    }
    Ok(wanted)
}

/// Unordered pairs, since taking (a, b) equals taking (b, a).
fn year_of_plenty_choices(game: &Game) -> Vec<Action> {
    let mut actions = Vec::new();
    for (position, first) in Resource::ALL.into_iter().enumerate() {
        for second in Resource::ALL.into_iter().skip(position) {
            if year_of_plenty_take(game, first, second).is_ok() {
                actions.push(Action::PlayYearOfPlenty { first, second });
            }
        }
    }
    actions
}

/// Continues road building while pieces and legal edges remain, else back to `Main`.
fn road_phase(game: &Game, seat: Seat, roads_left: u8) -> Phase {
    let can_continue = roads_left > 0
        && game
            .board
            .edge_ids()
            .any(|edge| building::check_road_placement(game, seat, edge).is_ok());
    if can_continue {
        return Phase::RoadBuilding { roads_left };
    }
    Phase::Main
}

fn check_free_road(game: &Game, seat: Seat, edge: EdgeId) -> Result<(), GameError> {
    game.require_turn(seat)?;
    if !matches!(game.phase, Phase::RoadBuilding { .. }) {
        return Err(GameError::WrongPhase);
    }
    building::check_road_placement(game, seat, edge)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rules::test_support::{after_setup, give, main_phase_game};

    fn hold(game: &mut Game, seat: Seat, card: DevelopmentCard) {
        game.players[usize::from(seat)].development_cards.push(card);
    }

    fn resource_total(game: &Game) -> u32 {
        game.bank.total() + game.players.iter().map(|p| p.hand.total()).sum::<u32>()
    }

    #[test]
    fn buy_pays_takes_the_top_card_and_hides_it_from_others() {
        let mut game = main_phase_game(3, 4);
        let top = *game.deck.last().unwrap();
        give(&mut game, 0, ResourceCounts::new([0, 0, 1, 1, 1]));

        let events = game.apply(0, Action::BuyDevelopmentCard).unwrap();

        assert_eq!(game.players[0].hand, ResourceCounts::default());
        assert_eq!(game.players[0].new_development_cards, vec![top]);
        assert_eq!(game.deck.len(), 24);
        let bought = events.last().unwrap();
        assert_eq!(bought.visible_to(Some(0)), *bought);
        assert_eq!(
            bought.visible_to(Some(1)),
            Event::DevelopmentCardBought {
                seat: 0,
                card: None
            }
        );
        assert_eq!(resource_total(&game), 95);

        let before = game.clone();
        assert_eq!(
            game.apply(0, Action::BuyDevelopmentCard),
            Err(GameError::NotEnoughResources)
        );
        assert_eq!(game, before);
    }

    #[test]
    fn the_whole_deck_can_be_bought_and_then_buying_fails() {
        let mut game = main_phase_game(3, 4);
        for _ in 0..25 {
            give(&mut game, 0, Purchase::DevelopmentCard.cost());
            game.apply(0, Action::BuyDevelopmentCard).unwrap();
        }
        let count = |card| {
            game.players[0]
                .new_development_cards
                .iter()
                .filter(|held| **held == card)
                .count()
        };
        assert_eq!(count(DevelopmentCard::Knight), 14);
        assert_eq!(count(DevelopmentCard::VictoryPoint), 5);
        assert_eq!(count(DevelopmentCard::RoadBuilding), 2);

        give(&mut game, 0, Purchase::DevelopmentCard.cost());
        let before = game.clone();
        assert_eq!(
            game.apply(0, Action::BuyDevelopmentCard),
            Err(GameError::NoCard)
        );
        assert_eq!(game, before);
        assert!(!game.legal_actions(0).contains(&Action::BuyDevelopmentCard));
    }

    #[test]
    fn a_card_bought_this_turn_is_playable_from_the_next_turn() {
        let mut game = main_phase_game(3, 4);
        give(&mut game, 0, Purchase::DevelopmentCard.cost());
        game.deck.push(DevelopmentCard::Knight);
        game.apply(0, Action::BuyDevelopmentCard).unwrap();

        let before = game.clone();
        assert_eq!(
            game.apply(0, Action::PlayKnight),
            Err(GameError::CardNotPlayable)
        );
        assert_eq!(game, before);
        assert!(!game.legal_actions(0).contains(&Action::PlayKnight));

        game.apply(0, Action::EndTurn).unwrap();
        assert_eq!(game.players[0].development_cards.len(), 1);
        assert!(game.players[0].new_development_cards.is_empty());
        game.current = 0;
        game.phase = Phase::Main;
        assert!(game.legal_actions(0).contains(&Action::PlayKnight));
    }

    #[test]
    fn only_one_development_card_per_turn_until_the_turn_ends() {
        let mut game = main_phase_game(3, 4);
        hold(&mut game, 0, DevelopmentCard::Monopoly);
        hold(&mut game, 0, DevelopmentCard::Knight);
        let monopoly = Action::PlayMonopoly {
            resource: Resource::Wood,
        };
        game.apply(0, monopoly).unwrap();

        let before = game.clone();
        assert_eq!(
            game.apply(0, Action::PlayKnight),
            Err(GameError::CardNotPlayable)
        );
        assert_eq!(game, before);
        assert!(game
            .legal_actions(0)
            .iter()
            .all(|action| !matches!(action, Action::PlayKnight | Action::PlayMonopoly { .. })));

        game.apply(0, Action::EndTurn).unwrap();
        assert!(!game.players[0].played_development_card_this_turn);
    }

    #[test]
    fn knight_moves_the_robber_and_counts_for_the_army() {
        let mut game = main_phase_game(3, 4);
        assert_eq!(game.apply(0, Action::PlayKnight), Err(GameError::NoCard));
        hold(&mut game, 0, DevelopmentCard::Knight);

        let events = game.apply(0, Action::PlayKnight).unwrap();

        assert_eq!(
            events[0],
            Event::DevelopmentCardPlayed {
                seat: 0,
                card: DevelopmentCard::Knight
            }
        );
        assert_eq!(game.phase, Phase::MoveRobber { then_steal: true });
        assert_eq!(game.players[0].knights_played, 1);
        assert!(game.players[0].development_cards.is_empty());
    }

    #[test]
    fn only_a_knight_may_be_played_before_rolling() {
        let mut game = after_setup(4, 3);
        hold(&mut game, 0, DevelopmentCard::Monopoly);
        hold(&mut game, 0, DevelopmentCard::Knight);
        assert_eq!(game.phase, Phase::Roll);

        assert_eq!(
            game.apply(
                0,
                Action::PlayMonopoly {
                    resource: Resource::Ore
                }
            ),
            Err(GameError::WrongPhase)
        );
        assert_eq!(
            game.legal_actions(0),
            vec![Action::RollDice, Action::PlayKnight]
        );
        game.apply(0, Action::PlayKnight).unwrap();
        assert_eq!(game.phase, Phase::MoveRobber { then_steal: true });
    }

    #[test]
    fn road_building_places_two_free_roads_that_must_connect() {
        let mut game = main_phase_game(4, 5);
        hold(&mut game, 0, DevelopmentCard::RoadBuilding);
        game.apply(0, Action::PlayRoadBuilding).unwrap();
        assert_eq!(game.phase, Phase::RoadBuilding { roads_left: 2 });
        let roads_before = game.players[0].roads_left;

        let legal = game.legal_actions(0);
        assert!(!legal.is_empty());
        let disconnected = game
            .board
            .edge_ids()
            .find(|edge| !legal.contains(&Action::BuildRoad { edge: *edge }))
            .unwrap();
        let before = game.clone();
        assert!(game
            .apply(0, Action::BuildRoad { edge: disconnected })
            .is_err());
        assert_eq!(game, before);

        game.apply(0, legal[0].clone()).unwrap();
        assert_eq!(game.phase, Phase::RoadBuilding { roads_left: 1 });
        let second = game.legal_actions(0)[0].clone();
        game.apply(0, second).unwrap();

        assert_eq!(game.phase, Phase::Main);
        assert_eq!(game.players[0].roads_left, roads_before - 2);
        assert_eq!(game.players[0].hand, ResourceCounts::default());
        assert_eq!(game.bank, ResourceCounts::new([19; 5]));
    }

    #[test]
    fn road_building_ends_early_when_pieces_run_out() {
        let mut game = main_phase_game(4, 5);
        hold(&mut game, 0, DevelopmentCard::RoadBuilding);
        game.players[0].roads_left = 1;
        game.apply(0, Action::PlayRoadBuilding).unwrap();
        assert_eq!(game.phase, Phase::RoadBuilding { roads_left: 2 });

        let road = game.legal_actions(0)[0].clone();
        game.apply(0, road).unwrap();

        assert_eq!(game.phase, Phase::Main);
        assert_eq!(game.players[0].roads_left, 0);
    }

    #[test]
    fn road_building_without_pieces_is_spent_and_skipped() {
        let mut game = main_phase_game(4, 5);
        hold(&mut game, 0, DevelopmentCard::RoadBuilding);
        game.players[0].roads_left = 0;

        game.apply(0, Action::PlayRoadBuilding).unwrap();

        assert_eq!(game.phase, Phase::Main);
        assert!(game.players[0].played_development_card_this_turn);
    }

    #[test]
    fn year_of_plenty_takes_two_cards_from_the_bank() {
        let mut game = main_phase_game(3, 4);
        hold(&mut game, 0, DevelopmentCard::YearOfPlenty);

        game.apply(
            0,
            Action::PlayYearOfPlenty {
                first: Resource::Ore,
                second: Resource::Ore,
            },
        )
        .unwrap();

        assert_eq!(game.players[0].hand, ResourceCounts::new([0, 0, 0, 0, 2]));
        assert_eq!(game.bank.get(Resource::Ore), 17);
        assert_eq!(resource_total(&game), 95);
    }

    #[test]
    fn year_of_plenty_needs_every_card_in_the_bank() {
        let mut game = main_phase_game(3, 4);
        hold(&mut game, 0, DevelopmentCard::YearOfPlenty);
        give(&mut game, 1, ResourceCounts::new([0, 18, 0, 0, 19]));
        let twice = Action::PlayYearOfPlenty {
            first: Resource::Wood,
            second: Resource::Wood,
        };
        let empty = Action::PlayYearOfPlenty {
            first: Resource::Clay,
            second: Resource::Ore,
        };

        let before = game.clone();
        assert_eq!(game.apply(0, twice.clone()), Err(GameError::BankEmpty));
        assert_eq!(game.apply(0, empty.clone()), Err(GameError::BankEmpty));
        assert_eq!(game, before);
        let legal = game.legal_actions(0);
        assert!(!legal.contains(&twice) && !legal.contains(&empty));

        let one_each = Action::PlayYearOfPlenty {
            first: Resource::Clay,
            second: Resource::Wood,
        };
        assert!(legal.contains(&one_each));
        game.apply(0, one_each).unwrap();
        assert_eq!(game.bank.get(Resource::Wood), 0);
    }

    #[test]
    fn monopoly_takes_the_resource_from_every_other_seat() {
        let mut game = main_phase_game(4, 4);
        hold(&mut game, 0, DevelopmentCard::Monopoly);
        give(&mut game, 0, ResourceCounts::new([0, 1, 0, 0, 0]));
        give(&mut game, 1, ResourceCounts::new([2, 3, 0, 0, 0]));
        give(&mut game, 2, ResourceCounts::new([0, 2, 1, 0, 0]));

        let events = game
            .apply(
                0,
                Action::PlayMonopoly {
                    resource: Resource::Wood,
                },
            )
            .unwrap();

        assert_eq!(game.players[0].hand, ResourceCounts::new([0, 6, 0, 0, 0]));
        assert_eq!(game.players[1].hand, ResourceCounts::new([2, 0, 0, 0, 0]));
        assert_eq!(game.players[2].hand, ResourceCounts::new([0, 0, 1, 0, 0]));
        assert_eq!(
            events.last(),
            Some(&Event::MonopolyTaken {
                seat: 0,
                resource: Resource::Wood,
                amount: 5
            })
        );
        assert_eq!(resource_total(&game), 95);
    }

    /// Rich hands make a rule that pays, spends or draws before a failing step visible.
    #[test]
    fn failed_development_actions_leave_the_game_unchanged() {
        let mut rich = main_phase_game(4, 6);
        for seat in 0..4 {
            give(&mut rich, seat, ResourceCounts::new([4, 4, 4, 4, 4]));
        }
        let mut empty_deck = rich.clone();
        empty_deck.deck.clear();
        let mut empty_bank = rich.clone();
        hold(&mut empty_bank, 0, DevelopmentCard::YearOfPlenty);
        empty_bank.bank = ResourceCounts::default();
        let mut bought_now = rich.clone();
        bought_now.players[0]
            .new_development_cards
            .extend([DevelopmentCard::Knight, DevelopmentCard::Monopoly]);
        let mut played = rich.clone();
        hold(&mut played, 0, DevelopmentCard::Monopoly);
        played.players[0].played_development_card_this_turn = true;
        let mut no_free_road = rich.clone();
        no_free_road.phase = Phase::RoadBuilding { roads_left: 2 };
        let actions = [
            Action::BuyDevelopmentCard,
            Action::PlayKnight,
            Action::PlayRoadBuilding,
            Action::PlayYearOfPlenty {
                first: Resource::Ore,
                second: Resource::Wood,
            },
            Action::PlayMonopoly {
                resource: Resource::Wood,
            },
            Action::BuildRoad {
                edge: crate::board::EdgeId(0),
            },
        ];

        let mut rejected = 0;
        for game in [empty_deck, empty_bank, bought_now, played, no_free_road] {
            for seat in 0..4 {
                for action in &actions {
                    let mut attempt = game.clone();
                    if attempt.apply(seat, action.clone()).is_err() {
                        rejected += 1;
                        assert_eq!(attempt, game, "seat {seat} {action:?}");
                    }
                }
            }
        }
        assert!(rejected > 100);
    }

    #[test]
    fn victory_point_cards_are_never_offered_to_play() {
        let mut game = main_phase_game(3, 4);
        hold(&mut game, 0, DevelopmentCard::VictoryPoint);

        assert_eq!(game.legal_actions(0), vec![Action::EndTurn]);
    }
}
