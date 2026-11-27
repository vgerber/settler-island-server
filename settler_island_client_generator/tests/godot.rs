//! Runs the generated GDScript client in a headless Godot: a JSON round trip of sample messages, a
//! short game against a real server, the game project in `client/godot` playing a full game (once
//! through `GameState`, once through mouse clicks on its main scene), its board placing corners and
//! sending the clicked action, `GameState` after a dropped act, and the HUD's discard dialog and event log.
//! Each project is copied and imported once per test binary. Skipped with a notice when no Godot binary
//! is found, or a panic when `SETTLER_REQUIRE_GODOT=1`; the binary is `$SETTLER_GODOT` or
//! `$HOME/Software/godot/godot`.

use std::collections::BTreeSet;
use std::fs::{self, File};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::OnceLock;
use std::time::{Duration, Instant};

use schemars::{schema_for, JsonSchema};
use serde_json::{json, Value};
use settler_island_bot::{create_bot, play_game, Difficulty};
use settler_island_client_generator::{default_client_directory, API_DIRECTORY};
use settler_island_game::{
    replay, Action, CornerId, DevelopmentCard, EdgeId, Event, Game, GameError, GameSettings, Phase,
    Port, Resource, ResourceCounts, Resume, TileId,
};
use settler_island_protocol::{
    AwayPolicy, ClientMessage, ErrorCode, LobbyDetails, LobbyId, LobbyInfo, LobbySummary, PublicId,
    SeatOccupant, ServerLimit, ServerMessage, User, UserKind,
};
use settler_island_server::{serve, Config, MemoryIdentityStore, MemoryStore, SessionSecret};

const GODOT_TIMEOUT: Duration = Duration::from_secs(240);

fn godot_binary() -> Option<PathBuf> {
    let path = std::env::var_os("SETTLER_GODOT")
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var_os("HOME").map(|home| Path::new(&home).join("Software/godot/godot"))
        })
        .unwrap_or_default();
    if path.is_file() {
        return Some(path);
    }
    // A gate that must cover the game client sets this, so a missing binary cannot pass silently.
    let required = std::env::var("SETTLER_REQUIRE_GODOT").is_ok_and(|value| value == "1");
    assert!(
        !required,
        "SETTLER_REQUIRE_GODOT=1 but there is no Godot binary at {}",
        path.display()
    );
    println!(
        "notice: no Godot binary at {}, skipping the headless Godot test",
        path.display()
    );
    None
}

#[derive(Clone, Copy)]
enum Project {
    /// `client/godot_tests` with the generated API only.
    Api,
    /// The game project `client/godot` plus every script of `client/godot_tests`.
    Game,
}

impl Project {
    fn name(self) -> &'static str {
        match self {
            Project::Api => "api",
            Project::Game => "game",
        }
    }
}

/// A prepared and imported project, built once per test binary and shared by all tests, which
/// give every run its own Godot home.
fn project_root(godot: &Path, project: Project) -> &'static Path {
    static API: OnceLock<PathBuf> = OnceLock::new();
    static GAME: OnceLock<PathBuf> = OnceLock::new();
    let cell = match project {
        Project::Api => &API,
        Project::Game => &GAME,
    };
    cell.get_or_init(|| {
        let root = fresh_root(project.name());
        match project {
            Project::Api => prepare_test_project(&root),
            Project::Game => prepare_game_project(&root),
        }
        run_godot(godot, &root, &root.join("import-home"), &["--import"]);
        root
    })
}

/// An empty directory; the project goes into `project/`.
fn fresh_root(name: &str) -> PathBuf {
    let root = Path::new(env!("CARGO_TARGET_TMPDIR")).join(format!("godot-{name}"));
    if root.exists() {
        fs::remove_dir_all(&root).unwrap();
    }
    fs::create_dir_all(&root).unwrap();
    root
}

fn prepare_test_project(root: &Path) {
    let project = root.join("project");
    let api = project.join("settler_island_api");
    fs::create_dir_all(&api).unwrap();
    let client = default_client_directory();
    copy_sources(&client.join("godot_tests"), &project);
    copy_sources(&client.join(API_DIRECTORY), &api);
}

