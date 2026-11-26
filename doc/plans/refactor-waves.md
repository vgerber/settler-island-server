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
