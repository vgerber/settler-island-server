use std::sync::Arc;

use serde::{Deserialize, Serialize};
use tokio::sync::Mutex;

pub type UserId = String;
pub type UserAccess = Arc<Mutex<UserData>>;

pub trait ServerUser {}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct UserData {
    id: UserId,
    name: String,
}

impl UserData {
    pub fn from(id: &UserId, name: &str) -> Self {
        UserData {
            id: id.clone(),
            name: name.to_string(),
        }
    }

    pub fn get_id(&self) -> &String {
        &self.id
    }

    pub fn get_name(&self) -> &String {
        &self.name
    }
}