fn prepare_game_project(root: &Path) {
    let project = root.join("project");
    let client = default_client_directory();
    copy_tree(&client.join("godot"), &project, false);
    for entry in fs::read_dir(client.join("godot_tests")).unwrap() {
        let path = entry.unwrap().path();
        // The test project's own project.godot must not replace the game's.
        if path.extension().is_some_and(|extension| extension == "gd") {
            fs::copy(&path, project.join(path.file_name().unwrap())).unwrap();
        }
    }
}

fn copy_sources(from: &Path, to: &Path) {
    for entry in fs::read_dir(from).unwrap() {
        let path = entry.unwrap().path();
        let is_source = path
            .extension()
            .is_some_and(|extension| extension == "gd" || extension == "godot");
        if is_source {
            fs::copy(&path, to.join(path.file_name().unwrap())).unwrap();
        }
    }
}

/// Copies a Godot project; the editor cache `.godot/` belongs to the checkout, so it is kept only
/// when copying an already imported project.
fn copy_tree(from: &Path, to: &Path, keep_cache: bool) {
    fs::create_dir_all(to).unwrap();
    for entry in fs::read_dir(from).unwrap() {
        let path = entry.unwrap().path();
        let name = path.file_name().unwrap();
        if name == ".godot" && !keep_cache {
            continue;
        }
        if path.is_dir() {
            copy_tree(&path, &to.join(name), keep_cache);
            continue;
        }
        fs::copy(&path, to.join(name)).unwrap();
    }
}

/// Runs Godot headless on `root/project` with its data and config in `home`; returns stdout plus stderr.
fn run_godot(godot: &Path, root: &Path, home: &Path, arguments: &[&str]) -> String {
    fs::create_dir_all(home).unwrap();
    let log = home.join("godot.log");
    let output = File::create(&log).unwrap();
    let mut child = Command::new(godot)
        .arg("--headless")
        .arg("--path")
        .arg(root.join("project"))
        .args(arguments)
        .env("XDG_DATA_HOME", home)
        .env("XDG_CONFIG_HOME", home)
        .env("XDG_CACHE_HOME", home)
        .stdin(Stdio::null())
        .stdout(output.try_clone().unwrap())
        .stderr(output)
        .spawn()
        .unwrap();
    let started = Instant::now();
    let status = loop {
        if let Some(status) = child.try_wait().unwrap() {
            break Some(status);
        }
        if started.elapsed() > GODOT_TIMEOUT {
            // Kills exactly the Godot process this test spawned.
            child.kill().unwrap();
            child.wait().unwrap();
            break None;
        }
        std::thread::sleep(Duration::from_millis(50));
    };
    let text = fs::read_to_string(&log).unwrap();
    let Some(status) = status else {
        panic!("godot {arguments:?} timed out:\n{text}");
    };
    let errors: Vec<&str> = text
        .lines()
        .filter(|line| line.contains("SCRIPT ERROR") || line.trim_start().starts_with("ERROR"))
        .collect();
    assert!(
        status.success() && errors.is_empty(),
        "godot {arguments:?} failed ({status}):\n{text}"
    );
    text
}

/// Runs one test script of `project` in a Godot home of its own and checks that the output has
/// `marker`.
fn run_script(godot: &Path, project: Project, script: &str, argument: &str, marker: &str) {
    let root = project_root(godot, project);
    let home = root.join("homes").join(script);
    let output = run_godot(godot, root, &home, &["-s", script, "--", argument]);
    assert!(output.contains(marker), "{output}");
}

fn user(id: &str, name: &str) -> User {
    User {
        id: PublicId(id.to_string()),
        name: name.to_string(),
        kind: UserKind::Guest,
    }
}

fn to_json<T: serde::Serialize>(value: &T) -> Value {
    serde_json::to_value(value).unwrap()
}

