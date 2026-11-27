# Godot client, milestone 2: the designed game screen

Applies the three design specs to the working client from `godot-client.md` (read that plan's rules and Verification
section, including `--position 200,200` for every windowed Godot run):
- `doc/design/layout.md`: layout, node tree, build mode, flows.
- `doc/design/visual-style.md`: palette, fonts, theme, board drawing.
- `doc/design/feedback.md`: EventPlayer, animations, sound hooks, settings.

Resolved open questions:
- `OfferTrade` is never in `legal_actions`: the offer builder is enabled while `EndTurn` is legal; the server validates.
- Bank rates: `OwnView.bank_rates` (per resource, `Resource::ALL` order: Clay, Wood, Sheep, Wheat, Ore) is on main;
  label bank trades from it, do not derive rates from ports in GDScript.
- Player names: from the last `LobbyState` (Net keeps it); the game view has seats only.
- Layout scaling stays `canvas_items`/`expand` at base 1600x900.
- Fonts: Bitter and Atkinson Hyperlegible (OFL) under `client/godot/assets/fonts/` with their OFL.txt.

## Steps
1. `ui-style` (board and theme): `theme/main_theme.tres`, fonts, palette, `board_painter.gd` changes from
   visual-style.md, seat colours, gold target glow. Files: `client/godot/theme/`, `assets/`, `scripts/board/board_painter.gd`,
   `project.godot` (theme setting only).
2. `ui-layout` (done; open: the compact paths (stacked dev cards, log popup) are checked by screenshots only, the mouse-only playtest runs at 1600x900; no top-bar menu yet, sound and animation settings arrive with step 3) (in parallel with 1): restructure the HUD to layout.md (opponent panels right, hand/dice/actions bottom,
   log), build mode with `Board.set_target_filter` (the only change in `scripts/board/board.gd`), compact mode, names
   from LobbyState. Files: `scripts/hud/`, `scenes/game.tscn`, hud scenes, `scripts/board/board.gd` (filter only),
   `scripts/net.gd` (keep last LobbyState only).
3. `ui-feedback` (after 1 and 2): EventPlayer, shown_view/shown_legal_actions for Board and Hud, animations, toasts,
   turn cue, settings autoload with animation speed, sound hook calls (no audio files).

## Acceptance
Screenshots (1600x900 and 1280x720) of: setup placement, own turn in Main with build mode armed, a 7 with discard, a
player trade offer, game over. A full game against three heuristic bots plays to the end with mouse input only, no
script errors in the log; `tools/check.sh` green.

## Leftovers from ui-style (for ui-layout)
- HUD text in seat colours is unreadable on dark panels for Charcoal (seat 4) and in the "Turn N" header: use the
  parchment seat panels from the theme (`SeatPanel`, `SeatPanelCurrent`) and draw seat identity as a colour chip +
  shape, never as text colour.
- `board.gd`: draw ports after tiles (piers currently under the tiles), pass `pulse` to `draw_targets` and redraw
  while targets are shown (gold glow pulse).
- 2:1 port label and icon are ~10 px at 1280x720: enlarge to the 16 px floor (board_painter.gd may be touched for
  this).
- Fonts and theme are built by `client/godot/tools/build_theme.gd` into `theme/`; rerun it after theme changes.

## 3D later (doc/plans/godot-3d.md)
- Keep Board behind its interface (`bind`, `set_target_filter`, legal targets, act via GameState) so Board3D can
  replace it; the HUD stays a 2D overlay.
- ui-feedback: build EventPlayer render-agnostic plus HUD feedback (toasts, turn cue, counts, waiting indicator);
  skip 2D board animations (road placement, dice, flying cards) — those are built once, in 3D.

## Small HUD follow-ups (from the live screenshot 2026-11-27)
- The steal line in the log has no seat chip (the steal event names its seats differently from `seat`).
- At 1600x900 the top log line can be half clipped while the log follows new lines.
