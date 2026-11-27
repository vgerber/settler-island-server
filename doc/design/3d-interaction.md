# 3D table: scene, camera, picking, player states

Design for milestone 3 (`doc/plans/godot-3d.md`). Scope: how `Board3D` plugs into the game screen, how the camera
frames the island next to the HUD, how targets are picked and shown, how it is tested, and what the seats look like.
Models, dice physics and 3D cards are separate designs. Interface facts below were read from `board.gd`,
`event_player.gd` and `game_screen.gd` at commit 37b5bbb.

## Scene structure

```
GameScreen (Control)
  Board | Board3D      one of the two, a `BoardView`, named `Board`, sized to `Hud.board_slot` by `_fit_board`
  Hud                  unchanged; it is a Control above the board in tree order
  Overlay              unchanged
Board3D (BoardView, Control)         does all input and picking itself
  SubViewportContainer (stretch, mouse_filter IGNORE)
    SubViewport (own World3D, MSAA 2x, opaque background)
      Table (Node3D)                 felt, lamp (DirectionalLight3D + soft shadow), WorldEnvironment
      Island (Node3D)                tiles, chips, ports, built from `BoardGeometry`
      Pieces (Node3D)                one node per road, settlement, city, plus the robber
      Markers (Node3D)               target rings, hover ghost, seat stands
      CameraRig (Node3D yaw) / Pitch (Node3D) / Camera3D
```

- **Region.** Board3D fills the HUD's `board_slot` exactly like the 2D board (1260x676 base, 1008x541 at 720p). The
  HUD panels never overlap the 3D view, dialogs and toasts (children of the slot) draw above it, and no click can
  reach the table through a panel. The plan's "behind the HUD" is met by tree order, not by a full-screen viewport
  (see decision 1).
- **Interface.** A new base class `BoardView extends Control` holds the contract: `bind(event_player)`,
  `set_target_filter(kinds)`, `targets() -> Array[BoardTarget]`, `player`, plus one addition,
  `screen_point(target) -> Vector2` (control-local pixels of a target; used by tests). `Board` and `Board3D` extend
  it. The real `bind` takes the `EventPlayer`, not `GameState`; the plan text is out of date on that. `BoardTarget` is
  reused unchanged: its `point` is the hex-unit position, and 3D maps `(x, y)` to world `(x, 0, y)`.
- **Choosing.** `game.tscn` holds only a placeholder slot. `GameScreen._ready` reads `Settings.board_view` (`"2d"`
  until 3D is accepted, then `"3d"`) and instantiates one of the two scenes into the same slot, named `Board`, so
  `%Board`, `_hud.target_filter_changed.connect(_board.set_target_filter)` and `_fit_board` stay as they are; only the
  `@onready` type becomes `BoardView`. The choice applies from the next game (no live swap, no state to migrate). The
  settings popup gets one row "Board: 3D / 2D". If the 3D scene cannot be built (no usable GL/Vulkan driver) the
  screen falls back to 2D and toasts once.
- **EventPlayer.** Board3D connects the same signals Board and Hud use:
  - `committed`: `_sync()` makes the scene equal to `shown_view`: creates missing pieces, removes vanished ones, moves
    the robber, rebuilds targets. It is idempotent and kills the running tween of any node whose state differs, so a
    collapsed beat, a resync or an unfocused window lands on the truth without replaying anything.
  - `event_started(event)`: starts a cosmetic animation for `SettlementPlaced`, `RoadPlaced`, `CityBuilt`,
    `RobberMoved`, `DiceRolled`, `ResourcesProduced` (tile pulse), `LongestRoadChanged` (road glow). The piece node is
    created at event time and tagged `animating`, so the following `_sync` keeps it instead of duplicating it.
  - `beat_started`: not used by the board.
  - Animations are skipped when `not player.animated()` and scaled by `player.speed_factor`. They never block the
    player: `EventCues.HOLD_MILLISECONDS` is short (150 ms per placement, 350 ms for dice), so a drop-and-settle of
    about 250 ms just finishes while the next event starts. The one change to `EventCues` is a longer `DiceRolled`
    hold when the board is 3D (about 900 ms, so the throw reads before production); the table takes the renderer as
    an argument, the player itself stays render-agnostic.
  - Targets and hover are rebuilt from `shown_legal_actions` only, never from events, so an animation can never offer
    an illegal click.

## Camera

