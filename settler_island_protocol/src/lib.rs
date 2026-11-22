//! WebSocket messages between the server and its clients, as JSON objects tagged by `type`.

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

pub use settler_island_bot::Difficulty;
pub use settler_island_game::{Action, Event, GameError, GameRecord, PlayerView, Seat};

/// Larger text frames are answered with `ErrorCode::MessageTooLarge`.
pub const MAX_MESSAGE_BYTES: usize = 64 * 1024;
pub const MAX_USER_NAME_CHARS: usize = 24;
pub const MAX_LOBBY_NAME_CHARS: usize = 40;
pub const MAX_LOBBIES_PER_PAGE: u32 = 50;
pub const MIN_SEATS: u8 = 3;
pub const MAX_SEATS: u8 = 4;

#[derive(
    Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize, JsonSchema,
)]
#[serde(transparent)]
pub struct UserId(pub String);

#[derive(
    Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize, JsonSchema,
)]
#[serde(transparent)]
pub struct LobbyId(pub u32);

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub struct User {
    pub id: UserId,
    pub name: String,
}

/// Every request carries a `request_id` that the direct reply (or error) echoes.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "type")]
pub enum ClientMessage {
    /// Guest login without a token; must be the first message.
    Hello {
        request_id: u32,
        name: String,
    },
    /// `page` starts at 0; `per_page` is 1 to `MAX_LOBBIES_PER_PAGE`.
    ListLobbies {
        request_id: u32,
        page: u32,
        per_page: u32,
    },
    CreateLobby {
        request_id: u32,
        name: String,
        password: Option<String>,
        seats: u8,
    },
    JoinLobby {
        request_id: u32,
        lobby: LobbyId,
        password: Option<String>,
    },
    LeaveLobby {
        request_id: u32,
    },
    AddBot {
        request_id: u32,
        difficulty: Difficulty,
    },
    RemoveBot {
        request_id: u32,
        seat: Seat,
    },
    StartGame {
        request_id: u32,
    },
    Act {
        request_id: u32,
        action: Action,
    },
    /// Answered with `LobbyState`, plus `GameStarted` when a game runs.
    GetState {
        request_id: u32,
    },
    GetRecord {
        request_id: u32,
    },
}

impl ClientMessage {
    pub fn request_id(&self) -> u32 {
        match self {
            ClientMessage::Hello { request_id, .. }
            | ClientMessage::ListLobbies { request_id, .. }
            | ClientMessage::CreateLobby { request_id, .. }
            | ClientMessage::JoinLobby { request_id, .. }
            | ClientMessage::LeaveLobby { request_id }
            | ClientMessage::AddBot { request_id, .. }
            | ClientMessage::RemoveBot { request_id, .. }
            | ClientMessage::StartGame { request_id }
            | ClientMessage::Act { request_id, .. }
            | ClientMessage::GetState { request_id }
            | ClientMessage::GetRecord { request_id } => *request_id,
        }
    }
}

