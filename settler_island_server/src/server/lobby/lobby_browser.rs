use std::{cmp, collections::HashMap};

use log::{debug, logger, trace};
use tokio::sync::Mutex;
use uuid::Uuid;

use crate::server::{
    message::error_codes,
    user::UserId,
    user_connection::{self, UserConnection},
};

use super::game_lobby::{GameLobby, GameLobbyAccess};

pub struct LobbyBrowser {
    lobbies: HashMap<String, GameLobbyAccess>,
}

impl LobbyBrowser {
    pub fn new() -> Self {
        LobbyBrowser {
            lobbies: HashMap::new(),
        }
    }

    pub async fn create_and_own_lobby(
        &mut self,
        owner: &UserConnection,
        name: String,
        password: String,
        player_count: u32,
    ) -> Result<(), String> {
        let mut owner_game_state = owner.get_game_state().lock().await;
        if let Some(lobby_id) = owner_game_state.lobby.as_ref() {
            return Err(format!(
                "User is already assigned to lobby \"{}\"",
                lobby_id.lock().await.get_id()
            ));
        }

        let id = &Uuid::new_v4().as_simple().to_string();
        let lobby = match GameLobby::from(
            id.clone(),
            name,
            password,
            player_count,
            owner.clone(),
            owner_game_state.user.as_ref().unwrap().get_id().clone(),
        )
        .await
        {
            Ok(lobby) => lobby,
            Err(err) => return Err("Failed to create lobby".to_string()),
        };

        if self.lobbies.contains_key(id) {
            return Err(format!("Lobby id is already taken"));
        }

        let lobby_access = GameLobbyAccess::new(Mutex::new(lobby));

        owner_game_state.lobby.replace(lobby_access.clone());
        trace!(
            "User \"{}\" created lobby \"{}\"",
            owner_game_state.user.as_ref().unwrap().get_id(),
            id
        );
        self.lobbies.insert(id.clone(), lobby_access);
        debug!("Lobbies increased to {}", self.lobbies.len());
        Ok(())
    }

    pub async fn join_lobby(
        &self,
        user_connection: &UserConnection,
        lobby_id: &String,
        password: &String,
    ) -> Result<(), error_codes::ErrorCode> {
        if let Some(_) = &user_connection.get_game_state().lock().await.lobby {
            return Err(error_codes::ALREADY_IN_LOBBY);
        };

        let found_lobby = match self.get_lobby_by_id(&lobby_id) {
            Some(lobby) => lobby,
            None => {
                return Err(error_codes::LOBBY_NOT_FOUND);
            }
        };

        let mut found_lobby_locked = found_lobby.lock().await;

        if !found_lobby_locked.is_password(&password) {
            return Err(error_codes::INVALID_PASSWORD);
        }

        found_lobby_locked
            .add_user(user_connection.clone())
            .await
            .unwrap();
        user_connection.get_game_state().lock().await.lobby = Some(found_lobby.clone());

        Ok(())
    }

    pub async fn leave_lobby(
        &mut self,
        user_id: &UserId,
        lobby: GameLobbyAccess,
    ) -> Result<(), error_codes::ErrorCode> {
        trace!("Lock lobby");
        let mut lobby = lobby.lock().await;

        if let Err(err) = lobby.remove_user(user_id) {
            return Err(error_codes::LOBBY_INTERNAL_ERROR);
        }

        debug!("User \"{}\" left lobby \"{}\"", user_id, lobby.get_id());

        if lobby.get_joined_user_count() > 0 {
            return Ok(());
        }

        debug!("Lobby \"{}\" is closing", lobby.get_id());

        match self.lobbies.remove(lobby.get_id()) {
            None => Err(error_codes::LOBBY_NOT_FOUND),
            Some(_) => Ok(()),
        }
    }

    pub fn close_lobby(&mut self, lobby_id: &String) -> Result<(), String> {
        trace!("Closing lobby \"{}\"", lobby_id);
        match self.lobbies.remove(lobby_id) {
            None => Err(String::from("Lobby not found")),
            Some(_) => Ok(()),
        }
    }

    pub fn get_lobby_by_id(&self, lobby_id: &String) -> Option<GameLobbyAccess> {
        return self.lobbies.get(lobby_id).cloned();
    }

    pub fn get_lobby_ids(&self) -> Vec<&String> {
        self.lobbies.keys().collect()
    }

    pub fn get_lobby_page(&self, page_index: usize, items_per_page: usize) -> Vec<GameLobbyAccess> {
        let lobby_ids = self.get_lobby_ids();
        let start_item_index = page_index * items_per_page;
        if start_item_index >= lobby_ids.len() {
            return vec![];
        }

        let end_item_index = cmp::min(start_item_index + items_per_page, lobby_ids.len());
        let lobby_page_ids = &lobby_ids[start_item_index..end_item_index];
        trace!(
            "Returning lobbies [{}..{}] ({})",
            start_item_index,
            end_item_index,
            lobby_page_ids.len()
        );

        lobby_page_ids
            .into_iter()
            .filter_map(|lobby_id| self.get_lobby_by_id(&lobby_id))
            .collect()
    }
}
