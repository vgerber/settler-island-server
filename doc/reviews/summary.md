# Review summary
This is the principal review over the three area reports: doc/reviews/rust.md, doc/reviews/godot.md and doc/reviews/stack.md. "rust N" means section N of rust.md. Claims marked as checked were re-read in the code on 2026-11-26.

## 1. State of the codebase
The architecture is sound and worth keeping. The rules engine is pure and validates read-only, and the same checks drive legal_actions. The server runs one actor per lobby. The GDScript client is generated, and a unit test fails when it is stale. The client sends only actions taken from the legal list.

The weak spots share one cause: facts and invariants are held by convention instead of by one owner. Rule data (costs, limits, rates, resource order) is private in the game crate, so the protocol, the bot and the Godot client copy it by hand. One copy has already drifted into a live bug: the client allows 32-character names, the server 24 (checked: connect.tscn:60, protocol lib.rs:10). "Applying a validated action cannot fail" also holds only by convention. Test scaffolding is copied in both the Rust and the Godot tests, and the gate depends on a git-ignored tools/. One runtime bug stands out: a failed JWKS fetch logs Keycloak users out for 60 s.

## 2. Top 15 (area, size)
1. JWKS refresh failure rejects valid tokens. Rust, S.
   - Where: keycloak.rs:62-102, identity/mod.rs:95-99.
   - Why: claim_refresh stamps last_fetch before the fetch. After a failed or concurrent fetch, key() returns Ok(None), and the token becomes "unknown kid" (checked).
   - Fix: stamp only after a successful fetch. Return KeysUnavailable when the cache is empty or the window was spent on a failure, and serialise refreshes. Replace the String errors with MissingKeyId, UnknownKeyId and Rejected. Add a test where the first fetch returns 500 and the second returns keys.
2. One source for limits, emitted as SiLimits.gd. Cross-area, M.
   - Where: game.rs:18-21 (private copies, checked), protocol lib.rs:10-18 and 282-293 (error texts), connect.tscn:60, lobby_browser.tscn:116,141-143, lobby_browser_screen.gd:6-7.
   - Fix: make the game limits pub, re-export them from the protocol, and build the error texts with format!. The generator emits SiLimits.gd (limits, costs, default port), and the screens read it in _ready. The stale-client test then catches drift. This also fixes the name-length bug.
3. Decide on tracking tools/ and doc/, and make check.sh gate its own worktree. Stack, M.
   - Where: .gitignore:8-9 (both doc/ and tools/ are ignored, checked), the untracked .cargo/config.toml, whose runner points into tools/, and check.sh:19-20 (checked).
   - Why: committing .cargo/config.toml breaks clones and CI. An agent's gate stamps the lead's tree. Plans, reviews and visual-style.md, which tracked scripts cite, dangle.
   - Fix: a user decision first, then git rev-parse --show-toplevel and a worktree case in the self-test.
4. SQLX_OFFLINE=true for every build. Stack, S.
   - Where: .env.example:13, README.md:27-29, ci.yml:10, check.sh:17.
   - Why: after the README quick start, a fresh clone builds against a live database and fails.
   - Fix: put SQLX_OFFLINE=true and SETTLER_TEST_DATABASE_URL in .env.example (or a tracked [env]). CI runs cargo sqlx prepare --workspace --check with a pinned sqlx-cli.
5. Godot tests must not skip silently. Stack and Godot, M.
   - Where: client_generator/tests/godot.rs:23 (hard-coded ~, checked) and :28-40, ci.yml:23-24.
   - Fix: with SETTLER_REQUIRE_GODOT=1 a missing Godot panics. Set it in check.sh full mode and in a CI job with a pinned headless Godot, and build the default path from $HOME.
6. Apply-side mutators that are all-or-nothing. Rust, M.
   - Where: game.rs:266-280, trade.rs:81-95 and 203-214, development.rs:14-81 and 159-163, robber.rs:44,73,98, building.rs:52-55 and 89-100.
   - Why: pay_to_bank emits ResourcesPaid even when nothing was paid. swap_hands can apply one leg only. Some code mutates before a lookup that can fail.
   - Fix: Game::player_mut, every lookup before the first mutation, one Game::move_resources(from, to, amount) for every transfer, and debug_assert on branches that stay unreachable.
7. Game crate exports its rule data. Rust, M.
   - Where: bot hand.rs:5-38 and 87-108, evaluation.rs:22-27 and 113-123, heuristic.rs:15, building.rs:10-14, development.rs:11, hud.gd:11.
   - Fix: a public Purchase enum with cost(), Resource::index(), public thresholds and Board::is_settlement_site. The bot reads own.bank_rates and deletes its copies, and the costs reach the client through SiLimits.
