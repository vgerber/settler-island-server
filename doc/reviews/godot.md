# Godot client review

Lead review over four slices (core, board, HUD, tests). Every high and medium slice finding was checked
against the code; duplicates are merged and cross-slice findings added. Paths are relative to the repo root;
`client/godot/` is shortened to `godot/`.

## Summary

The client has a clean shape: one `Net` autoload owns the socket, `GameScreen` owns `GameState`, Board and
Hud read only `GameState`, and every control sends an action taken from `legal_actions`. The weak points
show up where the coming work (EventPlayer, HUD layout restructure, Board3D) will push: `GameState.changed`
means three different things, Board's public surface is 2D pixel math, and the board/HUD split is held
together by copied constants. Colour has one documented source (`Palette`), but the theme builder, the HUD
and two wrapper layers do not use it, and the HUD still has its pre-walnut slate look. Many contracts are
stringly typed (click-target dictionaries, `action.get("corner")`, picker property names, `"give"`/`"receive"`,
resource-order arrays) where the generated typed classes could make drift fail at parse time. The Godot test
harness works and catches script errors, but every test repeats its scaffolding, re-imports the project and
cannot share helper scripts, so helpers are copied between `.gd` tests.

## Findings

Ranked by value to the project.

### 1. `GameState.changed` carries three meanings (high, structure)
- **Where:** `godot/scripts/game_state.gd:6,56,82,93,113`; `godot/scripts/hud/hud.gd:52-60`; `godot/scripts/board/board.gd:32-35`
- **Why:** One signal fires for a server update (new events), for a local send and a rate-limit take-back
  (empty events, only legal actions changed), and for a resync via `GameStarted` (empty events; `Hud.bind`
  replays `state.events` separately). `view` and `legal_actions` are overwritten before the emit. The planned
  EventPlayer (`doc/plans/godot-ui-design.md`, `doc/plans/godot-3d.md`) needs a shown state separate from
  the latest server state, and each listener would have to work out why the signal fired.
- **Fix:** Before the EventPlayer lands, split it into `snapshot_received(view, events, is_resync)` and
  `legal_actions_changed()`. The EventPlayer listens to the first and publishes the shown view; Board and Hud
  listen to the EventPlayer. Take `events` out of GameState's public fields.

### 2. No board interface: Board3D cannot be swapped in, and callers use 2D internals (high, structure)
- **Where:** `godot/scripts/screens/game_screen.gd:5`; `godot/scenes/game.tscn:3,16`;
  `godot/scripts/board/board.gd:15-21,38-49`; `godot/tools/board_screenshot.gd:53-60`;
  `client/godot_tests/board_test.gd:77,99,124,140`; `client/godot_tests/ui_game.gd:248,375`
- **Why:** `GameScreen` types `_board` as `Board`, and the scene bakes in `board.gd`. Board's public surface is
  `bind` plus writable `state`, `hex_size`, `origin`, `geometry`, `to_pixels` and `corner_position`. Tests and
  tools compute click points with `board.to_pixels(BoardGeometry.tile_center(...))`, which only works for a
  flat projection. `tile_corner_position` exists only for `board_test.gd:140`, which AGENTS.md forbids
  ("no test-only methods").
- **Fix:** Add a `BoardView` base (extends Control) with `bind(state)`, `targets() -> Array[BoardTarget]`
  and `screen_position(target) -> Vector2` (Board3D can use `Camera3D.unproject_position`). Type
  `_board` as `BoardView` and instantiate it into a slot. Make `hex_size`, `origin` and `geometry` private.
  Move tests and tools to `targets()`/`screen_position()`. Delete `tile_corner_position` and check corner
  agreement with `BoardGeometry.tile_corner` in hex units.

### 3. Click targets are untyped dictionaries read through a private field (high, by-design)
- **Where:** `godot/scripts/board/board.gd:22-23,74-85`; `godot/scripts/board/board_painter.gd:128-132,387-413`;
  `client/godot_tests/ui_game.gd:248`; `godot/tools/board_screenshot.gd:52-60`