/// The `type` tag of every variant of the internally tagged enum `T`, read from its schema, so a new Rust variant
/// is noticed here without a hand-kept list.
fn variant_names<T: JsonSchema>() -> BTreeSet<String> {
    let schema = to_json(&schema_for!(T));
    let variants = schema["oneOf"].as_array().expect("tagged enum schema");
    variants
        .iter()
        .map(|variant| {
            let tag = &variant["properties"]["type"];
            tag["const"].as_str().expect("tag constant").to_string()
        })
        .collect()
}

/// Fails when a variant of `T` has no sample in `samples`.
fn assert_covers<T: JsonSchema>(samples: &[Value]) {
    let present: BTreeSet<String> = samples
        .iter()
        .filter_map(|sample| sample["type"].as_str().map(str::to_string))
        .collect();
    let missing: Vec<_> = variant_names::<T>().difference(&present).cloned().collect();
    assert!(
        missing.is_empty(),
        "{} has no sample for {missing:?}; add one to the fixtures",
        std::any::type_name::<T>()
    );
}

/// One error code per variant: the unit variants are decoded from their schema names, so a new one is sampled
/// without an edit here.
fn error_code_samples() -> Vec<ErrorCode> {
    variant_names::<ErrorCode>()
        .into_iter()
        .map(|name| match name.as_str() {
            "LimitReached" => ErrorCode::LimitReached {
                limit: ServerLimit::ConnectionsPerIp,
            },
            "Game" => ErrorCode::Game {
                error: GameError::NotYourTurn,
            },
            _ => serde_json::from_value(json!({ "type": name })).expect("unit error code"),
        })
        .collect()
}

fn event_samples() -> Vec<Event> {
    let cards = ResourceCounts::new([1, 0, 2, 0, 1]);
    let one_brick = ResourceCounts::new([1, 0, 0, 0, 0]);
    let one_lumber = ResourceCounts::new([0, 1, 0, 0, 0]);
    vec![
        Event::SettlementPlaced {
            seat: 0,
            corner: CornerId(4),
        },
        Event::RoadPlaced {
            seat: 1,
            edge: EdgeId(7),
        },
        Event::CityBuilt {
            seat: 2,
            corner: CornerId(9),
        },
        Event::DiceRolled {
            seat: 3,
            first: 3,
            second: 4,
        },
        Event::ResourcesProduced {
            seat: 0,
            resources: cards,
        },
        Event::ResourcesPaid {
            seat: 1,
            resources: cards,
        },
        Event::RobberMoved {
            seat: 2,
            tile: TileId(5),
        },
        Event::CardsDiscarded {
            seat: 3,
            resources: cards,
        },
        Event::ResourceStolen {
            thief: 0,
            victim: 1,
            resource: Some(Resource::Ore),
        },
        Event::ResourceStolen {
            thief: 2,
            victim: 3,
            resource: None,
        },
        Event::BankTraded {
            seat: 1,
            gave: ResourceCounts::new([4, 0, 0, 0, 0]),
            received: ResourceCounts::new([0, 0, 0, 0, 1]),
        },
        Event::TradeOffered {
            seat: 0,
            give: one_brick,
            receive: one_lumber,
            to: None,
        },
        Event::TradeOffered {
            seat: 0,
            give: one_brick,
            receive: one_lumber,
            to: Some(1),
        },
        Event::TradeAnswered {
            seat: 2,
            accepted: true,
        },
        Event::TradeCompleted {
            seat: 0,
            with: 2,
            gave: one_brick,
            received: one_lumber,
        },
        Event::TradeCancelled { seat: 0 },
        Event::DevelopmentCardBought {
            seat: 1,
            card: Some(DevelopmentCard::Monopoly),
        },
        Event::DevelopmentCardBought {
            seat: 2,
            card: None,
        },
        Event::DevelopmentCardPlayed {
            seat: 3,
            card: DevelopmentCard::YearOfPlenty,
        },
        Event::MonopolyTaken {
            seat: 3,
            resource: Resource::Wheat,
            amount: 5,
        },
        Event::YearOfPlentyTaken {
            seat: 1,
            resources: ResourceCounts::new([0, 1, 0, 1, 0]),
        },
        Event::LongestRoadChanged {
            holder: Some(2),
            length: 6,
        },
        Event::LongestRoadChanged {
            holder: None,
            length: 0,
        },
        Event::LargestArmyChanged {
            holder: Some(1),
            knights: 3,
        },
        Event::LargestArmyChanged {
            holder: None,
            knights: 0,
        },
        Event::PhaseChanged {
            phase: Phase::RoadBuilding {
                roads_left: 2,
                resume: Resume::Main,
            },
        },
        Event::TurnStarted { seat: 2 },
        Event::TurnEnded { seat: 2 },
        Event::GameWon {
            seat: 1,
            points: 10,
        },
    ]
}