Rig: a pivot at the island centre with `yaw`, `pitch`, `distance` and a `pan` offset on the table plane. Perspective,
vertical FOV 35 (keep height), near 0.5, far 60.

| Parameter | Default | Limits |
|---|---|---|
| Pitch (down from horizontal) | 55 deg | 30 to 80 deg (lower would let pieces hide targets behind them) |
| Yaw | 0 (same orientation as the 2D board) | free; reset returns to 0 |
| Distance | auto-fit | 0.6x to 1.5x of the fit distance |
| Pan | 0 | at most 2.5 hex units from the island centre, so the island cannot be lost |

**Auto-framing.** The camera never uses a fixed distance. `fit_distance` takes a point cloud (all corners at table
height and at piece height 0.5, the port markers, the robber top) and finds the smallest distance, by 12 steps of
bisection, at which every projected point lies inside the viewport rect minus `MARGIN` (16 base units, as in 2D). The
viewport is the board slot, so the HUD's right column (340) and bottom bar (176) are outside it by construction.
For the standard 19-tile island that is about 10 units wide and 7 deep after foreshortening, so width limits and the
island fills about 90% of the slot width; the slot has the same 1.86 aspect at 1600x900 and 1280x720, so both frame
alike. User zoom is stored as a factor on the fit distance, so a window resize or the compact HUD switch (`resized`)
re-fits and keeps the relative zoom. Reset clears yaw, pitch, zoom and pan with a 0.25 s tween (instant when
animations are off). Larger boards fit by the same function and the zoom limits scale with it.

**Input.**

| Action | Mouse | Trackpad | Keyboard |
|---|---|---|---|
| Orbit | right button drag (over 6 px; a plain right click still disarms build mode) | two-finger scroll (`InputEventPanGesture`) | Q / E rotate 15 deg, Page Up / Page Down pitch |
| Zoom | wheel (towards the centre) | pinch (`InputEventMagnifyGesture`) | + / - |
| Pan | middle drag, or Shift + right drag | Shift + two-finger scroll | Shift + arrow keys |
| Reset | the 40x40 reset button in the slot's top left | same | Home |

No key collides with the HUD's 1/2/3 (build modes), Space (roll) and Esc (disarm); camera keys are ignored while a text
field (chat) has focus. Left click is the only button that acts on the game, so a camera drag cannot send an action.
Movement is smoothed (exponential, 0.1 s) unless animations are off. Camera state is local; only the zoom factor is
remembered between games.

## Picking and highlights

**Analytic, no colliders.** Targets exist only while legal (at most about 54 corners, 72 edges or 19 tiles), so the
scene holds no physics bodies. `_target_at(local_pixel)` projects each target's world point (table plane, y = 0.05)
with `Camera3D.unproject_position` and takes the nearest within the radius. This mirrors `Board._target_at`, so both
boards share one tie-break rule and one hover implementation.

- **Radius.** `max(world_radius_in_pixels, MIN_PICK_PIXELS)`. The world radius is the 2D value (0.32 hex units for
  corner and edge, 0.8 for a tile), converted by projecting the target and a point one radius away on the table. The
  floor is 20 base units (the 40x40 minimum target of `layout.md`), so corners stay clickable when the camera is far
  out or tilted to 30 deg. Pixels are control-local, so `canvas_items` scaling applies as elsewhere.
- **Input.** Board3D handles `_gui_input` itself (the container ignores the mouse), so there is no dependency on
  viewport input forwarding and headless tests can `push_input` as before. Hover updates on motion and also after
  every camera move or `committed` (the cursor stays still while the scene moves under it). Left click on a target
  calls `player.act(target.action)`; a click that ends a camera drag never acts.
- **Highlights, legal targets only.** Corner: flat gold ring on the table; edge: a gold bar along the edge; robber: the
  tile top gets a translucent gold overlay and outline. Unshaded gold with a dark outline, depth test off and a high
  render priority, so tall pieces and the robber never hide a ring. Pulse 0.55 to 1.0 at 0.8 Hz as in 2D, constant
  0.8 when animations are off. Shape differs per kind and the dark outline gives contrast, so the cue does not rely on
  gold alone. No glow post-processing is relied on (weak or missing in Compatibility); the ring itself is the glow.
- **Hover.** The hovered target gets full brightness and a translucent ghost piece in the own seat colour (settlement,
  city, road segment, or the robber figure hovering over the tile); the cursor becomes a pointing hand. Invalid spots
  never react.
