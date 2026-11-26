# Refactor waves from the code review

Source: `doc/reviews/summary.md` section 3 (task ids 1a-3f), details per finding in `doc/reviews/rust.md`,
`godot.md`, `stack.md`. Wave 0 is done (tools/ and doc/ are tracked). Godot-side items marked "folded into" go into
`doc/plans/godot-ui-design.md` steps, not separate agents.

## Rules for every task
- Only the files the task lists; anything else needed is reported, not edited.
- TDD: the failing test first; prove it bites with the batched sabotage script (restore in a `trap`).
- `tools/check.sh` green at the end (from the worktree root); every windowed Godot run passes `--position 200,200`.
- Commit subject-only conventional messages, no body, no attribution of any kind.

## Schedule
- Wave 1 batch A: 1a, 1b (heavy), 1d, 1e, 1h, 1i. Batch B: 1c, 1f, 1g.
- Wave 2 after wave 1 lands; wave 3 as the summary orders it.

## Acceptance
Each task's "Done when" from the summary; the lead gates every merge with `tools/check.sh` and the wave end with
`tools/check.sh db` plus the mouse-only UI playtest.
- 1f: add SQLX_OFFLINE=true as a tracked cargo [env] in .cargo/config.toml (gap left by 1e: a clone without .env).

## Follow-ups noted while merging wave 1
- 2i: switch `join` callers (lobby.rs, identity.rs, abandon.rs, connection.rs tests) to `Client::try_join`, delete the
  old `join`; replace sleeps and metrics' `wait_for` with `eventually`.
- 2c: remove `#[expect(dead_code)]` from `Game::require_main_turn` once it is used.
- 2b: `pay_to_bank` returns whether anything was paid so `ResourcesPaid` is not emitted for nothing.
- ui-layout: switch hud_discard_dialog/resource_picker/trade_builder/hud_ui to `Palette` and delete the
  `HudText.seat_color`/`resource_color` wrappers.
- 1a leftover (optional): back-off after a failed JWKS fetch while the realm is down.
- 2k leftover: board_painter passes resource strings like "Wood" to Palette.resource_pattern_color; switch to SiResource constants (fold into ui-layout).
- 2l (after 2b and 2c): the game crate exports the discard limit (robber.rs DISCARD_ABOVE), the largest army minimum,
  the city production factor and `Board::is_settlement_site`; the bot drops SAFE_HAND, LARGEST_ARMY_MIN, is_free_site
  and its factor 2 and uses them; the server drops its own `bot_seed` for the bot crate's (2e).
- 2c additions from 2b: `buy` pays before drawing the card (no lookup or payment after the first mutation); trade.rs
  switches its private `check_main_turn` to `Game::require_main_turn` when the `#[expect(dead_code)]` goes; `exchange`
  validates both legs before moving anything instead of undoing the first leg on failure.
- Watch: `concurrent_lobby_traffic_neither_deadlocks_nor_leaks` failed once under heavy parallel agent load (log lost; 30/30 alone). On the next failure read the kept gate log under .build/logs/ before changing anything.
- Later: replay/rebuild reject a record whose format_version is not FORMAT_VERSION (today it is written but never checked).
- After 3d: drop the dead `if "request_id" in message:` guard in the generator (SiClient.gd changes once); generator: dedup all field names in read_fields, add the DuplicateFile unit test.
- 3g (after 3e, protocol): interrupt phases (MoveRobber, Steal, Discard, RoadBuilding) carry the phase they resume
  (Roll or Main) instead of the `dice_rolled` flag, so "Main without a roll" is unrepresentable; touches phase.rs,
  game.rs, robber.rs, development.rs, turn.rs, client/. Replace remaining GameRecord::push callers with push_entry.
