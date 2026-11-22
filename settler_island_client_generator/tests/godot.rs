//! Runs the generated GDScript client in a headless Godot: a JSON round trip of sample messages and
//! a short game against a real server. Skipped with a notice when no Godot binary is found; the
//! binary is `$SETTLER_GODOT` or the default install path below.

use std::fs::{self, File};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use serde_json::{json, Value};
use settler_island_bot::{create_bot, play_game, Difficulty};
use settler_island_client_generator::{default_client_directory, API_DIRECTORY};
use settler_island_game::{replay, GameError, GameSettings};
use settler_island_protocol::{
    ClientMessage, ErrorCode, LobbyDetails, LobbyId, LobbySummary, SeatOccupant, ServerMessage,
    User, UserId, UserKind,
};
use settler_island_server::{serve, Config, MemoryIdentityStore, MemoryStore, SessionSecret};

const DEFAULT_GODOT: &str = "/home/vincent/Software/godot/godot";
const GODOT_TIMEOUT: Duration = Duration::from_secs(120);

fn godot_binary() -> Option<PathBuf> {
    let path = std::env::var_os("SETTLER_GODOT")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(DEFAULT_GODOT));
    if path.is_file() {
        return Some(path);
    }
    println!(
        "notice: no Godot binary at {}, skipping the headless Godot test",
        path.display()
    );
    None
}

/// A fresh copy of `client/godot_tests` with the generated API, plus a private Godot home.
fn prepare_project(name: &str) -> PathBuf {
    let root = Path::new(env!("CARGO_TARGET_TMPDIR")).join(format!("godot-{name}"));
    if root.exists() {
        fs::remove_dir_all(&root).unwrap();
    }
    let project = root.join("project");
    let api = project.join("settler_island_api");
    fs::create_dir_all(&api).unwrap();
    fs::create_dir_all(root.join("home")).unwrap();
    let client = default_client_directory();
    copy_files(&client.join("godot_tests"), &project);
    copy_files(&client.join(API_DIRECTORY), &api);
    copy_files(&client.join("godot"), &project);
    root
}

fn copy_files(from: &Path, to: &Path) {
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

/// Runs Godot headless with its data and config redirected; returns stdout plus stderr.
fn run_godot(godot: &Path, root: &Path, arguments: &[&str]) -> String {
    let log = root.join("godot.log");
    let output = File::create(&log).unwrap();
    let home = root.join("home");
    let mut child = Command::new(godot)
        .arg("--headless")
        .arg("--path")
        .arg(root.join("project"))
        .args(arguments)
        .env("XDG_DATA_HOME", &home)
        .env("XDG_CONFIG_HOME", &home)
        .env("XDG_CACHE_HOME", &home)
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

/// Imports the project so Godot knows the `class_name`s, then runs one test script.
fn run_script(godot: &Path, name: &str, script: &str, argument: &str) -> String {
    let root = prepare_project(name);
    run_godot(godot, &root, &["--import"]);
    run_godot(godot, &root, &["-s", script, "--", argument])
}

fn user(id: &str, name: &str) -> User {
    User {
        id: UserId(id.to_string()),
        name: name.to_string(),
        kind: UserKind::Guest,
    }
}

fn to_json<T: serde::Serialize>(value: &T) -> Value {
    serde_json::to_value(value).unwrap()
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
    let middle = replay(settings, &actions[..actions.len() / 2]).unwrap();
    let seat = middle.pending_seats()[0];
    let owner = user("u1", "Ada");

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
        },
        ClientMessage::CreateLobby {
            request_id: 4,
            name: "Open".to_string(),
            password: None,
            seats: 3,
            points_to_win: None,
            bot_difficulty: None,
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
    client.extend(actions.iter().map(|(_, action)| ClientMessage::Act {
        request_id: 12,
        action: action.clone(),
    }));

    let lobby = LobbyDetails {
        id: LobbyId(9),
        name: "Table".to_string(),
        owner: owner.clone(),
        has_password: true,
        started: false,
        points_to_win: 3,
        bot_difficulty: Difficulty::Heuristic,
        seats: vec![
            SeatOccupant::Human {
                user: owner.clone(),
            },
            SeatOccupant::Bot {
                difficulty: Difficulty::Random,
                reserved_for: Some(user("u2", "Bob")),
            },
            SeatOccupant::Bot {
                difficulty: Difficulty::Heuristic,
                reserved_for: None,
            },
            SeatOccupant::Open,
        ],
    };
    let mut server = vec![
        ServerMessage::Welcome {
            request_id: 1,
            user: owner.clone(),
        },
        ServerMessage::Lobbies {
            request_id: 2,
            page: 0,
            total: 1,
            lobbies: vec![LobbySummary {
                id: LobbyId(9),
                name: "Table".to_string(),
                owner: owner.clone(),
                seats: 4,
                open_seats: 1,
                has_password: true,
                started: false,
                points_to_win: 3,
                bot_difficulty: Difficulty::Heuristic,
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
        ServerMessage::Error {
            request_id: Some(12),
            code: ErrorCode::Game {
                error: GameError::NotYourTurn,
            },
            message: "it is not this seat's turn".to_string(),
        },
        ServerMessage::Error {
            request_id: None,
            code: ErrorCode::InvalidMessage,
            message: "invalid".to_string(),
        },
    ];
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
    let client: Vec<Value> = client.iter().map(to_json).collect();
    let server: Vec<Value> = server.iter().map(to_json).collect();
    json!({ "client": client, "server": server })
}

#[test]
fn generated_classes_round_trip_every_message() {
    let Some(godot) = godot_binary() else {
        return;
    };
    let fixtures_path =
        Path::new(env!("CARGO_TARGET_TMPDIR")).join("godot-round-trip-fixtures.json");
    fs::write(&fixtures_path, fixtures().to_string()).unwrap();

    let output = run_script(
        &godot,
        "round-trip",
        "round_trip.gd",
        fixtures_path.to_str().unwrap(),
    );

    assert!(output.contains("ROUND_TRIP_OK"), "{output}");
}

#[test]
fn generated_client_plays_against_a_real_server() {
    let Some(godot) = godot_binary() else {
        return;
    };
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let address = runtime.block_on(async {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let config = Config {
            bot_delay: Duration::ZERO,
            ..Config::new(SessionSecret::new(vec![7; 32]).unwrap())
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

    let output = run_script(
        &godot,
        "live-game",
        "live_game.gd",
        &format!("http://{address}"),
    );

    assert!(output.contains("LIVE_OK"), "{output}");
}
