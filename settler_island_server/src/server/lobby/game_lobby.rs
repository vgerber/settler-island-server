use std::{collections::HashMap, sync::Arc};

use serde::Serialize;
use settler_island_game::game::{
    board::generator::base_board_generator::generate_board,
    state::{
        state_machine::{GameStateBox, StateMachine},
        states::{start_village_placement::StartVillagePlacement, start_road_placement::StartRoadPlacement},
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
    game: Option<Game>,
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
        owner: UserConnection,
    ) -> Self {
        let owner_id = owner
            .get_game_state()
            .lock()
            .await
            .user
            .as_ref()
            .unwrap()
            .get_id()
            .clone();
        let mut users = HashMap::new();
        users.insert(owner_id.clone(), owner);

        GameLobby {
            id: id,
            name: name,
            password: password,
            player_count: player_count,
            owner_id: owner_id,
            users: users,
            game: None,
        }
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

    pub fn has_password(&self) -> bool {
        return !self.password.is_empty();
    }

    pub fn is_password(&self, password: &str) -> bool {
        return self.password == password;
    }

    pub fn start_game(
        &mut self,
        settings: GameSettings,
        player_user_ids: Vec<UserId>,
    ) -> Result<(), String> {
        let board = match generate_board() {
            Ok(board) => board,
            Err(err) => return Err(format!("Failed to generated board \"{}\"", err)),
        };
        let states: Vec<GameStateBox> = vec![Box::new(StartVillagePlacement::new()), Box::new(StartRoadPlacement::new()), Box::new(x)];
        let start_state_id = states[0].get_id().to_string();

        let state_machine = StateMachine::from(states, start_state_id);

        self.game = Some(Game::from(board, settings, state_machine));
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
