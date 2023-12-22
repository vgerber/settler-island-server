use std::cell::RefCell;

use self::{
    board::GameBoard,
    player::{Player, PlayerId},
    state::state_machine::StateMachine,
    trade::TradeOffer,
};

pub mod board;
pub mod color;
pub mod player;
pub mod state;
pub mod trade;

pub enum GameError {
    ActionFailed,
    ActionDataInvalid,
    ActionNotAllowed,
    NotPlayerTurn,
    InvalidLocation,
    NotEnoughResources,
}

#[derive(Debug, Clone)]
pub struct GameSettings {
    pub players: u8,
}

pub struct Game {
    board: GameBoard,
    settings: GameSettings,
    state_machine: RefCell<StateMachine>,
    current_player_index: usize,
    players: Vec<RefCell<Player>>,
    active_trade_offer: RefCell<Option<TradeOffer>>,
}

impl Game {
    pub fn from(board: GameBoard, settings: GameSettings, state_machine: StateMachine) -> Self {
        Game {
            board: board,
            settings: settings,
            state_machine: RefCell::new(state_machine),
            current_player_index: 0,
            players: vec![],
            active_trade_offer: RefCell::new(None),
        }
    }

    pub fn get_board(&self) -> &GameBoard {
        &self.board
    }

    pub fn get_board_mut(&mut self) -> &mut GameBoard {
        &mut self.board
    }

    pub fn get_current_player_index(&self) -> &usize {
        &self.current_player_index
    }

    pub fn get_state_machine(&self) -> &RefCell<StateMachine> {
        &self.state_machine
    }

    pub fn end_turn(&mut self) {
        self.current_player_index = (self.current_player_index + 1) % self.players.len();
    }

    pub fn is_player_turn(&self, player_id: &PlayerId) -> bool {
        self.players[self.current_player_index].borrow().get_id() == player_id
    }

    pub fn get_player(&self, player_id: PlayerId) -> &RefCell<Player> {
        &self.players[player_id]
    }

    pub fn get_players(&self) -> &Vec<RefCell<Player>> {
        &self.players
    }

    pub fn get_player_count(&self) -> usize {
        self.players.len()
    }

    pub fn get_current_player(&self) -> &RefCell<Player> {
        &self.players[self.current_player_index]
    }

    pub fn create_trade_offer(&mut self, offer: TradeOffer) {
        self.active_trade_offer = RefCell::new(Some(offer));
    }

    pub fn get_trade_offer(&self) -> &RefCell<Option<TradeOffer>> {
        &self.active_trade_offer
    }

    pub fn cancel_trade_offer(&self) {
        self.active_trade_offer.borrow_mut().take();
    }

    pub fn complete_trade_offer(&self) {
        self.active_trade_offer.borrow_mut().take();
    }
}