fn action_samples() -> Vec<Action> {
    let one_brick = ResourceCounts::new([1, 0, 0, 0, 0]);
    let one_lumber = ResourceCounts::new([0, 1, 0, 0, 0]);
    vec![
        Action::PlaceSettlement {
            corner: CornerId(4),
        },
        Action::PlaceRoad { edge: EdgeId(7) },
        Action::RollDice,
        Action::EndTurn,
        Action::BuildRoad { edge: EdgeId(8) },
        Action::BuildSettlement {
            corner: CornerId(5),
        },
        Action::BuildCity {
            corner: CornerId(5),
        },
        Action::MoveRobber { tile: TileId(3) },
        Action::Steal { victim: 2 },
        Action::Discard {
            resources: one_brick,
        },
        Action::BankTrade {
            give: Resource::Clay,
            receive: Resource::Ore,
        },
        Action::OfferTrade {
            give: one_brick,
            receive: one_lumber,
            to: Some(1),
        },
        Action::AcceptTrade,
        Action::RejectTrade,
        Action::ConfirmTrade { with: 1 },
        Action::CancelTrade,
        Action::BuyDevelopmentCard,
        Action::PlayKnight,
        Action::PlayRoadBuilding,
        Action::PlayYearOfPlenty {
            first: Resource::Wheat,
            second: Resource::Ore,
        },
        Action::PlayMonopoly {
            resource: Resource::Sheep,
        },
    ]
}

