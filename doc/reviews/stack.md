# Stack and tooling review

Lead review of two slices: tooling (gate scripts, CI, cargo and docker config) and linkage (how the protocol, server,
game, bot and Godot client share constants and types). Every high and medium finding was checked against the code on
2026-11-26 (main at dbe6aaa). Some slice line numbers were off; the locations below are corrected.

## Summary

The project already has the right pattern for preventing drift: the generated GDScript client is checked by an
ordinary unit test (`committed_client_matches_the_protocol`), so nobody has to remember to regenerate it. Most
findings come from places that do not use this pattern yet.

- **Rules kept by memory.** SQLX offline mode is set in only two places (CI and check.sh), while `.env.example`
  switches every other build to live query checking. The memory ceiling and the whole gate live in git-ignored
  `tools/`.
- **Generated or derived output with no check.** This covers the theme `.tres`, the `.sqlx` cache and the
  `.env.example` coverage.
- **Constants copied by hand.** Seat and points limits, name lengths, building costs, resource order, ports and colours
  are copied between the game, the protocol, the bot and the client. The client name length has already drifted into
  a real bug.

The single highest-value structural move is a generated limits/constants file for the client, fed from one source in
the game and protocol crates. Together with putting the HTTP session types into the schema, it turns most of the
linkage findings into stale-file test failures. On the tooling side, decide whether `tools/` is tracked. Three of the
high findings depend on that decision.

## Findings

### 1. `.env.example` turns every plain build into a live database check (high, by-design)
- **Location:** `.env.example:13` (DATABASE_URL set, no SQLX_OFFLINE); `README.md:27-29`; `.github/workflows/ci.yml:10`;
  `tools/check.sh:17`.
- **Why:** sqlx's query macros read `DATABASE_URL` and `SQLX_OFFLINE` from `.env` at compile time and check live
  whenever offline mode is not on. The README quick start is `cp .env.example .env` followed by `cargo run`. On a
  fresh clone the database is either down or empty (migrations run only at server start), so the build fails. Plain
  `cargo test` and rust-analyzer hit the same wall. AGENTS.md says "Builds use SQLX_OFFLINE=true", but only CI and
  check.sh enforce it.
- **Fix:** Add `SQLX_OFFLINE=true` to `.env.example` with a one-line comment, or set `[env] SQLX_OFFLINE = "true"` in a
  tracked `.cargo/config.toml`. `cargo sqlx prepare` overrides it with its own setting. Then drop the copies in CI and
  check.sh.

### 2. `.cargo/config.toml` depends on git-ignored `tools/` (high, tooling)
- **Location:** `.cargo/config.toml:1-2` (`runner = "tools/run_limited.sh"`); `.gitignore:9` (`tools/`);
  `.gitignore:8` (`doc/`).
- **Why:** `.cargo/` is untracked today. If it is committed as it is, every `cargo test` and `cargo run` in CI and on a
  fresh clone fails because `tools/run_limited.sh` is missing. If it is not committed, the memory ceiling that AGENTS.md
  promises applies only on this machine. The gate (`tools/check.sh`) that AGENTS.md names as the one gate has the same
  problem. `client/.gitignore` already has to un-ignore `godot/tools` because of the blanket rule.
- **Fix:** Track `tools/` (drop the line from `.gitignore`) and commit `.cargo/config.toml` with it. If `tools/` must
  stay private (project memory says doc/tools were left out on purpose), move the runner to a per-machine config, such
  as `~/.cargo/config.toml` or an ignored `.cargo/config.local`, and change AGENTS.md to say so.

### 3. `check.sh` always gates the main checkout, even when an agent runs it from a worktree (high, tooling)
- **Location:** `tools/check.sh:19-20`; `tools/worktree_new.sh:57-59,67`; `tools/merge_agent.sh:53-58`.
- **Why:** `repository="$(cd "$(dirname "$0")/.." && pwd)"` resolves to the script's own checkout. Worktrees have no
  `tools/` because it is ignored, so an agent can only call the main copy. The script then gates and stamps the lead's
  tree. The handoff asks for the "gated tree hash", and merge_agent skips the second gate when tree hashes match, so a
  green gate that never ran on the agent's tree can be reported as one that did.
