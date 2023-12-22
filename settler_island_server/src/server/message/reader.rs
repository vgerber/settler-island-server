use async_trait::async_trait;
use serde::{Deserialize, Serialize};

use crate::server::user_connection::UserConnection;

pub mod game_message;
pub mod game_server_message;
pub mod lobby_message;

#[async_trait]
pub trait MessageReaderProvider: Sync + Send {
    fn get_group(&self) -> &String;
    async fn call(
        &self,
        user: &UserConnection,
        command: &str,
        json_message: &str,
    ) -> Result<(), String>;
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct MessageBase {
    pub version: u32,
    pub group: String,
    pub command: String,
}
