# Settler Island Godot client

`schema.json` and `godot/settler_island_api/` are generated from the protocol types in `settler_island_protocol`;
never edit them by hand. The rest of `godot/` is the hand-written game project (Godot 4.7, typed GDScript).

- `schema.json`: JSON Schema of `ClientMessage`, `ServerMessage` and the HTTP session bodies (definitions under `$defs`).
- `godot/settler_island_api/`: Godot 4 GDScript, one `Si<Type>.gd` per schema type, plus the `SiClient` node, the
  `SiSessionClient` node for the HTTP session routes, and `SiLimits` (limits, purchase costs, default port, routes).
- `godot/project.godot`, `godot/scenes/`, `godot/scripts/`: the game (see below).
- `godot/tools/screenshot.gd`: walks the screens against a running server and saves a PNG of each.
- `godot/tools/board_screenshot.gd`: renders the game screen for the board fixtures that the Godot board test
  writes to `target/tmp/godot-board-fixtures.json` and saves a PNG of each.
- `godot/tools/game_screenshots.gd`: renders the game screen in five states (setup placement, own Main turn with build
  mode armed, a 7 with discard, a trade offer, game over) from the same fixtures; run it at `--resolution 1600x900` and
  `1280x720` with `--position 200,200`.
- `godot_tests/`: headless test scripts used by `settler_island_client_generator/tests/godot.rs`.

## Game project

`godot/` is the desktop client; `scenes/main.tscn` swaps four screens (`connect`, `lobby_browser`, `lobby_room`,
`game`) on what the server sends.

- `scripts/net.gd`, autoload `Net`: the one `SiClient`, guest login, `online`/`failed` signals. The guest token is
  kept in `user://session.cfg`, so a restarted client logs in as the same guest and rejoins its running game.
- `scripts/game_state.gd`, `GameState`: the latest view and legal actions of the own seat; `act` sends one of them.
  The game screen owns it and hands it to `Board` (`scripts/board/`) and `Hud` (`scripts/hud/`) via `bind`.
- The server's legal actions drive the UI: a button exists only for a legal action and sends that very action.

Run a local server (in-memory store) and the client:

```sh
SETTLER_BIND=127.0.0.1:8253 SETTLER_SESSION_SECRET=<32+ bytes> cargo run -p settler_island_server
~/Software/godot/godot --path client/godot
~/Software/godot/godot --path client/godot -s tools/screenshot.gd -- http://127.0.0.1:8253 "$PWD/.build"
```

The test project copies only the generated API from `godot/`; the full-game test copies all of `godot/` (without
`.godot/`) and plays a game through `Net` and `GameState`, reconnecting midway. `ui_game.gd` runs the real main scene and plays
a whole game by clicking HUD buttons, dialogs and highlighted board targets (seeded random choices); it fails
on a dead end, a click that misses its control or a game that does not finish.

## Regenerate

```sh
cargo run -p settler_island_client_generator            # rewrite client/
cargo run -p settler_island_client_generator -- --check # exit 1 when client/ is stale
```

`cargo test --workspace` fails while the committed output is stale. The Godot tests run when Godot is at
`/home/vincent/Software/godot/godot` or `$SETTLER_GODOT`, and pass with a notice otherwise.

## Use in a Godot project

Symlink (or copy) the API folder into the project; Godot picks up the `class_name`s on the next scan:

```sh
ln -s /path/to/settler-island-server/client/godot/settler_island_api /path/to/game/addons/settler_island_api
```

## Types

- Structs become classes with typed properties, `static func from_dict(data) -> Si<Name>` and `func to_dict()`.
- Tagged enums (`Action`, `Event`, `ServerMessage`, ...) become a base class whose `from_dict` picks the variant
  class `Si<Enum><Variant>` by its tag; check the variant with `is`, e.g. `action is SiActionBuildRoad`.
- String enums (`Resource`, `Difficulty`, ...) stay plain strings; `SiResource.ORE` and `SiResource.VALUES` name them.
- Id newtypes and fixed arrays (`TileId`, `ResourceCounts`) map to `int` and `Array[int]`.
- `Option` fields are `Variant` (or the class type) holding `null` when absent.

## Example

A guest first gets a token over HTTP with `SiSessionClient` (`POST SiLimits.GUEST_SESSION_ROUTE` with a
`SiGuestSessionRequest`, answered by a `SiGuestSession`), then sends `Authenticate` as the first message. A refused
request emits `failed` with the server's `SiHttpError` message:

```gdscript
extends Node

var client := SiClient.new()
var session := SiSessionClient.new()
var server := "http://127.0.0.1:%d" % SiLimits.DEFAULT_PORT
var token := ""

func _ready() -> void:
	add_child(client)
	add_child(session)
	session.guest_session_received.connect(_on_session)
	session.failed.connect(func(reason, _error): push_warning(reason))
	session.request_guest_session(server, "Ada")

func _on_session(guest: SiGuestSession) -> void:
	token = guest.token
	client.connected.connect(func(): client.send_authenticate(token))
	client.welcome_received.connect(_on_welcome)
	client.game_update_received.connect(_on_game_update)
	client.error_received.connect(func(message): push_warning(message.message))
	client.connect_to_url(server.replace("http://", "ws://") + SiLimits.WEBSOCKET_ROUTE)

func _on_welcome(message: SiServerMessageWelcome) -> void:
	print("logged in as ", message.user.name)
	client.send_list_lobbies(0, 20)

func _on_game_update(message: SiServerMessageGameUpdate) -> void:
	for event in message.events:
		if event is SiEventDiceRolled:
			print("rolled ", event.first + event.second)
	if not message.legal_actions.is_empty():
		client.send_act(message.legal_actions[0])
```

## Graphics quality

`project.godot` sets the renderer to Compatibility (also for web). The settings popup offers `Graphics: High` on
desktop; it writes `rendering/renderer/rendering_method="forward_plus"` into `override.cfg` in the executable's
directory (and removes the file for `Standard`), and applies after a restart. Checked with Godot 4.7.2 and a pack
next to the binary: `override.cfg` beside the executable switches `RenderingServer.get_current_rendering_method()`
to `forward_plus`. Runs of the editor binary with `--path` (development) ignore the executable directory, and
the file is skipped when that directory is not writable; start with `--rendering-method forward_plus` then.
