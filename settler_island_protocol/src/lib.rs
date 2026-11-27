//! WebSocket messages between the server and its clients, as JSON objects tagged by `type`.

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

pub use settler_island_bot::Difficulty;
pub use settler_island_game::{
    Action, Event, GameError, GameRecord, PlayerView, Purchase, Resource, Seat,
    DEFAULT_POINTS_TO_WIN, MAX_POINTS_TO_WIN, MAX_SEATS, MIN_POINTS_TO_WIN, MIN_SEATS,
};

/// Larger text frames are answered with `ErrorCode::MessageTooLarge`.
pub const MAX_MESSAGE_BYTES: usize = 64 * 1024;
pub const MAX_USER_NAME_CHARS: usize = 24;
pub const MAX_LOBBY_NAME_CHARS: usize = 40;
pub const MAX_LOBBIES_PER_PAGE: u32 = 50;
/// Bots that replace a leaving player play at this level unless `CreateLobby` names another.
pub const DEFAULT_BOT_DIFFICULTY: Difficulty = Difficulty::Heuristic;
/// What a lobby does with a leaving player's seat unless `CreateLobby` names another policy.
pub const DEFAULT_AWAY_POLICY: AwayPolicy = AwayPolicy::BotTakesOver;

/// The port the server listens on unless `SETTLER_BIND` says otherwise.
pub const DEFAULT_PORT: u16 = 8253;
/// `GET` upgrades to the WebSocket that carries `ClientMessage` and `ServerMessage`.
pub const WEBSOCKET_ROUTE: &str = "/api/v1/ws";
/// `POST` a `GuestSessionRequest`, get a `GuestSession`.
pub const GUEST_SESSION_ROUTE: &str = "/api/v1/sessions/guest";
/// `POST` an `UpgradeRequest`, get `Upgraded`.
pub const UPGRADE_SESSION_ROUTE: &str = "/api/v1/sessions/upgrade";
pub const HEALTH_ROUTE: &str = "/api/v1/health";

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

/// What happens to the seat of a human who leaves a running game, until they rejoin.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, JsonSchema)]
pub enum AwayPolicy {
    /// A bot of the lobby's `bot_difficulty` plays the seat.
    BotTakesOver,
    /// The seat stays theirs and the game waits whenever it needs that seat; bots of other seats wait too.
    WaitForPlayer,
}

/// How a user signed in; an upgraded guest keeps its id and becomes an `Account`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, JsonSchema)]
pub enum UserKind {
    Guest,
    Account,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub struct User {
    pub id: UserId,
    pub name: String,
    pub kind: UserKind,
}

/// Body of `POST /api/v1/sessions/guest`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub struct GuestSessionRequest {
    pub name: String,
}

/// Reply to `POST /api/v1/sessions/guest`; `token` is what `Authenticate` expects.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub struct GuestSession {
    pub token: String,
    pub user: User,
}

/// Body of `POST /api/v1/sessions/upgrade`: later logins with the account map to the guest's user id.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub struct UpgradeRequest {
    pub guest_token: String,
    /// A Keycloak access token.
    pub account_token: String,
}

/// Reply to `POST /api/v1/sessions/upgrade`: the user as later account logins see it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub struct Upgraded {
    pub user: User,
}

/// Body of every failed HTTP request.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub struct HttpError {
    pub code: ErrorCode,
    pub message: String,
}

