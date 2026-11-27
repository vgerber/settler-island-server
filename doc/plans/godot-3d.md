# Godot client, milestone 3: 3D table

Designs: `doc/design/3d-look.md` (Direction C, clay), `doc/design/3d-interaction.md` (scene, camera, picking, seats),
`doc/design/3d-motion.md` (dice, pieces, cards). Rules from `godot-client.md` apply (`--position 200,200` for every
windowed run; the 2D board stays as fallback and for tests).

## User decisions 2026-11-27
- Look: soft clay miniature (Direction C), original shapes only. All assets are low poly: flat-shaded facets, few
  triangles (spheres and cylinders about 6-8 segments, one chamfer on hex edges), clay colours and matte material.
  The sea is a grid of low-poly water hex tiles on the land lattice (piers on the coastal ring), not a smooth sheet.
- Renderer: switchable. The game is built for Compatibility with faked depth (vertex ambient occlusion baked into
  the procedural meshes, soft blob shadows under pieces, matte clay shader with rim light); a desktop quality setting
  `High` runs Forward+ and adds SSAO, glow and soft shadows on top. Web always uses Compatibility.
- Dice: scripted 700 ms tumble onto a tray at the table edge, landing on the server's faces by construction.
- Cards: hand stays 2D in the HUD; flights over the table are pooled 3D cards that hand over to 2D tokens at the hand.
- Defaults taken from the designs (recommended options): Board3D renders inside the board slot (HUD panels never
  cover the island); fixed yaw like 2D; seats keep the 2D panels plus small 3D seat stands showing the turn; the 3D
  dice consumer times its own sounds (`sound_by_consumer`); calm animated sea; tile props on; procedural only, CC0
  models may come later after a licence check.

## Renderer switch
Godot picks the rendering method at start-up, so the switch applies after a restart. `project.godot` sets
`rendering/renderer/rendering_method` (and its `.web` override) to `gl_compatibility`. `Settings.graphics_quality`
(`Standard` default, `High` on desktop only) is saved in `user://settings.cfg`; choosing `High` writes
`rendering_method = "forward_plus"` into `override.cfg` (Godot reads it from the project or executable directory at
start-up) and the row says "applies after restart". W0 checks that this works in an exported desktop build; if the
directory is not writable, `High` falls back to the `--rendering-method forward_plus` flag, documented in
`client/README.md`. The Environment turns on SSAO, glow and soft shadows only when
`RenderingServer.get_current_rendering_method()` is `forward_plus`.

## Waves (each part a worktree agent, Sonnet; at most two heavy 3D agents at once)
### W0 foundation (one agent; shared files)
- `BoardView extends Control` base class with the Board contract (`bind(event_player)`, `set_target_filter`,
  `targets()`, `screen_point(target)`); 2D `Board` extends it; `GameScreen` instantiates by `Settings.board_view`
  (`"3d"` is the default, `"2d"` stays selectable); `ui_game.gd` clicks through `screen_point` and runs once per board view.
- EventPlayer additions from 3d-motion.md: `current_pace()`, consumers' `finish_all()` called on collapse and
  resync, `sound_by_consumer` for `DiceRolled`.
- `Settings.board_view`, `Settings.graphics_quality` with settings popup rows; project renderer settings above.
Files: scripts/board/board.gd (+ new board_view.gd), scripts/feedback/event_player.gd, event_cues.gd,
scripts/settings.gd, scripts/hud/hud_settings_popup.gd, scripts/screens/game_screen.gd, project.godot,
client/godot_tests/, settler_island_client_generator/tests/godot.rs.

### W1 (two agents in parallel, disjoint files)
- 3A `board3d-core`: `scripts/board3d/board_3d.gd` (SubViewport in the slot), `camera_rig.gd` (fit by projected
  island bounds at 1600x900 and 1280x720, orbit/zoom/pan limits, reset), analytic `picking.gd` (nearest projected
  target within max(world radius, 20 px)), gold target rings, `_sync` from `shown_view` using placeholder primitives.
  Headless tests: pick round trip for every legal target type, framing at both resolutions, filter, sync idempotence.
- 3B `clay-kit`: `scripts/board3d/art/` procedural meshes (bevelled hex slabs with baked vertex AO, terrain props
  per resource, number chips with pressed numbers, piers with ratio flags, robber, road/settlement/city per seat,
  dice, table, seat stand), `shaders/clay.gdshader` (matte, fingerprint noise, rim light for the outline rule),
  `shaders/sea.gdshader`, blob shadow decal; `tools/clay_gallery.gd` renders a still of every piece under .build/.
  Deterministic props (hash of tile coordinates).

### W2 (two agents in parallel, after W1)
- 3C `board3d-art`: Board3D uses the clay kit, seat stands, Environment per renderer (High adds SSAO/glow/soft
  shadows), screenshots of the five acceptance states in both renderers.
- 3D `board3d-motion`: dice tray tumble, piece drops and robber hop, 3D card flights with pooled tokens and 2D hand
  hand-over, `finish_all`, per the event table in 3d-motion.md. Files: scripts/board3d/motion/, the HUD hand
  hand-over hook only.

### W3 verify and switch
Verifier agent: mouse-only full game on Board3D and on 2D, screenshots, fps at 1600x900 in both renderers on this
machine, no script errors. Then `Settings.board_view` defaults to `"3d"`.

## Acceptance
- `tools/check.sh` green; the mouse-only UI test passes with `board_view = "2d"` and `"3d"`.
- Board3D picking: every legal target of the five acceptance states is clickable via `screen_point` (headless test).
- The island is fully visible inside the slot at 1600x900 and 1280x720 at the default camera (headless test).
- Dice always show the server's roll at rest (test over all 36 outcomes).
- No piece doubles or flickers at commit; collapse and resync leave no token in flight (test with
  `SETTLER_BOT_DELAY_MILLISECONDS=50`).
- Standard quality: at least 60 fps at 1600x900 in Compatibility on this machine; High: at least 45 fps in Forward+.
- Screenshots of the five acceptance states in Standard and High, reviewed by the lead.

## Status 2026-11-27
- W0, 3A, 3B, 3D landed. Motion deviations: the dice hold stays 350 ms (620 ms broke the collapse budget test), so
  production flights may start while the dice land; only ghosts finish at commit, flights finish on collapse,
  resync and focus-out; the tray sits in the near right corner; more than 12 cards per event are dropped.
- Framing and tray fix: the default camera fits the island with its piers (not the stands or the sea), centred in the
  slot, so it fills about 90% of the limiting dimension (test: at least 75%). The own seat's stand at the near edge
  and parts of the others may fall outside the slot at the default view. The dice tray is a low-poly wooden tray
  on the free water spot nearest to the near right corner (searched against piers, flags, tiles and stands; test:
  dice rest inside it, it overlaps none of them and lies in view). Flights now aim at the stands the scene builds.
- Motion added: chip and tile pulses after the dice, the robber's tile dimmed to 60% (state, set on commit), city
  flash, dev card play flight (rise, show 300 ms, drop on the deck), monopoly flights, award badge flights, winner
  stand raise with confetti.
- Cuts, each shown by the ignored test `board3d_motion_cuts_show_their_symptom`: seat stand shake on a steal, road
  glow on an award. Card faces are flat coloured quads; a dev card starts at the stand, not at the HUD dev row.

- W3 done 2026-11-27: verifier passed; trade card moved to the side column, banner hides the top-bar prompt, 2D board
  redraws only its target layer (55 -> 216 fps), 3D is the default view. Leftovers are listed in doc/state-analysis.md.
