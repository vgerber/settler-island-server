# Godot client, milestone 1: a guest plays a full game against bots

Godot 4.7.2 (`~/Software/godot/godot`, or `$SETTLER_GODOT`), GDScript with static types everywhere. The game project is
`client/godot/` itself; the generated API in `client/godot/settler_island_api/` is already inside it (never edit it,
regenerate with `cargo run -p settler_island_client_generator`). 2D, desktop window 1600x900, scales with the window.
Read `client/README.md` first. The server must be running for live tests:
`SETTLER_BIND=127.0.0.1:8253 SETTLER_SESSION_SECRET=<any> cargo run -p settler_island_server` (see client/README.md) (in-memory store when no database URL is set;
stop it by exact PID afterwards).

## Layout (client/godot/)
- `project.godot`: main scene `scenes/main.tscn`; autoload `Net` = `scripts/net.gd`.
- `SiGuestSession.gd` stays where it is (hand-written).
- `scripts/net.gd` (autoload `Net`): owns one `SiClient` and the session. API:
  `start(server_http: String, name: String)` (guest token, WebSocket, `Authenticate`), `var user: SiUser`,
  `var client: SiClient`, signals `online(user: SiUser, running_lobby: Variant)`, `failed(reason: String)`.
  The guest token is stored in `user://session.cfg` so a restart of the client rejoins as the same guest; when
  `Welcome.running_lobby` is set, the client joins that lobby and lands in the game.
- `scripts/game_state.gd` (`class_name GameState`, RefCounted, owned by the game screen): the latest
  `seat`, `view: SiPlayerView`, `legal_actions: Array[SiAction]`, last `events`; signal `changed(events: Array[SiEvent])`;
  `func act(action: SiAction)` sends via `Net.client`; helpers `legal_of(script: Script) -> Array[SiAction]` (all legal
  actions of one variant class) and `is_my_turn()`. Fed from `game_started_received` and `game_update_received`.
- Screens (one scene + script each, swapped by `main.gd`): `connect` (server URL, default `http://127.0.0.1:8253`,
  name), `lobby_browser` (list, refresh, create with seats 3/4 + points to win + bot difficulty, join),
  `lobby_room` (seats, add/remove bot for the owner, start, leave), `game`.
- `game` scene children: `Board` (`scripts/board/*.gd`, step 2) and `Hud` (`scripts/hud/*.gd`, step 3). Both get the
  same `GameState` via `func bind(state: GameState)` and never talk to `Net` directly.

## Rules for the UI
- The server's `legal_actions` drive everything: a button or click target exists only when a matching legal action
  exists, and the client sends that very action object. No rule logic in GDScript beyond picking among legal actions.
- Errors from the server show as a toast; they never crash or freeze a screen.
- Code style as in AGENTS.md (full names, flat functions, comments say why).

## Step 1 (agent `godot-shell`): project, Net, screens up to the game screen
Project, autoload, the four screens, `GameState`, a placeholder `game` scene that shows phase, current seat and the
legal action count, and a "End turn"/"Roll" button picked from legal actions. Update
`settler_island_client_generator/tests/godot.rs` so the test project copies only `SiGuestSession.gd` from
`client/godot` (not `project.godot` or game scripts), and add `client/godot/` paths to `client/README.md` and
`client/.gitignore` as needed. Headless test `client/godot_tests/` or a new test in `godot.rs`: `GameState` fed from a
real game reaches a finished game when it always sends the first legal action (proves the wiring).

## Step 2 (agent `godot-board`): board rendering and picking (parallel with step 3)
Pointy-top hexes from `SiTile.coordinates` (cube q, r, s; corner `i` of a tile lies between neighbour `i` and `i+1`,
see `settler_island_game/src/coordinates.rs` for the direction order). Corner and edge positions derive from tile
corners. Draw terrain colours, number chips (6 and 8 red, pips), ports at their coast corners, the robber, roads,
settlements and cities in seat colours. Highlight targets of the legal actions (`PlaceSettlement`, `PlaceRoad`,
`BuildSettlement`, `BuildRoad`, `BuildCity`, `MoveRobber`, `PlayKnight`'s robber move if separate) and send the
matching action on click; hover feedback. Fits and centres the island in its rect. Screenshot check: render a board
from a seeded view to PNG (see Verification) and look at it.

## Step 3 (agent `godot-hud`): turn interface (parallel with step 2)
Own hand with counts, other players (cards, dev cards, points, knights, longest road/largest army), dice result, bank,
whose turn and phase, event log (readable lines from `events`). Buttons from legal actions: roll, end turn, buy
development card, play knight/road building/year of plenty/monopoly (a picker over the legal variants), bank trade
(give/receive picker over the legal `BankTrade` actions), discard dialog (choose cards until the required count;
send the matching legal `Discard`), steal target picker, player trade: offer builder for the current player and
accept/reject for addressed seats, confirm/cancel for the offerer. Game over overlay with the winner and "back to
lobbies".

## Verification
- Headless: `~/Software/godot/godot --headless --path client/godot --import` must report no script errors; tests run
  through `cargo test -p settler_island_client_generator` like the existing ones.
- Screenshots: a script run windowed for a moment (`--path client/godot -s tools/screenshot.gd -- <out.png>` style,
  quitting itself after saving `get_viewport().get_texture().get_image()`), output under `.build/`. The display is
  the user's desktop: keep windows short-lived, never leave Godot running, and always pass `--position 200,200`
  so the window opens on the left monitor (the right one, x 2560-5120, may run a fullscreen game).
- `tools/check.sh` stays green; commit subject-only conventional messages, no attribution lines.

## Acceptance
A person can start the server and the client, enter a name, create a lobby, add three bots, start, and play to the end
with only mouse input; closing and reopening the client rejoins the running game.