- **Fix:** Use `repository="$(git rev-parse --show-toplevel)"`, which is the caller's worktree, and add a worktree case
  to the `worktree_new.sh --self-test`. If `tools/` stays ignored, have worktree_new.sh symlink it into the worktree.
- **Correction to the slice:** the claim that worktrees run tests without the memory ceiling is wrong. Worktrees live
  under `.claude/worktrees/` inside the main checkout, so cargo walks up and finds the main `.cargo/config.toml`.

### 4. Godot tests never run in CI and pass silently wherever Godot is missing (high, tests)
- **Location:** `settler_island_client_generator/tests/godot.rs:23,28-40`; `.github/workflows/ci.yml:23-24`;
  `tools/check.sh` full mode (stamps green).
- **Why:** These tests are the only coverage of the hand-written game client: UI, full game, board and HUD. When Godot
  is missing, `godot_binary()` prints a notice that cargo captures and the test passes. CI never installs Godot, and
  check.sh stamps the tree green either way. The default path is the absolute `~/Software/godot/godot`,
  while AGENTS.md says `~/Software/godot/godot`.
- **Fix:** Add `SETTLER_REQUIRE_GODOT=1`, which makes `godot_binary()` panic instead of skipping. Set it in check.sh
  full and in a CI job that downloads a pinned headless Godot 4 and sets `SETTLER_GODOT`. Build the default path from
  `$HOME`.

### 5. Client accepts 25-32 character names that the server rejects, and hides the reason (high, by-design)
- **Location:** `client/godot/scenes/connect.tscn:60` (`max_length = 32`); `settler_island_protocol/src/lib.rs:10`
  (`MAX_USER_NAME_CHARS = 24`); `client/godot/SiGuestSession.gd:25-27`.
- **Why:** This is a live bug caused by a hand-copied limit. The server answers 400 with an `HttpError {code, message}`
  body. SiGuestSession throws the body away and shows "guest session failed: result 0, status 400".
- **Fix:** Set the LineEdit limit from the generated limit (finding 6) in `connect_screen._ready` instead of the
  `.tscn`. Parse the error body in SiGuestSession into the generated error type (finding 7) and emit its message.

### 6. Limits have no single source: game, protocol and client each keep their own copy (high, reuse)
- **Location:**
  - `settler_island_game/src/game.rs:18-21` (private MIN_SEATS, MAX_SEATS, MIN_POINTS_TO_WIN)
  - `settler_island_protocol/src/lib.rs:10-18` (pub copies of the same values plus more)
  - `client/godot/scripts/screens/lobby_browser_screen.gd:6-7` (LOBBIES_PER_PAGE 50, SEAT_CHOICES [4, 3])
  - `client/godot/scenes/lobby_browser.tscn:116,141-143` (lobby name 40, points 3/15/10)
  - `client/godot/scenes/connect.tscn:60`
- **Why:** The protocol already depends on the game crate, yet it repeats the game's limits. The server validates
  lobbies against the protocol copy and `Game::new` validates against its own, so a one-sided change lets a lobby start
  with settings the game then rejects. The client copies every limit by hand because the schema carries no constants.
  The generated doc comments even name the Rust constants the client cannot reference. Finding 5 shows the drift has
  already happened.
- **Fix:**
  - Make the game limits `pub` and re-export them from the protocol
    (`pub use settler_island_game::{MIN_SEATS, MAX_SEATS, MIN_POINTS_TO_WIN}`).
  - Keep one list in the protocol, for example `pub const CLIENT_CONSTANTS: &[(&str, i64)]`, and have the generator emit
    `SiLimits.gd` from it.
  - Client scripts set SpinBox, LineEdit and seat choices from SiLimits in `_ready`.
  - The existing stale-client test then catches drift for free.

