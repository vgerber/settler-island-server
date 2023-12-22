pub type ErrorCode = (&'static str, u32);

pub static INVALID_PASSWORD: ErrorCode = ("Invalid Password", 1);
pub static NOT_IN_LOBBY: ErrorCode = ("User did not join a lobby", 2);
pub static LOBBY_NOT_FOUND: ErrorCode = ("Lobby not found", 3);
pub static ALREADY_IN_LOBBY: ErrorCode = ("User is already in lobby", 4);
pub static NOT_REGISTERED: ErrorCode = ("User is registered", 5);