- **Why:** `{action, kind, point}` is a string-keyed Dictionary, `_hovered` uses `{}` for "none", and
  `ui_game.gd` reads it with `board.get("_targets")`, which goes null without an error after a rename.
  `board_screenshot.gd` re-implements target collection; its copy already drifted (no edge targets, the robber
  overwrites a corner, `Vector2.ZERO` used as "not found"). `action.get("corner")`/`get("edge")`
  (board.gd:76,79, board_painter.gd:413) read typed generated fields by string.
- **Fix:** `class_name BoardTarget extends RefCounted` with typed `action`, `kind`, `point`; `_hovered:
  BoardTarget` (null for none); public `targets()`. The screenshot tool hovers `targets()[0]`. Cast actions
  (`(action as SiActionBuildRoad).edge`) or keep the field name next to the class in one table.

### 4. Colours have one documented source that three places bypass (high, reuse)
- **Where:** `godot/tools/build_theme.gd:11-18` and literals at `:84-91,160,170,201,207,236,239,251,263,294`;
  `godot/scripts/hud/hud_ui.gd:5-7,66-68`; `godot/scripts/hud/hud.gd:23,152,217-225`;
  `godot/scripts/hud/hud_players.gd:19`; `godot/scripts/hud/hud_trade_panel.gd:8,15`;
  `godot/scripts/hud/hud_game_over.gd`; `godot/scripts/palette.gd:3,34-46`
- **Why:** `palette.gd` says it is "shared by the board, the HUD and the theme". The theme builder redefines
  PARCHMENT, CARD_STOCK, INK, INK_MUTED, CREAM, BORDER and FOCUS_LIGHT (= `FOCUS_ON_LIGHT`) and uses raw hex
  for PARCHMENT_DEEP (`#E6D8BA`), ACCENT, DANGER, FOCUS_ON_DARK and CREAM_MUTED. The HUD still uses the old
  dark-slate `Color(0.09, 0.12, 0.16)` panels, a gold hint and other unnamed literals, with per-node overrides,
  while the screens moved to the walnut theme (8976b20). A palette change updates the board and leaves the
  theme and HUD stale; the HUD restructure would carry the slate look along.
- **Fix:** `build_theme.gd` reads `Palette` (via `preload` if the class cache is missing on a fresh checkout)
  and Palette gains the missing names (button, button hover/pressed, disabled `#7A6E5E`, `#D9CDB5`). Before the
  HUD restructure, add theme type variations (`HudPanel`, `HudDialog`, `ProminentButton`, `MutedLabel`) in
  `build_theme.gd` and set `theme_type_variation` instead of overrides; map remaining literals to Palette
  tokens.

### 5. Palette wrappers and aliases in HudText and BoardPainter (medium, reuse)
- **Where:** `godot/scripts/hud/hud_text.gd:5-21`; `godot/scripts/board/board_painter.gd:10-14,19,21,44-53`;
  `godot/scripts/palette.gd:49-73`
- **Why:** HudText aliases `SEAT_COLORS`/`RESOURCE_COLORS` and copies `seat_color`/`resource_color` line for
  line; BoardPainter forwards `seat_color`/`seat_outline`/`seat_keyline` and aliases OUTLINE, KEYLINE, CHIP,
  CHIP_TEXT, HOT_NUMBER, and repeats `#231C17` (TARGET_HALO) and `#E8A93A` (LANTERN) as literals. Three
  entry points for one colour rule; AGENTS.md forbids single-use wrappers.
- **Fix:** Delete the HudText colour constants and functions and the painter forwards; call `Palette.*`
  directly. Write `Color(Palette.OUTLINE, 0.45)` for the halo and name the lantern colour once in Palette.

### 6. Resource and seat tables depend on array order and fail silently (medium, by-design)
- **Where:** `godot/scripts/palette.gd:5,26-31,49-73`; `godot/scripts/art/resource_art.gd:10-20,38,62,66`;
  `godot/scripts/board/board_painter.gd:184-199,206,233,243,262`;
  `godot/scripts/hud/hud_discard_dialog.gd:10,33`; `godot/scripts/hud/hud_trade_builder.gd:13-14,48-49`
- **Why:** `RESOURCE_COLORS[maxi(SiResource.VALUES.find(resource), 0)]` turns a typo or a new resource into
  Clay. The colour arrays match `SiResource.VALUES` only by a comment. `ResourceArt.draw_icon` matches on
  `"Wood"`, `"Clay"` literals without a default branch (draws nothing), and `_draw_motif` falls to desert dunes.
  Six literal `[0, 0, 0, 0, 0]` count arrays hard-code the resource count. `IVORY_SEAT := 2` and
  `CHARCOAL_SEAT := 3` are right only while `SEAT_COLORS` keeps its order.