### 7. HTTP session types and route paths are outside the schema, so SiGuestSession is hand-written (medium, structure)
- **Location:**
  - `settler_island_client_generator/src/lib.rs:43-55` (the schema walks only ClientMessage and ServerMessage)
  - `client/godot/SiGuestSession.gd:15-31`
  - route paths as literals in `settler_island_server/src/lib.rs:130-139`, `client/godot/scripts/net.gd:10` and
    `SiGuestSession.gd:17`
- **Why:** GuestSessionRequest, GuestSession, UpgradeRequest, Upgraded and HttpError never reach the client. Their JSON
  keys are typed by hand as strings, and error bodies are dropped.
- **Fix:** Add these types to `protocol_schema`'s definitions so their Si* classes are generated. Define the route
  paths as protocol constants used by the axum router, and emit them with the limits from finding 6.

### 8. Building costs are defined three times (medium, reuse)
- **Location:** `settler_island_game/src/rules/building.rs:10-14`, `rules/development.rs:11` (`pub(crate)`/private);
  `settler_island_bot/src/heuristic/hand.rs:31-38` (`Build::cost` repeats the four arrays);
  `client/godot/scripts/hud/hud.gd:11` (COSTS string).
- **Why:** A rule change would update the engine only. The bot would then plan with wrong costs and the HUD would show
  wrong costs, and no test would notice.
- **Fix:** Expose the costs publicly from the game, for example `pub enum Purchase { Road, Settlement, City,
  DevelopmentCard }` with `const fn cost()`. Make `Build::cost` delegate to it (or have `Build` reuse `Purchase`). Emit
  the costs to the client with the generated constants and build the HUD label from them.

### 9. `ResourceCounts` is a positional `[u8; 5]` whose order lives only in comments (medium, by-design)
- **Location:** `settler_island_game/src/resource.rs:9-43` (enum order, `ALL`, hand-written `index()` match);
  `ResourceCounts::new([..])` call sites, including the costs in finding 8; `client/godot/scripts/hud/hud.gd`,
  `hud_hand.gd` (`SiResource.VALUES.find(name)` indexing).
- **Why:** The order is stated four times: the declaration, `ALL`, `index()` and the doc comments. Call sites pass
  bare positions such as `[0, 0, 0, 2, 3]`, which are unreadable without the comment, and the generated client sees
  only `Array[int]`.
- **Fix:** Add `#[repr(u8)]` and have `index()` return `self as usize`. Add a named const constructor for call sites.
  Have the generator map ResourceCounts to an `SiResourceCounts` helper with `get(resource)` and `set(resource, n)`
  over `SiResource.VALUES`, which keeps the wire format unchanged.

### 10. Client resource styling depends on array order and string literals, and silently falls back to Clay (medium, by-design)
- **Location:** `client/godot/scripts/palette.gd:5-20,68-73`; `client/godot/scripts/art/resource_art.gd`;
  `client/godot/scripts/board/board_painter.gd` (13 `"Wood"`/`"Clay"`/`"Ore"` literals across the scripts).
- **Why:** RESOURCE_COLORS and RESOURCE_PATTERN_COLORS rely on SiResource.VALUES order, which only a comment states.
  `maxi(find(resource), 0)` maps an unknown or renamed resource to Clay without any warning. The generated
  `SiResource.*` constants exist so that code does not have to spell the wire strings, but these scripts do.
- **Fix:** Key the colours by `SiResource.*` in dictionaries and use those constants in match arms and calls. Add a
  Godot test that the dictionary keys equal `SiResource.VALUES`. Push an error on an unknown resource instead of
  falling back to Clay.

### 11. The theme is generated output with no regeneration check, and its colours copy Palette (medium, reuse)
- **Location:** `client/godot/tools/build_theme.gd:10-17`; `client/godot/scripts/palette.gd:34-45`;
  `client/godot/theme/main_theme.tres`, `theme/fonts/*.res`.
