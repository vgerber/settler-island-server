use serde::{Deserialize, Serialize};

pub type UserId = String;
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
}