/// Every message variant, with game payloads taken from a played game so all events occur.
fn fixtures() -> Value {
    let settings = GameSettings {
        seats: 4,
        points_to_win: 10,
        seed: 11,
    };
    let bots = (0..4)
        .map(|seat| {
            let difficulty = if seat % 2 == 0 {
                Difficulty::Random
            } else {
                Difficulty::Heuristic
            };
            create_bot(difficulty, seat)
        })
        .collect();
    let outcome = play_game(settings.clone(), bots, 3000).unwrap();
    let actions: Vec<_> = outcome
        .record
        .entries
        .iter()
        .map(|entry| (entry.seat, entry.action.clone()))
        .collect();
    let middle = replay(
        Game::new(settings).unwrap(),
        &outcome.record.entries[..actions.len() / 2],
    )
    .unwrap();
    let seat = middle.pending_seats()[0];
    let owner = user("2b7e151628ae4d2aabf71588ca09cf4f", "Ada");

    let mut client = vec![
        ClientMessage::Authenticate {
            request_id: 1,
            token: "token".to_string(),
        },
        ClientMessage::ListLobbies {
            request_id: 2,
            page: 0,
            per_page: 10,
        },
        ClientMessage::CreateLobby {
            request_id: 3,
            name: "Table".to_string(),
            password: Some("secret".to_string()),
            seats: 4,
            points_to_win: Some(3),
            bot_difficulty: Some(Difficulty::Random),
            away_policy: Some(AwayPolicy::WaitForPlayer),
        },
        ClientMessage::CreateLobby {
            request_id: 4,
            name: "Open".to_string(),
            password: None,
            seats: 3,
            points_to_win: None,
            bot_difficulty: None,
            away_policy: None,
        },
        ClientMessage::JoinLobby {
            request_id: 5,
            lobby: LobbyId(9),
            password: None,
        },
        ClientMessage::LeaveLobby { request_id: 6 },
        ClientMessage::AddBot {
            request_id: 7,
            difficulty: Difficulty::Heuristic,
        },
        ClientMessage::RemoveBot {
            request_id: 8,
            seat: 2,
        },
        ClientMessage::StartGame { request_id: 9 },
        ClientMessage::GetState { request_id: 10 },
        ClientMessage::GetRecord { request_id: 11 },
    ];
    let sample_actions: Vec<Action> = actions
        .iter()
        .map(|(_, action)| action.clone())
        .chain(action_samples())
        .collect();
    client.extend(sample_actions.iter().map(|action| ClientMessage::Act {
        request_id: 12,
        action: action.clone(),
    }));

    let info = LobbyInfo {
        id: LobbyId(9),
        name: "Table".to_string(),
        owner: owner.clone(),
        has_password: true,
        started: false,
        points_to_win: 3,
        bot_difficulty: Difficulty::Heuristic,
        away_policy: AwayPolicy::BotTakesOver,
    };
    let lobby = LobbyDetails {
        info: info.clone(),
        seats: vec![
            SeatOccupant::Human {
                user: owner.clone(),
            },
            SeatOccupant::Bot {
                difficulty: Difficulty::Random,
                reserved_for: Some(user("3f9c0a525d4e4b8a9e610c7d2a8b1e33", "Bob")),
            },
            SeatOccupant::Bot {
                difficulty: Difficulty::Heuristic,
                reserved_for: None,
            },
            SeatOccupant::Open,
            // One more seat than a game has, so every occupant kind is sampled.
            SeatOccupant::Away {
                user: user("c4a1e8f02b6d4c7e9f135a7b9d0e2c46", "Cy"),
            },
        ],
    };
    let mut server = vec![
        ServerMessage::Welcome {
            request_id: 1,
            user: owner.clone(),
            running_lobby: Some(LobbyId(9)),
        },
        ServerMessage::Lobbies {
            request_id: 2,
            page: 0,
            total: 1,
            lobbies: vec![LobbySummary {
                info,
                seats: 4,
                open_seats: 1,
            }],
        },
        ServerMessage::LobbyState {
            request_id: None,
            lobby,
        },
        ServerMessage::LobbyLeft { request_id: 6 },
        ServerMessage::GameStarted {
            request_id: Some(9),
            seat,
            view: middle.view(Some(seat)),
            legal_actions: middle.legal_actions(seat),
        },
        ServerMessage::Record {
            request_id: 11,
            record: outcome.record.clone(),
        },
    ];
    server.extend(
        error_code_samples()
            .into_iter()
            .map(|code| ServerMessage::Error {
                request_id: Some(12),
                message: code.description(),
                code,
            }),
    );
    server.extend(
        outcome
            .record
            .entries
            .iter()
            .map(|entry| ServerMessage::GameUpdate {
                request_id: None,
                events: entry.events.clone(),
                view: outcome.final_view.clone(),
                legal_actions: Vec::new(),
            }),
    );
    let event_values: Vec<Value> = event_samples().iter().map(to_json).collect();
    let action_values: Vec<Value> = sample_actions.iter().map(to_json).collect();
    let error_values: Vec<Value> = error_code_samples().iter().map(to_json).collect();
    let client: Vec<Value> = client.iter().map(to_json).collect();
    let server: Vec<Value> = server.iter().map(to_json).collect();
    assert_covers::<ClientMessage>(&client);
    assert_covers::<ServerMessage>(&server);
    assert_covers::<Action>(&action_values);
    assert_covers::<Event>(&event_values);
    assert_covers::<ErrorCode>(&error_values);
    json!({
        "client": client,
        "server": server,
        "actions": action_values,
        "events": event_values,
        "errors": error_values,
    })
}

fn write_fixtures() -> PathBuf {
    let path = Path::new(env!("CARGO_TARGET_TMPDIR")).join("godot-round-trip-fixtures.json");
    fs::write(&path, fixtures().to_string()).unwrap();
    path
}