/// Every request carries a `request_id` that the direct reply (or error) echoes.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "type")]
pub enum ClientMessage {
    /// Must be the first message; `token` is a guest session token or a Keycloak access token.
    Authenticate {
        request_id: u32,
        token: String,
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
        /// `MIN_POINTS_TO_WIN` to `MAX_POINTS_TO_WIN`; `None` means `DEFAULT_POINTS_TO_WIN`.
        #[serde(default)]
        points_to_win: Option<u8>,
        /// Replaces a player who leaves a running game; `None` means `DEFAULT_BOT_DIFFICULTY`.
        #[serde(default)]
        bot_difficulty: Option<Difficulty>,
        /// `None` means `DEFAULT_AWAY_POLICY`.
        #[serde(default)]
        away_policy: Option<AwayPolicy>,
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
            ClientMessage::Authenticate { request_id, .. }
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
        /// The lobby with a running game in which the user holds a seat, so a restarted client can rejoin it.
        running_lobby: Option<LobbyId>,
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

/// What the lobby list and the lobby room both show about a lobby.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub struct LobbyInfo {
    pub id: LobbyId,
    pub name: String,
    pub owner: User,
    pub has_password: bool,
    pub started: bool,
    pub points_to_win: u8,
    pub bot_difficulty: Difficulty,
    pub away_policy: AwayPolicy,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub struct LobbySummary {
    pub info: LobbyInfo,
    pub seats: u8,
    pub open_seats: u8,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub struct LobbyDetails {
    pub info: LobbyInfo,
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
    /// A player who left a running game under `AwayPolicy::WaitForPlayer`; the game waits for them to rejoin.
    Away {
        user: User,
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
    /// Sent to a connection just before the server closes it because the same user joined on a newer one.
    TakenOver,
    InvalidToken,
    AccountsDisabled,
    AccountAlreadyLinked,
    InvalidName,
    InvalidLobbyName,
    InvalidSeatCount,
    InvalidPointsToWin,
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
    /// A server-wide or per-user cap refused the request; retrying later may succeed.
    LimitReached {
        limit: ServerLimit,
    },
    Internal,
    Game {
        error: GameError,
    },
}

/// Which cap `ErrorCode::LimitReached` hit.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, JsonSchema)]
pub enum ServerLimit {
    Connections,
    ConnectionsPerIp,
    RunningGames,
    GamesPerUser,
    PasswordGuesses,
}

impl ErrorCode {
    pub fn description(&self) -> String {
        let text = match self {
            ErrorCode::InvalidMessage => "the message is not a valid client message",
            ErrorCode::MessageTooLarge => {
                return format!(
                    "the message is larger than {} KiB",
                    MAX_MESSAGE_BYTES / 1024
                )
            }
            ErrorCode::RateLimited => "too many messages, slow down",
            ErrorCode::NotWelcomed => "send Authenticate first",
            ErrorCode::AlreadyWelcomed => "Authenticate was already sent",
            ErrorCode::TakenOver => "this account joined on another connection",
            ErrorCode::InvalidToken => "the token is invalid or expired",
            ErrorCode::AccountsDisabled => "this server does not accept accounts",
            ErrorCode::AccountAlreadyLinked => "the account is already linked to another user",
            ErrorCode::InvalidName => {
                return format!("the name must have 1 to {MAX_USER_NAME_CHARS} visible characters")
            }
            ErrorCode::InvalidLobbyName => {
                return format!(
                    "the lobby name must have 1 to {MAX_LOBBY_NAME_CHARS} visible characters"
                )
            }
            ErrorCode::InvalidSeatCount => {
                return format!("a lobby has {MIN_SEATS} to {MAX_SEATS} seats")
            }
            ErrorCode::InvalidPointsToWin => {
                return format!(
                    "points to win must be between {MIN_POINTS_TO_WIN} and {MAX_POINTS_TO_WIN}"
                )
            }
            ErrorCode::InvalidPage => {
                return format!("per_page must be between 1 and {MAX_LOBBIES_PER_PAGE}")
            }
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
            ErrorCode::LimitReached { limit } => limit.description(),
            ErrorCode::Internal => "internal server error",
            ErrorCode::Game { error } => return error.to_string(),
        };
        text.to_string()
    }
}

impl ServerLimit {
    fn description(&self) -> &'static str {
        match self {
            ServerLimit::Connections => "the server has too many connections, try again later",
            ServerLimit::ConnectionsPerIp => "too many connections from this address",
            ServerLimit::RunningGames => "the server runs too many games, try again later",
            ServerLimit::GamesPerUser => "you already take part in too many games",
            ServerLimit::PasswordGuesses => "too many wrong passwords, try again later",
        }
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
    fn limit_reached_names_the_limit_as_a_string() {
        let code = ErrorCode::LimitReached {
            limit: ServerLimit::GamesPerUser,
        };
        let value = serde_json::to_value(code).unwrap();

        assert_eq!(
            value,
            json!({"type": "LimitReached", "limit": "GamesPerUser"})
        );
        assert_eq!(serde_json::from_value::<ErrorCode>(value).unwrap(), code);
    }

    #[test]
    fn seat_occupants_round_trip() {
        let seats = vec![
            SeatOccupant::Open,
            SeatOccupant::Human {
                user: User {
                    id: UserId("u1".to_string()),
                    name: "Ada".to_string(),
                    kind: UserKind::Guest,
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

    #[test]
    fn create_lobby_settings_are_optional() {
        let text = r#"{"type":"CreateLobby","request_id":1,"name":"T","password":null,"seats":3}"#;
        let message: ClientMessage = serde_json::from_str(text).unwrap();

        assert_eq!(
            message,
            ClientMessage::CreateLobby {
                request_id: 1,
                name: "T".to_string(),
                password: None,
                seats: 3,
                points_to_win: None,
                bot_difficulty: None,
                away_policy: None,
            }
        );
    }
}
