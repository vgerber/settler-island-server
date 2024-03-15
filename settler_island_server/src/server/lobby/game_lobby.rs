use std::{collections::HashMap, sync::Arc};

use log::trace;
use serde::Serialize;
use settler_island_game::game::{
    board::generator::base_board_generator::generate_board,
    state::{
        state_machine::{GameStateT, StateMachine},
        states::{
            start_road_placement::StartRoadPlacement,
            start_village_placement::StartVillagePlacement,
        },
    },
    Game, GameError, GameSettings,
};
use tokio::sync::Mutex;

use crate::server::{
    error::ServerError,
    user::{self, UserId},
    user_connection::UserConnection,
};

pub type GameLobbyAccess = Arc<Mutex<GameLobby>>;

pub struct GameLobby {
    id: String,
    name: String,
    password: String,
    player_count: u32,
    owner_id: UserId,
    users: HashMap<UserId, UserConnection>,
    game: Mutex<Option<Game>>,
}

#[derive(Serialize, Debug)]
pub struct GameLobbySummary {
    id: String,
    name: String,
    player_count: u32,
    password_protected: bool,
}

impl GameLobby {
    pub async fn from(
        id: String,
        name: String,
        password: String,
        player_count: u32,
        creator: UserConnection,
        owner_id: UserId,
    ) -> Result<Self, ServerError> {
        let mut users = HashMap::new();
        users.insert(owner_id.clone(), creator);

        Ok(GameLobby {
            id: id,
            name: name,
            password: password,
            player_count: player_count,
            owner_id: owner_id,
            users: users,
            game: Mutex::new(None),
        })
    }

    pub fn get_id(&self) -> &String {
        return &self.id;
    }

    pub fn get_name(&self) -> &String {
        return &self.name;
    }

    pub fn get_player_count(&self) -> &u32 {
        return &self.player_count;
    }

    pub fn get_joined_user_count(&self) -> usize {
        return self.users.len();
    }

    pub fn has_password(&self) -> bool {
        return !self.password.is_empty();
    }

    pub fn is_password(&self, password: &str) -> bool {
        return self.password == password;
    }

    pub fn remove_user(&mut self, user_id: &UserId) -> Result<(), String> {
        if !self.users.contains_key(user_id) {
            return Err(format!("\"{}\" is not in lobby", user_id));
        }
        self.users.remove(user_id).unwrap();
        trace!("User \"{}\" removed from lobby \"{}\"", user_id, self.id);
        if self.users.len() == 0 || user_id != &self.owner_id {
            return Ok(());
        }

        // change owner if user is not the last user
        self.owner_id = self.users.keys().next().unwrap().clone();
        trace!(
            "Changed lobby \"{}\" owner to \"{}\"",
            self.id,
            self.owner_id
        );

        Ok(())
    }

    pub async fn start_game(
        &mut self,
        settings: GameSettings,
        player_user_ids: Vec<UserId>,
    ) -> Result<(), String> {
        let board = match generate_board() {
            Ok(board) => board,
            Err(err) => return Err(format!("Failed to generated board \"{}\"", err)),
        };
        let states: Vec<GameStateT> = vec![
            Box::new(StartVillagePlacement::new()),
            Box::new(StartRoadPlacement::new()),
        ];
        let start_state_id = states[0].get_id().to_string();

        let state_machine = StateMachine::from(states, start_state_id);

        self.game
            .lock()
            .await
            .replace(Game::from(board, settings, state_machine));
        Ok(())
    }
}

impl GameLobbySummary {
    pub fn from(lobby: &GameLobby) -> Self {
        GameLobbySummary {
            id: lobby.id.clone(),
            name: lobby.name.clone(),
            player_count: lobby.player_count,
            password_protected: lobby.password.len() > 0,
        }
    }
}