/// The shapes of `UserId`s: a guest's hyphenated uuid or `kc:` plus a Keycloak subject.
fn is_user_id_shaped(text: &str) -> bool {
    let hyphens_at_uuid_positions = text.len() == 36
        && text.char_indices().all(|(index, character)| match index {
            8 | 13 | 18 | 23 => character == '-',
            _ => character.is_ascii_hexdigit(),
        });
    text.starts_with("kc:") || hyphens_at_uuid_positions
}

/// Every string anywhere in `value`.
fn strings(value: &Value) -> Vec<&str> {
    match value {
        Value::String(text) => vec![text.as_str()],
        Value::Array(items) => items.iter().flat_map(strings).collect(),
        Value::Object(fields) => fields.values().flat_map(strings).collect(),
        _ => Vec::new(),
    }
}

#[test]
fn server_messages_name_users_only_by_public_id() {
    let fixtures = fixtures();
    let leaked: Vec<&str> = strings(&fixtures["server"])
        .into_iter()
        .filter(|text| is_user_id_shaped(text))
        .collect();
    assert!(leaked.is_empty(), "user ids in server messages: {leaked:?}");
}

#[test]
fn generated_classes_round_trip_every_message() {
    let Some(godot) = godot_binary() else {
        return;
    };
    let fixtures_path = write_fixtures();

    run_script(
        &godot,
        Project::Api,
        "round_trip.gd",
        fixtures_path.to_str().unwrap(),
        "ROUND_TRIP_OK",
    );
}

/// A server with instant bots on an ephemeral port, running on `runtime` until the test ends; `seed`
/// fixes the board, dice and bots of every game.
fn start_server(runtime: &tokio::runtime::Runtime, seed: Option<u64>) -> String {
    let address = runtime.block_on(async {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let config = Config {
            bot_delay: Duration::ZERO,
            // Scripted clients answer every update at once; the limiter has its own server tests.
            messages_per_second: 10_000,
            seed,
            ..Config::new(SessionSecret::new((0..32).collect::<Vec<u8>>()).unwrap())
        };
        tokio::spawn(serve(
            listener,
            config,
            MemoryStore::default(),
            MemoryIdentityStore::default(),
            std::future::pending(),
        ));
        address
    });
    format!("http://{address}")
}

#[test]
fn generated_client_plays_against_a_real_server() {
    let Some(godot) = godot_binary() else {
        return;
    };
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let server = start_server(&runtime, None);

    run_script(&godot, Project::Api, "live_game.gd", &server, "LIVE_OK");
}

#[test]
fn game_client_plays_a_full_game_and_rejoins_it() {
    let Some(godot) = godot_binary() else {
        return;
    };
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let server = start_server(&runtime, None);

    run_script(
        &godot,
        Project::Game,
        "full_game.gd",
        &server,
        "FULL_GAME_OK",
    );
}

#[test]
fn main_scene_plays_a_full_game_with_mouse_clicks_only() {
    let Some(godot) = godot_binary() else {
        return;
    };
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let server = start_server(&runtime, Some(4));

    run_script(&godot, Project::Game, "ui_game.gd", &server, "UI_GAME_OK");
}

/// `GameStarted` for `seat` at the current state of `game`.
fn game_started(game: &Game, seat: u8) -> Value {
    to_json(&ServerMessage::GameStarted {
        request_id: None,
        seat,
        view: game.view(Some(seat)),
        legal_actions: game.legal_actions(seat),
    })
}

/// Two generic ports one free edge apart: four generic corners in a row along the coast.
fn has_adjacent_generic_ports(game: &Game) -> bool {
    let board = game.board();
    let is_generic = |corner| board.corner(corner).unwrap().port == Some(Port::Generic);
    let generic_edges = board
        .edges()
        .iter()
        .filter(|edge| edge.corners.iter().all(|corner| is_generic(*corner)))
        .count();
    generic_edges > 4
}

