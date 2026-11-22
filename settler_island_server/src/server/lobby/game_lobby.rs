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
    Game, GameSettings,
};
use tokio::sync::Mutex;

use crate::server::{user::UserId, user_connection::UserConnection};

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
    ) -> Self {
        let mut users = HashMap::new();
        users.insert(owner_id.clone(), creator);

        GameLobby {
            id,
            name,
            password,
            player_count,
            owner_id,
            users,
            game: Mutex::new(None),
        }
    }

    pub fn get_id(&self) -> &String {
        &self.id
    }

    pub fn get_joined_user_count(&self) -> usize {
        self.users.len()
    }

    pub fn is_password(&self, password: &str) -> bool {
        self.password == password
    }

    pub async fn add_user(&mut self, user_connection: UserConnection) -> Result<(), String> {
        let user_id = user_connection
            .get_game_state()
            .lock()
            .await
            .user
            .as_ref()
            .unwrap()
            .get_id()
            .clone();

        if self.users.contains_key(&user_id) {
            return Err(format!("\"{}\" is already in lobby", user_id));
        }

        self.users.insert(user_id, user_connection);
        Ok(())
    }

    pub fn remove_user(&mut self, user_id: &UserId) -> Result<(), String> {
        if !self.users.contains_key(user_id) {
            return Err(format!("\"{}\" is not in lobby", user_id));
        }
        self.users.remove(user_id).unwrap();
        trace!("User \"{}\" removed from lobby \"{}\"", user_id, self.id);
        if self.users.is_empty() || user_id != &self.owner_id {
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

    pub fn get_users(&self) -> &HashMap<UserId, UserConnection> {
        &self.users
    }

    pub async fn start_game(
        &mut self,
        settings: GameSettings,
        _player_user_ids: Vec<UserId>,
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
            password_protected: !lobby.password.is_empty(),
        }
    }
}
