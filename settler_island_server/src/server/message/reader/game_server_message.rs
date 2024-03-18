use async_trait::async_trait;
use futures_util::future::join_all;
use log::warn;
use serde::{Deserialize, Serialize};
use serde_json::{json, Error};
use settler_island_game::game;

use crate::server::{
    lobby::game_lobby::{GameLobbyAccess, GameLobbySummary},
    message::error_codes,
    user::UserData,
    user_connection::UserConnection,
};

use super::MessageReaderProvider;

#[derive(Deserialize)]
struct RegisterUserMessage {
    pub username: String,
}

#[derive(Deserialize)]
struct GetLobbiesMessage {
    pub page: u32,
    pub items_per_page: u32,
}

#[derive(Serialize)]
struct LobbiesMessage {
    pub page: u32,
    pub lobbies: Vec<GameLobbySummary>,
}

#[derive(Deserialize)]
struct JoinLobbyMessage {
    pub lobby_id: String,
    pub password: String,
}

#[derive(Deserialize)]
struct CreateLobbyMessage {
    pub lobby_name: String,
    pub password: String,
}

pub struct GameServerMessage {
    group: String,
}

impl GameServerMessage {
    pub fn new() -> Self {
        GameServerMessage {
            group: "server".to_string(),
        }
    }

    async fn register_user(
        &self,
        user_connection: &UserConnection,
        message: &str,
    ) -> Result<(), String> {
        let user_result: Result<RegisterUserMessage, Error> = serde_json::from_str(message);
        if user_result.is_err() {
            return Err(format!(
                "Failed to parse register user data \"{:?}\"",
                user_result.err()
            ));
        }
        if let Err(err) = user_connection
            .get_server()
            .lock()
            .await
            .register_user(&user_result.unwrap().username, user_connection)
            .await
        {
            return Err(err);
        }

        self.send_user(user_connection).await
    }

    async fn get_lobbies(
        &self,
        user_connection: &UserConnection,
        message: &str,
    ) -> Result<(), String> {
        let lobbies_request = match serde_json::from_str::<GetLobbiesMessage>(message) {
            Ok(request) => request,
            Err(err) => return Err(format!("Failed to parse get lobbies request \"{}\"", err)),
        };
        self.send_lobbies(user_connection, lobbies_request).await
    }

    async fn send_user(&self, user_connection: &UserConnection) -> Result<(), String> {
        let user = match user_connection.get_game_state().lock().await.user.clone() {
            Some(user) => user,
            None => return Err("User not found".to_string()),
        };

        let user_value = match serde_json::to_value(&user) {
            Ok(json_value) => json_value,
            Err(err) => return Err(err.to_string()),
        };

        match user_connection
            .send(self.get_group(), "user", user_value)
            .await
        {
            Ok(_) => Ok(()),
            Err(err) => Err(format!("Failed to send register message \"{}\"", err)),
        }
    }

    async fn send_lobbies(
        &self,
        user_connection: &UserConnection,
        lobbies_request: GetLobbiesMessage,
    ) -> Result<(), String> {
        let server = user_connection.get_server().lock().await;
        let lobbies = join_all(
            server
                .lobby_browser
                .get_lobby_page(
                    lobbies_request.page as usize,
                    lobbies_request.items_per_page as usize,
                )
                .into_iter()
                .map(|lobby| async move {
                    let locked_lobby = lobby.lock().await;
                    GameLobbySummary::from(&locked_lobby)
                }),
        )
        .await;

        let page_message = LobbiesMessage {
            page: lobbies_request.page,
            lobbies: lobbies,
        };

        let serialized_page_message = match serde_json::to_value(page_message) {
            Ok(value) => value,
            Err(err) => return Err(err.to_string()),
        };

        match user_connection
            .send(self.get_group(), "lobbies", serialized_page_message)
            .await
        {
            Ok(_) => Ok(()),
            Err(err) => Err(format!("Failed to send register message \"{}\"", err)),
        }
    }

    async fn send_lobby(&self, user_connection: &UserConnection) -> Result<(), String> {
        let lobby_access = &user_connection.get_game_state().lock().await;
        let lobby = match lobby_access.lobby.as_ref() {
            Some(lobby) => lobby.lock().await,
            None => {
                let _ = user_connection.send_error(error_codes::NOT_IN_LOBBY).await;
                return Err("User is not assigned to a lobby".to_string());
            }
        };

        let lobby_value = match serde_json::to_value(&GameLobbySummary::from(&lobby)) {
            Ok(json_value) => json_value,
            Err(err) => return Err(err.to_string()),
        };

        match user_connection
            .send(self.get_group(), "lobby", lobby_value)
            .await
        {
            Ok(_) => Ok(()),
            Err(err) => Err(format!("Failed to send lobby message \"{}\"", err)),
        }
    }

    async fn join_lobby(
        &self,
        user_connection: &UserConnection,
        message: &str,
    ) -> Result<(), String> {
        let join_lobby_message = match serde_json::from_str::<JoinLobbyMessage>(message) {
            Ok(request) => request,
            Err(err) => return Err(format!("Failed to parse join lobby request \"{}\"", err)),
        };

        if let Err(join_error) = user_connection
            .get_server()
            .lock()
            .await
            .lobby_browser
            .join_lobby(
                user_connection,
                &join_lobby_message.lobby_id,
                &join_lobby_message.password,
            )
            .await
        {
            user_connection
                .send_error(join_error)
                .await
                .expect("Send error failed");
            return Err(format!("join lobby failed \"{}\"", join_error.0));
        }

        self.send_lobby(user_connection).await
    }

    async fn create_game_lobby(
        &self,
        user_connection: &UserConnection,
        message: &str,
    ) -> Result<(), String> {
        let creation_message = match serde_json::from_str::<CreateLobbyMessage>(message) {
            Ok(message) => message,
            Err(err) => return Err(format!("Failed to parse create lobby message \"{}\"", err)),
        };

        if let Err(err) = user_connection
            .get_server()
            .lock()
            .await
            .lobby_browser
            .create_and_own_lobby(
                &user_connection,
                creation_message.lobby_name,
                creation_message.password,
                4,
            )
            .await
        {
            return Err(err);
        }

        self.send_lobby(user_connection).await
    }
}

#[async_trait]
impl MessageReaderProvider for GameServerMessage {
    fn get_group(&self) -> &String {
        &self.group
    }

    async fn call(
        &self,
        user_connection: &UserConnection,
        command: &str,
        json_message: &str,
    ) -> Result<(), String> {
        // unregistered
        match command {
            "register" => return self.register_user(&user_connection, json_message).await,
            _ => (),
        }

        // registered
        if let None = user_connection.get_game_state().lock().await.user {
            let _ = user_connection
                .send_error(error_codes::NOT_REGISTERED)
                .await;
            return Err("User not registered".to_string());
        }

        match command {
            "get-lobbies" => return self.get_lobbies(&user_connection, json_message).await,
            "join-lobby" => return self.join_lobby(&user_connection, json_message).await,
            "get-user" => return self.send_user(&user_connection).await,
            "get-lobby" => return self.send_lobby(&user_connection).await,
            "create-lobby" => return self.create_game_lobby(&user_connection, json_message).await,
            _ => (),
        }

        Err(format!("Command \"{}\" not found", command))
    }
}