- **Fix:** Key resource colours by `SiResource.*` constants and `push_error` on a missing key; use the
  constants in every `match` with an erroring default branch; add one `empty_resource_counts()` sized from
  `SiResource.VALUES`. Store seats as one record per seat (`color, name, outline, keyline`) behind a
  single lookup. A board_test check that Palette keys equal `SiResource.VALUES` closes the loop.

### 7. Board layout copies the HUD constants by hand (medium, reuse)
- **Where:** `godot/scenes/game.tscn:24-25`; `godot/scripts/hud/hud.gd:9-10,90,112-113,163-164`
- **Why:** The Board node has `offset_right = -380.0`, `offset_bottom = -200.0`, which equal
  `Hud.COLUMN_WIDTH`/`BAR_HEIGHT` only by convention. The planned layout restructure changes those, and the
  board silently slides under the panels.
- **Fix:** One owner for the layout: containers in `game.tscn` with the board as the expanding child, or
  `GameScreen` sets the board rect from a `Hud.reserved_area()` at bind time.

### 8. `hud.gd` holds layout, prompts, legal-action queries and the action bar (medium, structure)
- **Where:** `godot/scripts/hud/hud.gd` (405 lines): hints `:239-282`, picker queries `:331-405`, action bar
  `:134-156`; `godot/scripts/hud/hud_text.gd:57-78`
- **Why:** The prompt logic, generic legal-action filtering (`_picker_options`, `_distinct`, `_matches`,
  `_bank_rate`) and the action-bar table live beside the layout. `layout.md` splits these into separate
  regions, so the restructure becomes a rewrite, and none of the pure logic is testable without the node tree.
  `_hint` and `HudText.phase_text` also phrase the same steps twice.
- **Fix:** Move prompt text to a static `HudText.prompt(state)` (one source; keep `phase_text` only if the
  log needs it), legal-action queries to `GameState` or a static `LegalQuery`, the action bar to a
  `HudActionBar` node. Hud only lays out and wires regions.

### 9. Picker and event log read protocol fields by string name (medium, by-design)
- **Where:** `godot/scripts/hud/hud.gd:331-343,380-400`; `godot/scripts/hud/hud_event_log.gd:24-26`;
  `godot/scripts/hud/hud_trade_builder.gd:18-20,61-70,78-99`
- **Why:** Pickers pass `["resource"]`, `["first","second"]`, `["give","receive"]` and read them with
  `action.get(property)` compared through `str()`: a protocol rename makes `get` return null and the dialog
  opens with every button disabled, no error. The event log tints only events with a `seat` field found by
  `event.get("seat")` (thief and holder events stay untinted). The trade builder's `side: String` selects
  `_give`/`_receive` four times, and any typo edits the receive side.
- **Fix:** Typed extractor callables per picker (`func(action: SiActionBankTrade): return [action.give,
  action.receive]`); `HudText.event_actor(event) -> int` typed per variant; `enum Side { GIVE, RECEIVE }`
  with counts indexed by side.

### 10. The "may offer a trade" rule lives in three places (medium, reuse)
- **Where:** `godot/scripts/game_state.gd:45-48`; `godot/scripts/hud/hud.gd:296-299,312-315,328`
- **Why:** "EndTurn is legal" stands in for "may offer" in `GameState.offer_trade`, `Hud._can_offer_trade`
  and as the `SiActionEndTurn` script passed to the trade builder as `depends_on`. A dropped offer is silent,
  unlike `act`.
- **Fix:** `GameState.can_offer_trade() -> bool`, used by all three; `push_warning` when an offer is dropped.
  Longer term, have the protocol state offer permission explicitly.

### 11. Error display has no owner; `refused` has no listener (medium, structure)
- **Where:** `godot/scripts/game_state.gd:8,96-104`; `godot/scripts/main.gd:25,80-84`
- **Why:** Nothing connects to `GameState.refused`. `main.gd` toasts every server error, including the
  `RateLimited` error that `GameState` already recovers from silently. When in-game feedback arrives, errors
  will show twice or not at all.
