# Godot client, milestone 3: 3D table (after milestone 2)

The user wants a 3D view: 3D map, 3D cards, animated road/settlement placement, a 3D dice roll, player states
on the table. Not started; this file fixes the constraints milestones 1-2 must keep so 3D drops in.

## Constraints on the current work
- Board is a component with one interface: `bind(state: GameState)`, `set_target_filter(...)`, highlights only targets
  of legal actions, sends the clicked action through `GameState`. A `Board3D` implements the same interface; the game
  screen picks one (setting), the 2D board stays as fallback and for tests.
- The HUD stays a 2D overlay (CanvasLayer) above the 3D scene; dialogs and pickers stay 2D.
- `EventPlayer` (feedback.md) is render-agnostic: it sequences events and tells consumers (Board, Board3D, Hud) to
  play them, each with its own animation; no 2D-specific board animations beyond simple highlights in milestone 2.
- Geometry (cube coordinates -> positions, corner/edge placement) lives in `board_geometry.gd` and is reused in 3D
  (x/y of the 2D layout become x/z on the table).

## Scope sketch (to plan in detail later)
- Table scene: Node3D, orbit/zoom camera with limits and a reset, warm lamp lighting, soft shadows.
- Map: hex tile meshes per terrain (procedural or simple low-poly models, original art), number chips, ports as piers,
  robber figure; picking via ray casts against corner/edge/tile colliders.
- Pieces: road, settlement, city meshes in seat colours; placement animation (drop + settle, dust puff).
- Dice: two physics dice thrown on the table, result forced to the server's roll (animate to the known faces).
- Cards: 3D cards for resources and development cards in a fanned hand at the bottom of the view; flying cards for
  production, steals, trades, discards (backs for hidden ones).
- Player states: a mat or stand per seat at the table edge showing pieces left, card counts, points, badges.
- Performance target: 60 fps at 1600x900 on integrated graphics; Compatibility renderer if the web export matters.