8. Split GameState.changed (folded into EventPlayer). Godot, M.
   - Where: game_state.gd:6 (one signal for three meanings, checked) and :56,82,93,113, hud.gd:52-60, board.gd:32-35.
   - Fix: snapshot_received(view, events, is_resync) and legal_actions_changed(). EventPlayer republishes the shown view.
9. BoardView interface and a typed BoardTarget. Godot, M.
   - Where: game_screen.gd:5, game.tscn:16, board.gd:15-23, 38-49 and 74-85, board_painter.gd:387-413, board_screenshot.gd:52-60, ui_game.gd:248,375, board_test.gd:140.
   - Why: callers read board.get("_targets") and writable projection fields. The screenshot tool has lost the edge targets. tile_corner_position exists only for tests.
   - Fix: a BoardView base with bind, targets() and screen_position(target), a BoardTarget class, and private projection fields.
10. Shared server test scaffolding. Rust tests, M.
    - Where: tests/game.rs:98-138 and 205-251, persistence.rs:265-327, common/mod.rs:71-84 and 227-251, lobby.rs:141,158,179, abandon.rs:99-170, connection.rs:243,264.
    - Fix: play_as, start_with_bots, next_game_started and next_game_update, a join that returns Result<LobbyDetails, ErrorCode>, an eventually poller and a DB drop guard.
11. Store the open trade only in Phase::TradeOffered { offer }. Rust and protocol, M.
    - Where: phase.rs:38, game.rs:89 and 240-251, view.rs:23-24 and 101, trade.rs:139-158 and 246-259.
    - Fix: delete Game.trade and PlayerView.trade, add awaits_answer_from, regenerate the client and update the HUD trade panel.
12. Palette as the single colour source. Godot, M.
    - Where: build_theme.gd:10-18 and 84-91, palette.gd:26-73 (Clay fallback through maxi(find,0), checked), hud_text.gd:5-21, board_painter.gd:10-53, resource_art.gd:10-20.
    - Fix: build_theme preloads Palette, keys are SiResource.* with push_error on unknown ones, callers use Palette directly, and a Godot test compares a rebuilt theme with the committed .tres.
13. HTTP session types and routes in the schema. Cross-area, M.
    - Where: generator lib.rs:43-55, SiGuestSession.gd:15-31 (hand-written, named like generated code), server lib.rs:130-139, net.gd:10,110.
    - Fix: put GuestSession, Upgrade and HttpError in the schema, and make the routes protocol constants. The client parses HttpError instead of showing only "status 400".
14. Godot protocol coverage. Godot tests, S.
    - Where: godot.rs:177-201, round_trip.gd:7-27, hud_event_log.gd:51-83, game_state_test.gd:40-42.
    - Fix: fail on any generated Si* variant missing from the fixtures, and generate the samples from Rust Event and ErrorCode.
15. Deduplicate rule checks. Rust, S.
    - Where: building.rs:129-151, trade.rs:45-71 and 228-244, development.rs:166-169 and 262-274, turn.rs:35-38, plus the six finished/winner matches.
    - Fix: Game::require_main_turn, building::check_road_placement, check_bank_trade as the filter for legal_main, and Game::winner() and is_finished().

Next in line: phase invariants (rust 8), record and store dedup with the snapshot rule (rust 10-11), the Postgres casts (rust 13), Net leaving the socket open (godot 12), check.sh db handling (stack 13) and the rate-limiter merge (rust 16).

## 3. Waves
Rules for every wave:
- Tasks in one wave touch disjoint files.
- The lead owns AGENTS.md, the Cargo.tomls, the game lib.rs re-exports and, after wave 1, ci.yml.
- At most one protocol and client-regeneration task per wave.
- Every task uses TDD, proves its test bites, and ends with tools/check.sh green.

Wave 0 (user decisions, no agent):
- Track tools/ together with .cargo/config.toml, or keep both per-machine and document that in AGENTS.md.
- Track doc/, or inline the facts that the tracked scripts cite.

Wave 1 (foundations, parallel):
- 1a JWKS fix.
  - Files: keycloak.rs, identity/mod.rs.
  - Done when: a 500-then-keys test gives KeysUnavailable, a retry succeeds within 60 s, and the error variants are typed.
- 1b Game core helpers.
  - Files: game.rs, resource.rs.
  - Done when: the limits are pub, and player_mut, require_main_turn, move_resources (tested all-or-nothing), winner(), is_finished(), Resource::index and a named ResourceCounts constructor exist. Consumers do not change yet.