- **Build mode.** Unchanged: the HUD calls `set_target_filter([SiActionBuildRoad])` etc. and the board builds markers
  only for the filtered kinds. Forced phases (setup, robber, road building) show every legal target at once, as in 2D.
  A city target is a ring around an existing settlement.
- **Robber move.** All legal tiles get the overlay at once; hover lifts the ghost robber over the tile; click sends
  `MoveRobber`. Tile picking uses the centre distance, so the click does not depend on the ring.

**Accessibility.** Mouse-only play works with the default camera: nothing requires camera movement, since the default
pitch shows every corner and edge. Targets keep the 40 base unit minimum. Reduced motion is the existing animation
setting (speed 0): no pulse, no camera tweens, instant pieces and dice. The camera reset is a visible button as well as
a key. Keyboard target cycling (Tab through `targets()`, Enter to act) is not in this milestone and is the same open
gap as in the 2D board; design it once for `BoardView` later.

**Testing Board3D (equivalent of the headless mouse-only test).** `godot_tests/ui_game.gd` casts `%Board` to `Board`
and computes the click point with `board.to_pixels(target.point)`. Change it to `BoardView` and
`board.screen_point(target)` (2D: `to_pixels`; 3D: `unproject_position` in control pixels). The rest (`targets()`,
`_click_at` through `root.push_input`, the dead-end check) stays, and the script runs once per `Settings.board_view`.
Camera math works headless because `unproject_position` needs no rendering. Further tests in `board3d_test.gd`, written
test first:
1. Round trip: for every target of a bound standard board, `screen_point` then the picker returns the same target, at
   the 1600x900 and 1280x720 slot sizes and at pitch 30, 55 and 80.
2. Framing: all point-cloud points project inside the slot rect minus margin at both resolutions, at the zoom limits
   and after a resize. Together with "the viewport is the slot" this is the "never behind a HUD panel" check.
3. Filter: `set_target_filter([SiActionBuildRoad])` yields only edge targets, equal to `legal_of` of those kinds.
4. Sync: a `committed` after a collapsed beat leaves no `animating` node and piece counts equal the view.
5. Drag guard: a right-button drag moves the camera and sends no action; a plain right click still disarms.

Rendered output cannot be asserted headless, so a windowed verifier (`--position 200,200`) plays one setup and one
robber move with screenshots at both resolutions before the milestone is reported.

## Player states at the table

Options: (a) keep the 2D `PlayerPanel` column and add nothing in 3D; (b) a full 3D mat per seat with counts, badges and
points; (c) panels stay, plus a small 3D stand per seat.

**Recommendation: (c).** Each seat gets a low stand at the table edge in its seat colour. It pulses like the panel's
pending border when that seat is pending and sits raised and lit for the current player. All numbers (cards, points,
pieces left, army and road badges) stay in the panels. Reasons: text on a tilted, orbitable table is hard to keep above
the 18 base unit minimum font; the right column is already laid out and tested at both resolutions; the panels carry
the toasts, floaters and log links of the feedback design; and a mat can be added later without changing the HUD. The
stand gives "whose turn" at a glance on the table and is the 3D origin for flying cards (production, steals, trades).
Card flights end at the panel or hand through a 2D handoff: the card's last 3D position is projected to screen
coordinates, then the 2D flight takes over.

## Decisions for the user

1. **View region.** (a) Board3D inside the board slot, like the 2D board (recommended: no HUD overlap, no click leaks,
   simple framing); (b) full-screen 3D behind semi-transparent HUD panels (more immersive, needs camera frustum
   offsets, panel opacity and click blocking, roughly one more agent wave).
2. **Renderer and web.** (a) Compatibility renderer (recommended if a web export is wanted: weaker shadows, no glow,
   runs on integrated GPUs); (b) Forward+ for desktop only (better shadows and MSAA, no web export).
3. **Seat presentation.** (a) panels plus 3D seat stands (recommended); (b) panels only; (c) full 3D mats with the
   numbers (heaviest, risks text legibility).
4. **Default orientation.** (a) fixed yaw, same as the 2D board for every player (recommended: matches the 2D layout,
   shared screenshots read the same); (b) rotate so the own seat sits at the near edge as at a real table (needs a
   per-seat yaw and re-fit; clearer for stands and the hand).