- **Why:** Seven colours are repeated by hand: PARCHMENT, CARD_STOCK, INK, INK_MUTED, CREAM, BORDER, and FOCUS_LIGHT,
  which equals FOCUS_ON_LIGHT. A palette change leaves the theme on the old colours. Nothing detects a `.tres` that is
  out of date with its script.
- **Fix:** `build_theme.gd` preloads `res://scripts/palette.gd` and uses its constants, and BUTTON moves into Palette.
  Add a Godot test that builds the theme into a temporary copy and compares it with the committed `.tres`, the same way
  the generator's stale-client check works.

### 12. CI never runs `cargo sqlx prepare --check` (medium, tooling)
- **Location:** `.github/workflows/ci.yml:26-51`.
- **Why:** Offline builds fail only when a query has no cache entry. A leftover `.sqlx` file, or a cached type that no
  longer matches the migrations, gets through. "Run `cargo sqlx prepare` after a query change" is a step people have to
  remember, and no gate checks it. The job also reruns the whole server suite, including the in-memory tests the gate
  job already ran.
- **Fix:** In the postgres job, install a pinned sqlx-cli and run `sqlx migrate run` and
  `cargo sqlx prepare --workspace --check`. Limit the test step to the Postgres-backed test targets.

### 13. `check.sh db` hides docker failures and carries on when Postgres never becomes ready (medium, calls)
- **Location:** `tools/check.sh:94-110`.
- **Why:** `docker compose up -d db >/dev/null 2>&1` throws its output away. The 30-try `pg_isready` loop also falls
  through silently, so the user sees dozens of connection errors from the tests instead of the one cause. The
  container name is also hard-coded twice next to the compose service name.
- **Fix:** Let `docker compose up` print its output and fail the script. After the loop, exit with "settler-island-db
  not ready after 30 s". Use `docker compose exec db pg_isready` so only the service name is needed.

### 14. Default port: 8253 is a literal in four places, and three doc examples still say 8080 (low, naming)
- **Location:**
  - 8253: `settler_island_server/src/config.rs:132,272,318`, `client/godot/scripts/screens/connect_screen.gd:6`,
    `client/godot/scenes/connect.tscn:50`
  - 8080: `client/README.md:83,91`, `client/godot/SiGuestSession.gd:5`, `settler_island_client_generator/src/gdscript.rs:661`
    (which also ends up in the generated `SiClient.gd:31`)
- **Why:** Anyone who copies the examples connects to the wrong port, which is also Keycloak's container port.
- **Fix:** Add a `DEFAULT_BIND` const in config.rs and use it in `Config::new` and the tests. Drop the scene's `text`,
  since `_ready` sets it. Change the examples to 8253 and regenerate the client.

### 15. Gate scripts each keep their own help, root and branch code, and the help ranges are already wrong (low, reuse)
- **Location:** `tools/check.sh:28` (prints 2-12 of a 14-line header); `tools/worktree_new.sh:14` and
  `tools/worktree_done.sh:14` (print 2-8 of 9 lines, dropping `--self-test`). `merge_agent.sh` and
  `worktree_status.sh` are correct today.
- **Fix:** Add a sourced `tools/common.sh` with `print_header` (print up to the first non-comment line),
  `main_branch` and `repository_root`.

### 16. HudText duplicates Palette's seat and resource colour lookups (low, reuse)
- **Location:** `client/godot/scripts/hud/hud_text.gd:5-6,16-21` against `palette.gd:48-49,68-69`. HUD code makes 11
  calls through HudText, while board code uses Palette.
- **Fix:** Delete the HudText copies and call `Palette.seat_color` and `Palette.resource_color`.

### 17. CARD_NAMES is keyed by wire strings, and SEAT_NAMES is unused (low, by-design)
- **Location:** `client/godot/scripts/hud/hud_text.gd:7-13`; `client/godot/scripts/palette.gd:27` (SEAT_NAMES has no
  references).