/// Broadcasts carry `request_id` only in the copy sent to the member whose request caused them.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "type")]
pub enum ServerMessage {
    Welcome {
        request_id: u32,
        user: User,
    },
    Lobbies {
        request_id: u32,
        page: u32,
        total: u32,
        lobbies: Vec<LobbySummary>,
    },
    /// Sent to every member whenever the lobby changes.
    LobbyState {
        request_id: Option<u32>,
        lobby: LobbyDetails,
    },
    LobbyLeft {
        request_id: u32,
    },
    /// Sent at the start and on rejoin; `legal_actions` is empty when the seat need not act.
    GameStarted {
        request_id: Option<u32>,
        seat: Seat,
        view: PlayerView,
        legal_actions: Vec<Action>,
    },
    /// Events are filtered for the receiving seat.
    GameUpdate {
        request_id: Option<u32>,
        events: Vec<Event>,
        view: PlayerView,
        legal_actions: Vec<Action>,
    },
    /// Filtered for the requesting seat while the game runs, complete once it is finished.
    Record {
        request_id: u32,
        record: GameRecord,
    },
    /// `request_id` is `None` when the message could not be read far enough to find it.
    Error {
        request_id: Option<u32>,
        code: ErrorCode,
        message: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub struct LobbySummary {
    pub id: LobbyId,
    pub name: String,
    pub owner: User,
    pub seats: u8,
    pub open_seats: u8,
    pub has_password: bool,
    pub started: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub struct LobbyDetails {
    pub id: LobbyId,
    pub name: String,
    pub owner: User,
    pub has_password: bool,
    pub started: bool,
    /// Index is the game seat.
    pub seats: Vec<SeatOccupant>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "type")]
pub enum SeatOccupant {
    Open,
    Human {
        user: User,
    },
    /// `reserved_for` is the player this bot stands in for until they rejoin.
    Bot {
        difficulty: Difficulty,
        reserved_for: Option<User>,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "type")]
pub enum ErrorCode {
    InvalidMessage,
    MessageTooLarge,
    RateLimited,
    NotWelcomed,
    AlreadyWelcomed,
    InvalidName,
    InvalidLobbyName,
    InvalidSeatCount,
    InvalidPage,
    LobbyNotFound,
    LobbyFull,
    GameAlreadyStarted,
    WrongPassword,
    AlreadyInLobby,
    NotInLobby,
    NotOwner,
    SeatsNotFilled,
    NotABot,
    NoGame,
    Internal,
    Game { error: GameError },
}

impl ErrorCode {
    pub fn description(&self) -> String {
        let text = match self {
            ErrorCode::InvalidMessage => "the message is not a valid client message",
            ErrorCode::MessageTooLarge => "the message is larger than 64 KiB",
            ErrorCode::RateLimited => "too many messages, slow down",
            ErrorCode::NotWelcomed => "send Hello first",
            ErrorCode::AlreadyWelcomed => "Hello was already sent",
            ErrorCode::InvalidName => "the name must have 1 to 24 visible characters",
            ErrorCode::InvalidLobbyName => "the lobby name must have 1 to 40 visible characters",
            ErrorCode::InvalidSeatCount => "a lobby has 3 or 4 seats",
            ErrorCode::InvalidPage => "per_page must be between 1 and 50",
            ErrorCode::LobbyNotFound => "no such lobby",
            ErrorCode::LobbyFull => "the lobby is full",
            ErrorCode::GameAlreadyStarted => "the game has already started",
            ErrorCode::WrongPassword => "wrong lobby password",
            ErrorCode::AlreadyInLobby => "leave the current lobby first",
            ErrorCode::NotInLobby => "not in a lobby",
            ErrorCode::NotOwner => "only the lobby owner may do this",
            ErrorCode::SeatsNotFilled => "every seat needs a player or a bot",
            ErrorCode::NotABot => "that seat holds no bot",
            ErrorCode::NoGame => "no game is running in this lobby",
            ErrorCode::Internal => "internal server error",
            ErrorCode::Game { error } => return error.to_string(),
        };
        text.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn client_message_is_a_flat_object_tagged_by_type() {
        let message = ClientMessage::JoinLobby {
            request_id: 7,
            lobby: LobbyId(3),
            password: None,
        };
        let value = serde_json::to_value(&message).unwrap();

        assert_eq!(
            value,
            json!({"type": "JoinLobby", "request_id": 7, "lobby": 3, "password": null})
        );
        assert_eq!(
            serde_json::from_value::<ClientMessage>(value).unwrap(),
            message
        );
        assert_eq!(message.request_id(), 7);
    }

    #[test]
    fn act_carries_the_tagged_game_action() {
        let text = r#"{"type":"Act","request_id":2,"action":{"type":"BankTrade","give":"Sheep","receive":"Ore"}}"#;
        let message: ClientMessage = serde_json::from_str(text).unwrap();

        assert_eq!(
            message,
            ClientMessage::Act {
                request_id: 2,
                action: Action::BankTrade {
                    give: settler_island_game::Resource::Sheep,
                    receive: settler_island_game::Resource::Ore,
                },
            }
        );
    }

    #[test]
    fn game_error_nests_inside_the_error_code() {
        let message = ServerMessage::Error {
            request_id: Some(4),
            code: ErrorCode::Game {
                error: GameError::NotYourTurn,
            },
            message: "it is not this seat's turn".to_string(),
        };
        let value = serde_json::to_value(&message).unwrap();

        assert_eq!(
            value,
            json!({
                "type": "Error",
                "request_id": 4,
                "code": {"type": "Game", "error": {"code": "NotYourTurn"}},
                "message": "it is not this seat's turn",
            })
        );
        assert_eq!(
            serde_json::from_value::<ServerMessage>(value).unwrap(),
            message
        );
    }

    #[test]
    fn seat_occupants_round_trip() {
        let seats = vec![
            SeatOccupant::Open,
            SeatOccupant::Human {
                user: User {
                    id: UserId("u1".to_string()),
                    name: "Ada".to_string(),
                },
            },
            SeatOccupant::Bot {
                difficulty: Difficulty::Random,
                reserved_for: None,
            },
        ];
        let text = serde_json::to_string(&seats).unwrap();

        assert_eq!(
            serde_json::from_str::<Vec<SeatOccupant>>(&text).unwrap(),
            seats
        );
        assert!(text.contains(r#"{"type":"Bot","difficulty":"Random","reserved_for":null}"#));
    }
}
