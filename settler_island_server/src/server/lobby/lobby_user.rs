use serde::{Deserialize, Serialize};

use crate::server::user::UserData;

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct LobbyUser {
    user: UserData,
}

impl LobbyUser {
    pub fn from(user: UserData) -> Self {
        LobbyUser { user: user }
    }
}
