use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

use crate::board::Board;
use crate::game::{DevelopmentCard, Game, Seat};
use crate::phase::Phase;
use crate::resource::ResourceCounts;
use crate::rules::scoring;

/// What one seat (or a spectator) may see of a game.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct PlayerView {
    pub board: Board,
    pub phase: Phase,
    pub current: Seat,
    pub turn_number: u32,
    pub bank: ResourceCounts,
    pub development_cards_left: u8,
    pub longest_road: Option<Seat>,
    pub largest_army: Option<Seat>,
    pub players: Vec<PublicPlayerView>,
    /// `None` for spectators.
    pub own: Option<OwnView>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub struct PublicPlayerView {
    pub seat: Seat,
    pub resource_count: u8,
    pub development_card_count: u8,
    pub roads_left: u8,
    pub settlements_left: u8,
    pub cities_left: u8,
    pub knights_played: u8,
    /// Without hidden victory point cards.
    pub points: u8,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub struct OwnView {
    pub seat: Seat,
    pub hand: ResourceCounts,
    pub development_cards: Vec<DevelopmentCard>,
}

impl PlayerView {
    pub(crate) fn of(game: &Game, viewer: Option<Seat>) -> PlayerView {
        let players = game
            .players
            .iter()
            .enumerate()
            .map(|(index, player)| {
                let seat = index as Seat;
                PublicPlayerView {
                    seat,
                    resource_count: player.hand.total() as u8,
                    development_card_count: player.development_cards.len() as u8,
                    roads_left: player.roads_left,
                    settlements_left: player.settlements_left,
                    cities_left: player.cities_left,
                    knights_played: player.knights_played,
                    points: scoring::public_points(game, seat),
                }
            })
            .collect();
        let own = viewer.and_then(|seat| {
            let player = game.players.get(usize::from(seat))?;
            Some(OwnView {
                seat,
                hand: player.hand,
                development_cards: player.development_cards.clone(),
            })
        });

        PlayerView {
            board: game.board.clone(),
            phase: game.phase.clone(),
            current: game.current,
            turn_number: game.turn_number,
            bank: game.bank,
            development_cards_left: game.deck.len() as u8,
            longest_road: game.longest_road,
            largest_army: game.largest_army,
            players,
            own,
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::resource::{Resource, ResourceCounts};
    use crate::rules::test_support::{after_setup, give};

    #[test]
    fn view_shows_only_the_own_hand() {
        let mut game = after_setup(3, 14);
        give(&mut game, 2, ResourceCounts::single(Resource::Ore, 3));

        let own = game.view(Some(2)).own.unwrap();
        let spectator = game.view(None);

        assert_eq!(own.hand, game.players[2].hand);
        assert_eq!(game.view(Some(1)).own.unwrap().hand, game.players[1].hand);
        assert!(spectator.own.is_none());
        assert_eq!(
            u32::from(spectator.players[2].resource_count),
            game.players[2].hand.total()
        );
        assert_eq!(spectator.players[0].points, 2);
    }
}
