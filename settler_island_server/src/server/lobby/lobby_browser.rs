use std::collections::HashMap;

use tokio::sync::Mutex;
use uuid::Uuid;

use crate::server::user_connection::UserConnection;

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
        if let Some(lobby_id) = owner.get_game_state().lock().await.lobby.as_ref() {
            return Err(format!(
                "User is already assigned to lobby \"{}\"",
                lobby_id.lock().await.get_id()
            ));
        }

        let id = &Uuid::new_v4().as_simple().to_string();
        let lobby = GameLobby::from(id.clone(), name, password, player_count, owner.clone()).await;

        if self.lobbies.contains_key(id) {
            return Err(format!("Lobby id is already taken"));
        }

        self.lobbies
            .insert(id.clone(), GameLobbyAccess::new(Mutex::new(lobby)));
        Ok(())
    }

    pub fn close_lobby(&mut self, lobby_id: &String) -> Result<(), String> {
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
        let end_item_index = start_item_index + items_per_page - 1;
        let lobby_page_ids = &lobby_ids[start_item_index..end_item_index];

        lobby_page_ids
            .into_iter()
            .filter_map(|lobby_id| self.get_lobby_by_id(&lobby_id))
            .collect()
    }
}
