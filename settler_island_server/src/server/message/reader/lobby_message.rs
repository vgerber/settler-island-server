use std::fmt::format;

use async_trait::async_trait;
use serde_json::json;
use settler_island_game::game::GameSettings;

use crate::server::{
    message::error_codes,
    user_connection::{self, UserConnection},
};

use super::MessageReaderProvider;

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
        user_connection.get_game_state().lock().await.lobby = None;

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
            _ => (),
        }

        Err(format!("Command \"{}\" not found", command))
    }
}
