use std::{collections::HashMap, fmt::format};

use async_trait::async_trait;
use futures_util::future::join_all;
use log::trace;
use serde_json::json;
use settler_island_game::game::GameSettings;
use tokio::sync::Mutex;

use crate::server::{
    lobby::game_lobby::GameLobbyAccess,
    message::error_codes,
    user::{UserData, UserId},
    user_connection::{self, UserConnection},
};

use super::MessageReaderProvider;

type UsersMessage = HashMap<UserId, UserData>;

pub struct LobbyMessage {
    group: String,
}

impl LobbyMessage {
    pub fn new() -> Self {
        LobbyMessage {
            group: "lobby".to_string(),
        }
    }

    async fn leave_lobby(&self, user_connection: &UserConnection) -> Result<(), String> {
        let mut game_state = user_connection.get_game_state().lock().await;
        let lobby_browser = &mut user_connection.get_server().lock().await.lobby_browser;

        if let Err(err) = game_state.leave_lobby(lobby_browser).await {
            let _ = user_connection.send_error(error_codes::NOT_IN_LOBBY).await;
            return Err("Failed to leave lobby".to_string());
        }

        match user_connection.send(&self.group, "left", json!({})).await {
            Ok(_) => Ok(()),
            Err(err) => Err(format!("Failed to send lobby left message \"{}\"", err)),
        }
    }

    async fn start_game(&self, user_connection: &UserConnection) -> Result<(), String> {
        let game_state = user_connection.get_game_state().lock().await;
        let lobby = match game_state.lobby.as_ref() {
            Some(lobby) => lobby,
            None => {
                let _ = user_connection.send_error(error_codes::NOT_IN_LOBBY).await;
                return Err("User cannot start game as the user is not in a lobby".to_string());
            }
        };

        if let Err(err) = lobby
            .lock()
            .await
            .start_game(GameSettings { players: 2 }, vec![])
            .await
        {
            return Err(format!("User could not start game \"{}\"", err));
        }

        Ok(())
    }

    async fn get_users(&self, user_connection: &UserConnection) -> Result<(), String> {
        trace!("Process get-users");
        let lobby = match user_connection.get_game_state().lock().await.lobby.as_ref() {
            Some(lobby) => lobby.clone(),
            None => {
                let _ = user_connection.send_error(error_codes::NOT_IN_LOBBY).await;
                return Err("User cannot start game as the user is not in a lobby".to_string());
            }
        };

        self.send_users(user_connection, &lobby).await;
        Ok(())
    }

    pub async fn send_users(
        &self,
        user_connection: &UserConnection,
        lobby: &GameLobbyAccess,
    ) -> Result<(), String> {
        let mut users = UsersMessage::new();

        let lobby = lobby.lock().await;

        let user_data_list: Vec<UserData> =
            join_all(lobby.get_users().iter().map(|user_entry| async {
                user_entry
                    .1
                    .get_game_state()
                    .lock()
                    .await
                    .user
                    .as_ref()
                    .unwrap()
                    .clone()
            }))
            .await;

        trace!(
            "Collected {} user(s) for lobby {}",
            user_data_list.len(),
            lobby.get_id()
        );

        user_data_list.into_iter().for_each(|user_data| {
            trace!("Collecting UserId={}", user_data.get_id());
            users.insert(user_data.get_id().clone(), user_data);
        });

        let users_value = match serde_json::to_value(users) {
            Ok(json_value) => json_value,
            Err(err) => return Err(err.to_string()),
        };

        match user_connection
            .send(self.get_group(), "users", users_value)
            .await
        {
            Ok(_) => Ok(()),
            Err(err) => Err(format!("Failed to send users message \"{}\"", err)),
        }
    }
}

#[async_trait]
impl MessageReaderProvider for LobbyMessage {
    fn get_group(&self) -> &String {
        &self.group
    }

    async fn call(
        &self,
        user_connection: &UserConnection,
        command: &str,
        json_message: &str,
    ) -> Result<(), String> {
        // registered
        if let None = user_connection.get_game_state().lock().await.user {
            let _ = user_connection
                .send_error(error_codes::NOT_REGISTERED)
                .await;
            return Err("User not registered".to_string());
        }

        if let None = user_connection.get_game_state().lock().await.lobby {
            let _ = user_connection.send_error(error_codes::NOT_IN_LOBBY).await;
            return Err("User not in lobby".to_string());
        }

        match command {
            "leave" => return self.leave_lobby(&user_connection).await,
            "start-game" => return self.start_game(&user_connection).await,
            "get-users" => return self.get_users(&user_connection).await,
            _ => (),
        }

        Err(format!("Command \"{}\" not found", command))
    }
}
