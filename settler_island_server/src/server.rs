use std::{collections::HashMap, sync::Arc};

use log::{debug, info};
use tokio::sync::Mutex;
use uuid::Uuid;

use crate::server::user::UserData;

use self::{
    lobby::lobby_browser::LobbyBrowser,
    user::{ServerUser, UserId},
    user_connection::UserConnection,
};

pub mod error;
pub mod lobby;
pub mod message;
pub mod user;
pub mod user_connection;

pub type GameServerAccess = Arc<Mutex<GameServer>>;

pub struct GameServer {
    lobby_browser: LobbyBrowser,
    users: Mutex<HashMap<UserId, UserConnection>>,
}

impl GameServer {
    pub fn new() -> GameServerAccess {
        Arc::new(Mutex::new(GameServer {
            lobby_browser: LobbyBrowser::new(),
            users: Mutex::new(HashMap::new()),
        }))
    }

    pub async fn register_user(
        &mut self,
        username: &str,
        user_connection: &UserConnection,
    ) -> Result<(), String> {
        let mut users = self.users.lock().await;
        if let Some(user) = user_connection.get_game_state().lock().await.user.as_ref() {
            if users.contains_key(user.get_id()) {
                return Err(format!("{:?} user is already registered", user));
            }
        }

        let id = Uuid::new_v4().as_simple().to_string();
        let user = UserData::from(&id, username);

        if users.contains_key(&id) {
            return Err(format!("Failed to register user with {:?}", user));
        }

        users.insert(id.to_string(), user_connection.clone());
        debug!("Registered {:?}", user);
        user_connection.get_game_state().lock().await.user = Some(user);

        Ok(())
    }

    pub async fn unregister_user(&mut self, id: &UserId) -> Result<(), String> {
        debug!("Unregister {} {}", id, self.users.try_lock().is_ok());
        let users = self.users.lock().await;
        let user_connection = match users.get(id) {
            None => return Err(String::from("User not found")),
            Some(user_connection) => user_connection,
        };
        let mut game_state = user_connection.get_game_state().lock().await;
        if let Some(lobby) = game_state.lobby.clone() {
            self.lobby_browser.leave_lobby(id, lobby).await;
        }
        game_state.user = None;
        Ok(())
    }
}