- **Fix:** Key CARD_NAMES by `SiDevelopmentCard.*` and test the keys against `.VALUES`. Delete SEAT_NAMES. Once
  SiLimits exists, assert `SEAT_COLORS.size() >= SiLimits.MAX_SEATS`, because `seat % size` would otherwise hide a
  fifth seat.

### 18. The `.env.example` test checks only some fields and cannot see unknown keys (low, tests)
- **Location:** `settler_island_server/src/config.rs:321-340`.
- **Why:** The test does not check `trade_answer_time`, `trust_forwarded_for`, `log_format` or `database_url`. A
  misspelled key in `.env.example` loads the default and still passes.
- **Fix:** Put the variable names in one `const VARIABLES: &[&str]` used by `from_vars`. Assert that the keys in
  `.env.example` and that list are the same set.

### 19. The local Postgres URL is written out in several places (low, reuse)
- **Location:** `docker-compose.yml:6,24`; `.env.example:13`; `tools/check.sh:104`; `README.md:47`.
  CI's `:5432` URL is a different service and is fine.
- **Fix:** Add `SETTLER_TEST_DATABASE_URL` to `.env.example`, have `check.sh db` read it from there, and point the
  README at it.

### 20. worktree_new.sh prints a sabotage script path it never creates (low, tooling)
- **Location:** `tools/worktree_new.sh:7,90`.
- **Fix:** Add `tools/prove_test_bites.sh <file> <test filter>`. It reverts the fix in a `trap`, expects the test to
  fail and checks that `git diff` is clean afterwards. Print that command in the brief instead of the dead path.

### 21. Tracked files point at docs that are git-ignored or deleted by design (low, by-design)
- **Location:** `client/godot/scripts/palette.gd:3`, `art/resource_art.gd:3`, `board/board_painter.gd:4` and
  `tools/build_theme.gd:2` cite `doc/design/visual-style.md`. `hud/hud.gd:4` and `board/board.gd:4` cite
  `doc/plans/godot-client.md`, and AGENTS.md says plans are deleted when the work lands. AGENTS.md itself is untracked.
- **Fix:** Settle this together with finding 2. Either track the referenced docs, or move the few facts the scripts
  need into the scripts' own one-line comments and drop the references to plans.

## Dropped

- **The worktree part of finding 3** ("the worktree also lacks .cargo/config.toml, so tests run without the memory
  ceiling"): cargo finds the main checkout's `.cargo/config.toml` by walking up from `.claude/worktrees/<tag>`.
- **The object-keyed wire format for ResourceCounts** (an alternative in the linkage slice): it would change the
  protocol for no gain over a generated `SiResourceCounts` helper. Only the helper was kept.
- **CI's Postgres URL in the "six places" count**: it points at a different service on port 5432 and belongs to CI.
- **The slice line numbers** `.env.example:55`, `README.md:108-111` and `client/README.md:240,248` do not exist. The
  findings themselves held and were relocated.

## Good, keep

- The stale-client check is an ordinary unit test (`settler_island_client_generator/src/lib.rs:146`), so `cargo test`
  and CI catch an unregenerated `client/`. Findings 6, 7, 8 and 11 should copy this pattern.
- Bank and port rates are computed once by the engine and sent in `OwnView.bank_rates`. The HUD reads them instead of
  re-deriving the rules.
- Phases, events and error codes reach the client as typed generated classes (`is SiPhaseX`), and enums carry
  `VALUES`, so the client can dispatch without matching strings.
- check.sh stamps by tree hash, filters its output to failures and totals, and merge_agent skips a second gate on an
  identical tree. Together these keep agent context small.
- The worktree scripts have `--self-test` modes and refuse to delete dirty or unmerged work.
- The headless Godot tests isolate their XDG dirs and kill only their own child process.
- `docker-compose.yml` and `.env.example` document every setting, bind only to 127.0.0.1 and use project-named
  containers. `config.rs` loads `.env.example` through the real parser in a test.