/// A fresh game in its setup phase on a board with adjacent generic ports, and a late bot game where
/// the robber is about to move, so the board shows roads, settlements, cities and robber targets.
fn board_fixtures() -> Value {
    let settings = GameSettings {
        seats: 4,
        points_to_win: 10,
        seed: 23,
    };
    let setup = (0..)
        .map(|seed| {
            Game::new(GameSettings {
                seed,
                ..settings.clone()
            })
            .unwrap()
        })
        .find(has_adjacent_generic_ports)
        .unwrap();
    let bots = (0..4)
        .map(|seat| create_bot(Difficulty::Heuristic, seat))
        .collect();
    let outcome = play_game(settings.clone(), bots, 3000).unwrap();
    let actions: Vec<_> = outcome
        .record
        .entries
        .iter()
        .map(|entry| (entry.seat, entry.action.clone()))
        .collect();
    let last_robber_move = actions
        .iter()
        .rposition(|(_, action)| matches!(action, Action::MoveRobber { .. }))
        .unwrap();
    let middle = replay(
        Game::new(settings).unwrap(),
        &outcome.record.entries[..last_robber_move],
    )
    .unwrap();
    json!({
        "setup": game_started(&setup, setup.pending_seats()[0]),
        "middle": game_started(&middle, actions[last_robber_move].0),
    })
}

#[test]
fn board_places_shared_corners_once_and_sends_the_clicked_action() {
    let Some(godot) = godot_binary() else {
        return;
    };
    let fixtures_path = Path::new(env!("CARGO_TARGET_TMPDIR")).join("godot-board-fixtures.json");
    fs::write(&fixtures_path, board_fixtures().to_string()).unwrap();

    run_script(
        &godot,
        Project::Game,
        "board_test.gd",
        fixtures_path.to_str().unwrap(),
        "BOARD_OK",
    );
}

/// `GameStarted` for a seat that must discard and has more than one way to do it, from a bot game.
fn discard_fixture() -> Value {
    for seed in 1..50 {
        let settings = GameSettings {
            seats: 4,
            points_to_win: 10,
            seed,
        };
        let bots = (0..4)
            .map(|seat| create_bot(Difficulty::Random, seat))
            .collect();
        let outcome = play_game(settings.clone(), bots, 3000).unwrap();
        let mut game = Game::new(settings).unwrap();
        for entry in &outcome.record.entries {
            game.apply(entry.seat, entry.action.clone()).unwrap();
            if !matches!(game.phase(), Phase::Discard { .. }) {
                continue;
            }
            let choosing = game
                .pending_seats()
                .into_iter()
                .find(|seat| game.legal_actions(*seat).len() > 1);
            if let Some(seat) = choosing {
                return to_json(&ServerMessage::GameStarted {
                    request_id: None,
                    seat,
                    view: game.view(Some(seat)),
                    legal_actions: game.legal_actions(seat),
                });
            }
        }
    }
    panic!("no bot game reached a discard with a choice");
}

#[test]
fn hud_discard_dialog_sends_exactly_the_picked_legal_discard() {
    let Some(godot) = godot_binary() else {
        return;
    };
    let fixture_path = Path::new(env!("CARGO_TARGET_TMPDIR")).join("godot-hud-discard.json");
    fs::write(&fixture_path, discard_fixture().to_string()).unwrap();

    run_script(
        &godot,
        Project::Game,
        "hud_discard.gd",
        fixture_path.to_str().unwrap(),
        "HUD_DISCARD_OK",
    );
}

#[test]
fn game_state_offers_a_rate_limited_act_again() {
    let Some(godot) = godot_binary() else {
        return;
    };
    let game = Game::new(GameSettings {
        seats: 4,
        points_to_win: 10,
        seed: 5,
    })
    .unwrap();
    let fixture_path = Path::new(env!("CARGO_TARGET_TMPDIR")).join("godot-game-state.json");
    let mut fixture = game_started(&game, 0);
    fixture["rate_limited"] = to_json(&ServerMessage::Error {
        request_id: None,
        message: ErrorCode::RateLimited.description(),
        code: ErrorCode::RateLimited,
    });
    fs::write(&fixture_path, fixture.to_string()).unwrap();

    run_script(
        &godot,
        Project::Game,
        "game_state_test.gd",
        fixture_path.to_str().unwrap(),
        "GAME_STATE_OK",
    );
}

