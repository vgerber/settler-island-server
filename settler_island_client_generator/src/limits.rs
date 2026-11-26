//! `SiLimits.gd`: the protocol's limits, purchase costs, default port and HTTP routes as GDScript
//! constants, and `SiSessionClient.gd`, the HTTP helper for the session routes.

use std::fmt::Write;

use settler_island_protocol::{
    Purchase, Resource, DEFAULT_POINTS_TO_WIN, DEFAULT_PORT, GUEST_SESSION_ROUTE, HEALTH_ROUTE,
    MAX_LOBBIES_PER_PAGE, MAX_LOBBY_NAME_CHARS, MAX_POINTS_TO_WIN, MAX_SEATS, MAX_USER_NAME_CHARS,
    MIN_POINTS_TO_WIN, MIN_SEATS, UPGRADE_SESSION_ROUTE, WEBSOCKET_ROUTE,
};

use crate::gdscript::HEADER;

pub const LIMITS_FILE: &str = "SiLimits.gd";
pub const SESSION_CLIENT_FILE: &str = "SiSessionClient.gd";

// The game crate has no list of every purchase; the keys of `SiLimits.COSTS`.
const PURCHASES: [Purchase; 4] = [
    Purchase::Road,
    Purchase::Settlement,
    Purchase::City,
    Purchase::DevelopmentCard,
];

pub fn limits_class() -> String {
    let integers = [
        ("MIN_SEATS", MIN_SEATS.to_string()),
        ("MAX_SEATS", MAX_SEATS.to_string()),
        ("MIN_POINTS_TO_WIN", MIN_POINTS_TO_WIN.to_string()),
        ("MAX_POINTS_TO_WIN", MAX_POINTS_TO_WIN.to_string()),
        ("DEFAULT_POINTS_TO_WIN", DEFAULT_POINTS_TO_WIN.to_string()),
        ("MAX_USER_NAME_CHARS", MAX_USER_NAME_CHARS.to_string()),
        ("MAX_LOBBY_NAME_CHARS", MAX_LOBBY_NAME_CHARS.to_string()),
        ("MAX_LOBBIES_PER_PAGE", MAX_LOBBIES_PER_PAGE.to_string()),
        ("DEFAULT_PORT", DEFAULT_PORT.to_string()),
    ];
    let routes = [
        ("WEBSOCKET_ROUTE", WEBSOCKET_ROUTE),
        ("GUEST_SESSION_ROUTE", GUEST_SESSION_ROUTE),
        ("UPGRADE_SESSION_ROUTE", UPGRADE_SESSION_ROUTE),
        ("HEALTH_ROUTE", HEALTH_ROUTE),
    ];
    let mut output = format!(
        "{HEADER}class_name SiLimits\nextends RefCounted\n## Limits the server enforces, purchase costs, the default port and the HTTP routes.\n\n"
    );
    for (name, value) in integers {
        let _ = writeln!(output, "const {name} := {value}"); // Writing to a String cannot fail.
    }
    output.push('\n');
    for (name, path) in routes {
        let _ = writeln!(output, "const {name} := {}", quoted(path)); // Writing to a String cannot fail.
    }
    output.push_str(
        "\n## What each purchase costs, counted in `SiResource.VALUES` order.\nconst COSTS: Dictionary[String, Array] = {\n",
    );
    for purchase in PURCHASES {
        let cost = purchase.cost();
        let counts: Vec<String> = Resource::ALL
            .iter()
            .map(|resource| cost.get(*resource).to_string())
            .collect();
        // Writing to a String cannot fail.
        let _ = writeln!(output, "\t\"{purchase:?}\": [{}],", counts.join(", "));
    }
    output.push_str("}\n");
    output
}

pub fn session_client_class() -> String {
    format!("{HEADER}{SESSION_CLIENT}")
}

fn quoted(text: &str) -> String {
    serde_json::Value::String(text.to_string()).to_string()
}

const SESSION_CLIENT: &str = "class_name SiSessionClient
extends Node
## HTTP requests to the session routes. Add it to the scene tree, call `request_guest_session` and pass
## the token of `guest_session_received` to `SiClient.send_authenticate`. A refused request emits `failed`
## with the server's message and its `SiHttpError`, which is null when no error body arrived.

signal guest_session_received(session: SiGuestSession)
signal upgraded_received(upgraded: SiUpgraded)
signal failed(reason: String, error: SiHttpError)

const _HEADERS: PackedStringArray = [\"Content-Type: application/json\"]


## `base_url` is the server's HTTP address, e.g. `\"http://127.0.0.1:%d\" % SiLimits.DEFAULT_PORT`.
func request_guest_session(base_url: String, user_name: String) -> Error:
\tvar request := SiGuestSessionRequest.new()
\trequest.name = user_name
\treturn _post(base_url + SiLimits.GUEST_SESSION_ROUTE, request.to_dict(), _on_guest_session)


## Links the guest of `guest_token` to the Keycloak account of `account_token`.
func request_upgrade(base_url: String, guest_token: String, account_token: String) -> Error:
\tvar request := SiUpgradeRequest.new()
\trequest.guest_token = guest_token
\trequest.account_token = account_token
\treturn _post(base_url + SiLimits.UPGRADE_SESSION_ROUTE, request.to_dict(), _on_upgraded)


func _post(url: String, body: Dictionary, on_reply: Callable) -> Error:
\tvar http := HTTPRequest.new()
\tadd_child(http)
\thttp.request_completed.connect(_on_completed.bind(http, on_reply))
\tvar error := http.request(url, _HEADERS, HTTPClient.METHOD_POST, JSON.stringify(body))
\tif error != OK:
\t\thttp.queue_free()
\t\tfailed.emit(\"cannot send the request to %s (%d)\" % [url, error], null)
\treturn error


func _on_completed(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest, on_reply: Callable) -> void:
\thttp.queue_free()
\tif result != HTTPRequest.RESULT_SUCCESS:
\t\tfailed.emit(\"cannot reach the server (result %d)\" % result, null)
\t\treturn
\tvar data: Variant = JSON.parse_string(body.get_string_from_utf8())
\tif not data is Dictionary:
\t\tfailed.emit(\"the server answered status %d without a JSON object\" % status, null)
\t\treturn
\tif status == HTTPClient.RESPONSE_OK:
\t\ton_reply.call(data)
\t\treturn
\tif not data.has(\"code\") or not data.has(\"message\"):
\t\tfailed.emit(\"the server answered status %d\" % status, null)
\t\treturn
\tvar error := SiHttpError.from_dict(data)
\tfailed.emit(error.message, error)


func _on_guest_session(data: Dictionary) -> void:
\tif not data.has(\"token\") or not data.get(\"user\") is Dictionary:
\t\tfailed.emit(\"the guest session reply is malformed\", null)
\t\treturn
\tguest_session_received.emit(SiGuestSession.from_dict(data))


func _on_upgraded(data: Dictionary) -> void:
\tif not data.get(\"user\") is Dictionary:
\t\tfailed.emit(\"the upgrade reply is malformed\", null)
\t\treturn
\tupgraded_received.emit(SiUpgraded.from_dict(data))
";