- 1c Purchase.
  - Files: new rules/purchase.rs, plus the cost constants in building.rs and development.rs, and rules/mod.rs.
  - Done when: there is one cost table.
- 1d Test scaffolding.
  - Files: tests/common/mod.rs, tests/game.rs, tests/persistence.rs.
  - Done when: the helpers exist, game.rs and persistence.rs use them, and no databases leak.
- 1e Build environment.
  - Files: .env.example, README.md, ci.yml.
  - Done when: a build with Postgres stopped works after cp .env, and CI runs sqlx prepare --check.
- 1f Gate scripts (after wave 0).
  - Files: tools/*.sh, a new tools/common.sh and prove_test_bites.sh, .gitignore, .cargo/config.toml.
  - Done when: check.sh stamps the worktree it runs in (self-test case), full mode sets SETTLER_REQUIRE_GODOT=1, db mode fails fast on docker errors, and the help prints the whole header.
- 1g Godot harness.
  - Files: godot.rs, a new godot_tests/test_support.gd, the test .gd files, the exit code in board_screenshot.gd.
  - Done when: the project is imported once (OnceLock) and run through one helper, the require flag works, the default path comes from $HOME, and the tools exit non-zero on failure.
- 1h Palette source.
  - Files: palette.gd, build_theme.gd, main_theme.tres, hud_text.gd, resource_art.gd.
  - Done when: no colour literal exists outside Palette, the keys are SiResource.* with push_error, and the theme is rebuilt.
- 1i Net failure paths.
  - Files: net.gd.
  - Done when: _fail closes the socket and resets the flags, and start() closes any previous socket.

Wave 2 (consumers, parallel):
- 2a SiLimits (the protocol task of this wave).
  - Files: protocol lib.rs, generator src, server lib.rs (routes, line 88 text), client/.
  - Done when: the protocol re-exports the limits, the error texts use format!, SiLimits.gd holds the limits, costs, DEFAULT_BIND port and routes, the session types are generated, HttpError is parsed, and --check is green.
- 2b Trade and robber rules.
  - Files: trade.rs, robber.rs.
  - Done when: transfers use move_resources, no code indexes players directly, check_bank_trade drives legal_main, bank_rates is computed once, and tests cover a failed swap_hands leaving both hands unchanged and victim dedup.
- 2c Build and development rules.
  - Files: building.rs, development.rs, turn.rs.
  - Done when: check_road_placement is shared, every lookup comes before the first mutation, and require_main_turn is used.
- 2d Bot.
  - Files: settler_island_bot/src/** and tests.
  - Done when: no rule constant is copied, the bot uses bank_rates and Purchase, the fallback has a debug_assert, and bot_seed is exported.
- 2e Lobby.
  - Files: lobby.rs, registry.rs, metrics.rs.
  - Done when: winner() is used, one finish or abandon transition decrements the gauge once, list_lobby and unlist_lobby exist, SeatCount is validated, and a rejected bot offer falls back to EndTurn (tested).
- 2f Postgres.
  - Files: postgres.rs, plus a migration if BIGINT is chosen.
  - Done when: writes use try_from and errors name the raw row id.
- 2g Config.
  - Files: config.rs, main.rs.
  - Done when: DATABASE_URL is parsed in from_vars, one VARIABLES list equals the .env.example keys, and the whole Config is compared.
- 2h Rate limiter.
  - Files: connection.rs, rate_limit.rs.
  - Done when: one TokenBucket is used by both limiters.
- 2i Remaining server tests.
  - Files: tests/lobby.rs, abandon.rs, connection.rs.
  - Done when: they use the helpers and no sleep is used for synchronisation.
- 2j Godot protocol tests.
  - Files: godot.rs, round_trip.gd, hud_event_log.gd, game_state_test.gd, plus a new stale-token test.
  - Done when: a missing variant fails, the samples come from Rust, and a bogus session.cfg is replaced and online fires.
- 2k Board painter colours.
  - Files: board_painter.gd (colour part only).
  - Done when: no aliases or hex literals remain.

Wave 3 (protocol train, one change after another; the other tasks run alongside):
- 3a Trade in the phase (protocol).
  - Files: phase.rs, game.rs, view.rs, trade.rs, client/, hud_trade_panel.gd.
- 3b Record and store dedup (alongside 3a).
  - Files: record.rs, store.rs, tests/persistence.rs.
  - Change: store RecordEntry, one replay function in the game crate, store::wants_snapshot. The lobby call sites switch in 3d.
- 3c Board geometry helpers (alongside 3a).
  - Files: board.rs, scoring.rs, bot evaluation.rs.
  - Change: buildings_of, touches_road, Edge::other_end. No protocol change.
- 3d Phase invariants (protocol, after 3a).
  - Files: phase.rs, setup.rs, turn.rs, robber.rs, game.rs, lobby.rs (store calls).
  - Change: SetupRound enum, Game::start_turn, a named discard entry.
- 3e LobbyInfo (protocol, after 3d).
  - Files: protocol lib.rs, lobby.rs, connection.rs, the lobby screens.
  - Change: a nested LobbyInfo and DEFAULT_BOT_DIFFICULTY emitted to the client.
- 3f Generator strictness.
  - Files: model.rs, gdscript.rs.
  - Change: Unsupported instead of Any, a GdType enum, REQUEST_ID required.

Folded into the Godot work, not run separately:
- ui-layout (godot-ui-design.md step 2; ui-style has landed):
  - SiLimits in connect.tscn and the lobby browser. If 2a lands later, set max_length = 24 now as a stop-gap.
  - Theme type variations instead of the slate HUD.
  - The board rect taken from the HUD's reserved area or from containers, not the copied offsets in game.tscn:24-25 (checked).
  - The hud.gd split (HudText.prompt, legal queries, HudActionBar).
  - can_offer_trade, and typed picker and trade-builder fields.
  - Named font sizes and a minimum button size.
  - Error ownership between GameState, HUD and main.
  - Typed BoardTarget and targets() as the base for set_target_filter.
  - A target overlay with the pulse wired as the plan's leftovers ask (godot 20 says remove it; the plan says wire it).
- ui-feedback / EventPlayer: split GameState.changed, build the HUD widgets once, keep the shown view separate from the server view.
- Before Board3D (godot-3d.md): the full BoardView interface used by GameScreen, the tests and the tools; delete tile_corner_position. Ports on edges and splitting the board layout from the pieces belong to the Board3D protocol redesign.

## 4. Cross-area themes
- The same fact typed by hand in several places:
  - Limits: game, protocol and .tscn files.
  - Costs: engine, bot and hud.gd:11.
  - Resource order: ResourceCounts comments, [0,0,0,0,0] literals, Palette arrays.
  - Port 8253: config, connect screen, generator, and README examples that say 8080.
  - Routes and session JSON: the server router and SiGuestSession.gd.
  - The Postgres URL: compose, .env.example, check.sh, README.

  The fix is the pattern the project already trusts: one Rust owner, emitted by the generator, guarded by the stale-client test.
- Engine data is private, so consumers re-derive it: the bot copies rule data despite bank_rates, and the HUD proxies the trade-offer rule through EndTurn.
- Invariants held by convention:
  - "Apply cannot fail" in the engine.
  - Paired state: the trade and the phase, dice_rolled and the phase, a port on both corner and edge.
  - Metrics gauges.
  - GameState.changed.
  - Array-order lookups.

  Each should become a type, a single transition, or an error at the boundary.
- Silent degradation: Godot tests skip as a pass, the generator emits Any, the bot falls back to legal.first(), Palette falls back to Clay, the HTTP error body is dropped, and check.sh db keeps going after docker fails. Fail loudly in tests and debug builds.
- Copied test scaffolding: server tests, the godot.rs runner, the .gd tests, and the revert-in-a-trap script each agent rewrites.
- Stringly typed fields: Keycloak errors, generator types, board targets, picker fields, card names. Use the Si* classes and Rust enums that already exist.

## 5. What to keep
- Read-only check_* validation that also drives legal_*, errors_leave_the_game_unchanged, the determinism tests from three sides, and the card-conservation and longest-road proptests.
- Event::visible_to as the single point that hides secret information.
- The actor design: one task per lobby, a registry task, oneshot replies, an outbox that never awaits. Also apply_and_store (clone, store, commit) and the replay check in StoredGame::rebuild.
- The generated client with --check and the committed-client test, and the typed Si* classes with VALUES. Extend this pattern; do not replace it.
- OwnView.bank_rates, computed once by the engine.
- Client ownership: Net owns the socket, GameScreen owns GameState, the Board and HUD send only legal actions, and legal_actions stays empty until the reply. BoardGeometry is pure and reusable by Board3D. build_theme.gd generates the theme.
- Tooling: the tree-hash stamp, output filtered to failures and totals, worktree scripts with self-tests that refuse to delete dirty work, Godot tests with isolated XDG dirs, and compose services bound to 127.0.0.1 with project names.