- **Fix:** GameState emits `refused` for its own requests and swallows `RateLimited`; the HUD shows `refused`;
  `main.gd` toasts only errors no screen claimed (e.g. a `handles_error(message) -> bool` on the current
  screen). Otherwise delete the signal.

### 12. Net leaves the socket open on failure paths (medium, calls)
- **Where:** `godot/scripts/net.gd:41-52,107-111,143-155`
- **Why:** `_fail` clears `_socket_opened` but never closes. When a refused stored token triggers a fresh guest
  session and that request fails, the socket stays connected and unauthenticated; the next `start()` calls
  `connect_to_url` without closing. Only the login-refused path calls `stop()` itself.
- **Fix:** Make `_fail` the single exit: clear `_socket_opened`, `client.close()`, reset `_reauthenticating`
  and `_authenticate_request`. `start()` closes any previous socket first; line 149's `stop()` goes.

### 13. Godot test harness: repeated scaffolding, one import per test, no shared helpers (medium, structure)
- **Where:** `settler_island_client_generator/tests/godot.rs:70-82,159-163,344-361,386-438,501-610`;
  `client/godot_tests/board_test.gd:7-14,27-29,37,51-63,147-159`; `client/godot_tests/game_state_test.gd:6-30`;
  `client/godot_tests/ui_game.gd:57,397-412`; `client/godot_tests/hud_discard.gd:11-13,81-92`;
  `client/godot_tests/round_trip.gd:30-32`; `godot/tools/screenshot.gd:17-26,97-100`;
  `godot/tools/board_screenshot.gd:17-25,63-73`
- **Why:** Every Rust test repeats skip / write fixture / `prepare_*` / `run_script` / marker assert and types
  the script name twice; fixtures land outside the test root. `prepare_game_project` copies all of
  `client/godot` and `run_script` re-imports it for each of six tests. Because only one `.gd` is copied, a
  test cannot use a helper script: `RecordingClient` is identical in two tests, the synthetic click sequence
  exists in three places, fixture loading in three, and pass/fail reporting is done five different ways. The
  screenshot tools copy each other's argument check and frame countdown and `quit(0)` after a failed
  `save_png`.
- **Fix:** Build and import the game project once per test binary (`OnceLock`), copying all of
  `client/godot_tests/*.gd` into `res://tests/`. Add `test_support.gd` (`RecordingClient`, `click`,
  `read_fixture`, `expect`, `finish` printing one `<NAME>_OK`/`_FAILED` line). In Rust, one
  `run_godot_test(project, script, argument)` helper. Tools quit non-zero on save or parse failure.

### 14. Round trip does not prove every variant is exercised (medium, tests)
- **Where:** `settler_island_client_generator/tests/godot.rs:177-201`; `client/godot_tests/round_trip.gd:7-27`
- **Why:** The fixture comment claims "all events occur", but which Event, Action, Phase and ErrorCode
  variants appear depends on bot seed 11. A new variant, or a bot change, silently leaves that variant's
  generated `from_dict`/`to_dict` untested. `hud_event_log.gd:35-48` already has the right pattern.