#[test]
fn event_player_shows_a_view_only_after_its_events() {
    let Some(godot) = godot_binary() else {
        return;
    };
    let game = Game::new(GameSettings {
        seats: 4,
        points_to_win: 10,
        seed: 5,
    })
    .unwrap();
    let fixture_path = Path::new(env!("CARGO_TARGET_TMPDIR")).join("godot-event-player.json");
    fs::write(&fixture_path, game_started(&game, 0).to_string()).unwrap();

    run_script(
        &godot,
        Project::Game,
        "event_player_test.gd",
        fixture_path.to_str().unwrap(),
        "EVENT_PLAYER_OK",
    );
}

#[test]
fn hud_event_log_has_a_line_for_every_event() {
    let Some(godot) = godot_binary() else {
        return;
    };

    run_script(
        &godot,
        Project::Game,
        "hud_event_log.gd",
        write_fixtures().to_str().unwrap(),
        "HUD_EVENT_LOG_OK",
    );
}

#[test]
fn hud_fits_the_window_in_every_screenshot_state() {
    let Some(godot) = godot_binary() else {
        return;
    };
    let fixtures_path = Path::new(env!("CARGO_TARGET_TMPDIR")).join("godot-hud-min-size.json");
    fs::write(&fixtures_path, board_fixtures().to_string()).unwrap();

    run_script(
        &godot,
        Project::Game,
        "hud_min_size.gd",
        fixtures_path.to_str().unwrap(),
        "HUD_MIN_SIZE_OK",
    );
}

#[test]
fn every_sound_hook_has_a_file_and_repeats_are_dropped() {
    let Some(godot) = godot_binary() else {
        return;
    };

    run_script(
        &godot,
        Project::Game,
        "sfx_atmosphere.gd",
        "",
        "SFX_ATMOSPHERE_OK",
    );
}

#[test]
fn net_goes_online_after_a_failed_start() {
    let Some(godot) = godot_binary() else {
        return;
    };
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let server = start_server(&runtime, None);

    run_script(
        &godot,
        Project::Game,
        "net_reconnect.gd",
        &server,
        "NET_RECONNECT_OK",
    );
}

#[test]
fn net_replaces_a_refused_stored_token_with_a_fresh_guest_session() {
    let Some(godot) = godot_binary() else {
        return;
    };
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let server = start_server(&runtime, None);

    run_script(
        &godot,
        Project::Game,
        "net_stale_token.gd",
        &server,
        "NET_STALE_TOKEN_OK",
    );
}

#[test]
fn screens_take_their_limits_from_the_protocol() {
    let Some(godot) = godot_binary() else {
        return;
    };
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let fixture = json!({
        "server": start_server(&runtime, None),
        "invalid_name_message": ErrorCode::InvalidName.description(),
    });
    let fixture_path = Path::new(env!("CARGO_TARGET_TMPDIR")).join("godot-screen-limits.json");
    fs::write(&fixture_path, fixture.to_string()).unwrap();

    run_script(
        &godot,
        Project::Game,
        "screen_limits.gd",
        fixture_path.to_str().unwrap(),
        "SCREEN_LIMITS_OK",
    );
}

#[test]
fn committed_theme_matches_a_fresh_build() {
    let Some(godot) = godot_binary() else {
        return;
    };
    // The build overwrites the theme, so it runs in a copy of the imported project.
    let root = fresh_root("theme");
    let project = root.join("project");
    copy_tree(
        &project_root(&godot, Project::Game).join("project"),
        &project,
        true,
    );
    run_godot(
        &godot,
        &root,
        &root.join("home"),
        &["-s", "tools/build_theme.gd"],
    );

    let theme = Path::new("theme/main_theme.tres");
    let committed = fs::read(default_client_directory().join("godot").join(theme)).unwrap();
    let rebuilt = fs::read(project.join(theme)).unwrap();
    assert!(
        committed == rebuilt,
        "client/godot/theme/main_theme.tres is stale: run `godot --headless --path client/godot -s tools/build_theme.gd`"
    );
}
