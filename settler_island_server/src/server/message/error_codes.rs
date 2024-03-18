pub type ErrorCode = (&'static str, u32);

pub static NOT_REGISTERED: ErrorCode = ("User is registered", 100);
pub static INVALID_PASSWORD: ErrorCode = ("Invalid Password", 101);
pub static NOT_IN_LOBBY: ErrorCode = ("User did not join a lobby", 200);
pub static LOBBY_NOT_FOUND: ErrorCode = ("Lobby not found", 201);
pub static ALREADY_IN_LOBBY: ErrorCode = ("User is already in lobby", 202);
pub static LOBBY_INTERNAL_ERROR: ErrorCode = ("Lobby internal error", 203);