- **Fix:** In `round_trip.gd`, list the generated `Si<Base><Variant>.gd` files for the message, event,
  action, phase and error-code bases and fail on any variant missing from the fixtures (or check the JSON
  schema's tags on the Rust side). Share the variant-listing helper with `hud_event_log.gd` via item 13.

### 15. `ui_game` coverage hangs on seeds and labels split across Rust and GDScript (medium, tests)
- **Where:** `client/godot_tests/ui_game.gd:11-18,220,248,313-341`; `settler_island_client_generator/tests/godot.rs:24,428`;
  `client/godot_tests/hud_discard.gd:27`; `godot/scripts/hud/hud.gd:142-145`; `godot/scripts/hud/hud_game_over.gd:27`
- **Why:** The promised discard, knight, steal and trade coverage depends on server seed 4 in Rust and SEED,
  POINTS_TO_WIN in GDScript; `UI_GAME_OK` lists what was used but asserts nothing. Controls are found by
  display label ("End turn", "Offer trade...") and by `get_index() % 7 == 6` for the trade grid; private
  fields are read with `get("_targets")`/`get("_discard_dialog")`. The 80 ms step is tuned to the server's
  rate limit, the 100 s script timeout to `GODOT_TIMEOUT`, with no link.
- **Fix:** Pass seeds, step delay and timeout from `godot.rs` as script arguments; fail when the promised
  features were not used. Label constants in HudText used by HUD and test (or node metadata); find dialogs by
  type as `ui_game.gd` already does; public `Board.targets()` (item 3).

### 16. Hand-written protocol JSON in `.gd` tests can drift (medium, by-design)
- **Where:** `client/godot_tests/hud_event_log.gd:51-83`; `client/godot_tests/game_state_test.gd:40-42`
- **Why:** Every SiEvent sample and the `{"type": "RateLimited"}` error are typed by hand. A field rename in
  Rust makes `from_dict` fill a default and the test still passes. The other fixtures are generated from
  Rust types precisely to avoid this.
- **Fix:** Build the samples in `godot.rs` from `settler_island_game::Event` and `ErrorCode` values with
  `to_json` and pass them as a fixture; keep the variant-coverage check in GDScript.

### 17. No test for replacing a stale stored token (medium, tests)
- **Where:** `godot/scripts/net.gd:97-105,143-150`; `client/godot_tests/full_game.gd:119`
- **Why:** The InvalidToken path (fresh guest session, re-authenticate on the same socket) depends on three
  flags and is what happens after a secret rotation or database reset; only the valid-token reconnect is
  tested.
- **Fix:** A godot_tests script that writes `session.cfg` with a bogus token, calls `Net.start`, and asserts
  `online` fires, `failed` does not, and the stored token changed.

### 18. HUD rebuilds every widget on every change (low, calls)
- **Where:** `godot/scripts/hud/hud.gd:70-85,198-236`; `godot/scripts/hud/hud_players.gd:11-14`;
  `godot/scripts/hud/hud_hand.gd:18-25`; `godot/scripts/hud/hud_trade_panel.gd:74-84`
- **Why:** Each `changed` (including every own act) frees and recreates bank, dice, player rows, hand and
  trade buttons, losing hover and focus; the EventPlayer will refresh more often. `_refresh_bank` calls
  `_refresh_dice`, a hidden coupling.
- **Fix:** Build fixed widgets once and update them; rebuild only the variable lists when their legal actions
  change; call `_refresh_dice` from `_refresh`. Do it as part of the HUD restructure.

### 19. Font sizes and click targets are magic numbers below `layout.md` minimums (low, structure)
- **Where:** `godot/scripts/hud/hud_ui.gd:35,43`; `godot/scripts/hud/hud.gd:11-23,96,125,150,203,212`;
  `godot/scripts/hud/hud_event_log.gd:15`; `godot/scripts/hud/hud_resource_picker.gd:79`
- **Why:** `layout.md` sets 18-unit minimum font and 40x40 targets; `HudUi.button` uses height 36 and call sites
  patch it to 40; labels use 12-17.
- **Fix:** Named sizes in HudUi or theme font sizes; `HudUi.button` enforces the minimum.

### 20. Board repaints everything on hover; dead `pulse` parameter (low, calls)
- **Where:** `godot/scripts/board/board.gd:100-105,124-134`; `godot/scripts/board/board_painter.gd:128-154,387`
- **Why:** A hover change redraws sea, wave grid, tiles, chips and pieces. `pulse` is documented as driven by a
  clock in Board that does not exist; it is always 1.0.
- **Fix:** Draw targets on a child overlay that redraws on hover (also the split Board3D needs). Remove `pulse`
  until an animation exists.

### 21. Generated-looking hand-written `SiGuestSession.gd`; WebSocket URL built twice (low, structure)
- **Where:** `godot/SiGuestSession.gd`; `settler_island_client_generator/tests/godot.rs:25-26,62-66`;
  `godot/scripts/net.gd:10,110`; `client/godot_tests/live_game.gd:47`
- **Why:** The file has the generated `Si` prefix but is hand-written and copied into the API test project by
  name. `live_game.gd` builds `ws://.../api/v1/ws` itself, without `wss://` handling, copying `net.gd`.
- **Fix:** Generate the guest session and a `SiClient.websocket_url(server_http)` into `settler_island_api/`,
  or rename the file; use the one URL helper in both places.

### 22. Smaller items (low)
- **Seat labels:** `Palette.SEAT_NAMES` is unused; "Seat %d" is formatted in `hud_text.gd:27` and
  `lobby_room_screen.gd:45`. One `seat_label` function, or delete the constant.
- **Difficulty OptionButton:** fill/select/read from `SiDifficulty.VALUES` repeated in
  `lobby_browser_screen.gd:28,91` and `lobby_room_screen.gd:16,29,71`; `select(find(...))` gets -1 on unknown.
  One small shared script.
- **Session file:** `net.gd:66-87` and `connect_screen.gd:22-25` parse `session.cfg` twice and repeat the
  key strings; one typed `StoredSession`.
- **Geometry rebuild:** `board.gd:52-56` guesses a new game from the corner count, and `bind` reconnects
  without a guard; build `geometry` once in `bind`.
- **Dialog closing:** `hud.gd:228-236` polls a hard-coded list of dialogs; the discard dialog closes itself.
  One `HudDialog.sync(state)` hook called for all dialogs.
- **`HudActionList`/action bar:** `[Button, Callable]` and `[String, SiAction]` pairs (`hud.gd:30-31,319-324`)
  need casts; typed arrays or an inner class.
- **Build costs:** `hud.gd:11` repeats the rule engine's costs as English text; at least move it into HudText
  with a pointer to the Rust source.
- **Fixture builders in `godot.rs`:** `discard_fixture` and `fixtures` rebuild `GameStarted` inline although
  `game_started()` exists; `GameSettings { seats: 4, points_to_win: 10, seed }` is written four times; the
  record-to-actions map appears twice here and in the bot harness and server tests (a `Record::actions()` in
  `settler_island_game` would serve all).
- **`DEFAULT_GODOT`** (`godot.rs:23`) hard-codes one home directory; resolve from `$HOME`.
- **Leak check:** `run_godot` (`godot.rs:148-151`) ignores "ObjectDB instances leaked at exit", so the manual
  frees in the tests verify nothing; fail on that line.

## Dropped

- **Edge midpoint and hexagon centre recomputed** (board_geometry.gd:31,65; board_painter.gd:430-436): two
  one-line formulas, negligible cost; not worth a change on its own. Fold it into the overlay work of item 20
  if touched.
- **build_theme literal lists, `bg` name, untyped margin array** (build_theme.gd:133-145, 153, 205, 248, 258,
  292): mostly a tool-local nit; the colour part is covered by item 4.
- **Prompt text vs phase text as its own finding:** merged into item 8.
- **"Offer trade" proxy in core slice:** merged with the HUD slice's finding into item 10.
- **HudText colour duplication (core and HUD slices) and BoardPainter wrappers:** merged into item 5.
- **Trade builder side and untyped pairs as separate findings:** merged into items 9 and 22.
- **Separate "board_screenshot re-implements targets" and "tile_corner_position test-only":** merged into
  items 2 and 3.
- **Discard test private field access as its own finding:** merged into item 15.

## Good, keep

- `GameState` keeps the stale-legal-actions invariant explicit: `_send` empties `legal_actions` until the
  matching reply, and the rate-limit take-back returns the previous choices (game_state.gd:51-113).
- Clear ownership: `Net` owns the single `SiClient` and session; `GameScreen` owns `GameState` and releases it
  on exit; Board and Hud read only `GameState`, never `Net`.
- Board and HUD offer only actions taken from `legal_of`, so the UI cannot send an illegal move (except
  documented trade offers).
- `BoardGeometry` is pure hex-unit math, separate from pixels and drawing, ready for reuse by Board3D.
- `main.gd` swaps screens synchronously with the reason documented, so messages in the same frame reach the
  new screen.
- `build_theme.gd` generates `main_theme.tres` and the font resources from sources, so nothing is hand-edited.
- `hud_event_log.gd` checks coverage against the generated `SiEvent*.gd` files; most fixtures come from real
  Rust types and real bot games.
- `run_godot` isolates XDG dirs per test, kills only its own child on timeout and fails on `SCRIPT ERROR`.
- `ui_game.gd` drives the real main scene by mouse only and prints useful diagnostics on dead ends.
- Comments are one-line "why" notes, and screens use unique-name `%Node` references.
