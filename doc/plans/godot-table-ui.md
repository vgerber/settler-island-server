# 3D table UI (Crafted Table)

The 3D view gets an in-game UI made only of 3D meshes on the table; the 2D HUD stays for the 2D board view (fallback
and test path). Design source: `doc/design/hud-drafts/crafted-table.md` (direction picked by the user 2026-11-28) and
the requirements in `doc/design/hud-drafts/README.md`.

## User requirements
1. Board state is always clear at a glance, shown in the 3D scene.
2. Everything is a 3D mesh: cards (own hand, dev cards, opponent hands, bank, trade), the prompt sign, the bell, the
   ticker, plates and chips. Text exists only as `Label3D` on a mesh (plate, chip, sign). No `Control` widget is
   drawn over the 3D view in a game, except the 2D fallback while a wave is not done.
3. Opponents' hands are 3D card stacks (backs) at their seats, readable as a count.
4. The own remaining pieces stand on the table at the own side (supply rack), for immersion. Every opponent gets the
   same furniture at their side (user, 2026-11-28): the same hand tray with their cards as backs, the same supply
   rack with their remaining pieces, dev backs, plate, knights, awards; same models, at most a shared smaller scale.
5. Every action, own or remote, is a proper animation: objects move from source to destination, counts change on
   arrival, nothing snaps (requirement 3 in the README). The speed setting (normal, fast, instant) scales all of it;
   `finish_all` ends every tween on a cut.

## Decisions (refining the draft)
- **Supply rack is the build control.** The draft's build slab and the user's pieces-left wish merge: a wooden rack at
  the own seat holds the real remaining pieces (15 roads, 5 settlements, 4 cities, shown as meshes, counted by sight
  and by a chip). Clicking a piece of a row arms that build kind; the piece lifts and a ghost follows the cursor on
  the board. Under each row its cost as mini 3D cards; a missing card is a red dashed outline with `need 1 Ore`.
  Building flies that exact piece from the rack to the board.
- **Dev deck and trade** sit on the bank rack: click the dev deck to buy, click the scale token to open the trade mat.
- **Own hand** is camera-fixed (a `Node3D` under the camera, drawn in the same world) so it stays readable while
  orbiting; everything else is world-fixed on the table.
- **Opponent detail:** all of it (name, points, card backs, dev backs, knights, supply, awards); the user wants
  immersion over minimalism.
- **Board framing:** the 3D view fills the window; fixtures stand on the sea around the island.
- **Settings, history and game over** are 3D too (a walnut settings board with clay sliders and toggles, a ledger
  book for history, a title sign with two wood buttons). Connect, lobby browser and lobby room stay 2D (outside a game).
- 2D board view: unchanged 2D HUD. `Settings.board_view == "3d"` decides at game start.

## Interfaces (fixed for all agents)
- `TableControl extends Node3D` (`scripts/table/table_control.gd`): `label: String`, `enabled: bool`,
  `signal activated`, `pick_radius` (world units) and `pick_point()` (world), `set_hovered(bool)`,
  `set_pressed(bool)`. Hover lifts 0.04 and adds the lantern rim; disabled controls are hidden or lidded, never grey.
- `TableControls` (`scripts/table/table_controls.gd`): registry owned by `Board3D`; analytic picking like `Picking`
  (projected radius, nearest wins, resting pose only), board targets keep priority only when a build kind is armed.
  `Board3D.clickables() -> Array[Dictionary]` returns `{label, enabled, screen_point}` for every visible control and
  board target, for the mouse-only playtest.
- `TableHud extends Node3D` (`scripts/table/table_hud.gd`): the 3D counterpart of `Hud`, bound to the `EventPlayer`,
  reusing `HudLegal`, `HudText` and `SeatNames`; owns the fixtures, the armed build kind and the target filter
  (`target_filter_changed`). It reads only the player, never `Net`.
- `TableAnchors` (extends `TableLayout`'s job, same file or `scripts/table/table_anchors.gd`): world points for
  `hand_card(resource, index)` (via the camera rig), `seat_cards(seat, index)`, `seat_dev(seat)`, `bank_pile(resource)`,
  `dev_deck()`, `supply_slot(seat, kind, index)`, `mat_slot(side, index)`, `sign()`, `bell()`. Motion layers fly
  between these points only.
- Art (`scripts/board3d/art/`): `CardArt` (resource card face per resource, dev card face per kind, backs; bevelled
  slab about 0.36 x 0.5 x 0.012, glyph as raised geometry, no text, at most 120 triangles), `FixtureArt` (supply
  rack, bank rack, bell, sign board, award board, trade mat, plate, chip, token, ledger, settings board), low poly
  and flat shaded, budgets in `clay_kit_test.gd`.
- Text: `TableText.plate(text, size)` makes a mesh plate with a `Label3D` (Bitter for digits, no slashed zero; at least
  13 px on screen at 1280x720, checked headless).

## Waves
At most two heavy 3D agents at once; shared files (`board_3d.gd`, `game_screen.gd`, `hud.gd`, `palette.gd`,
`table_layout.gd`, `ui_game.gd`) belong to one agent per wave.

| Wave | Agent | Scope | Shared files it owns |
|---|---|---|---|
| 1 | A: framework | `TableControl`, `TableControls`, `TableText`, `TableHud` skeleton (prompt sign with live text, bell = end turn), table mode in `GameScreen` (3D fills the window, 2D HUD hidden except widgets not yet replaced), `clickables()` and the 3D branch of `ui_game.gd` clicking table controls | `board_3d.gd`, `game_screen.gd`, `hud.gd`, `ui_game.gd`, `palette.gd` |
| 1 | B: art | `CardArt`, `FixtureArt` meshes, budgets, gallery shots of every fixture | none (`clay_kit_test.gd`, `clay_gallery.gd`) |
| 2 | C: own side | Hand rig with stacks (hover, select, reading spot), dev card fan, supply rack as build control with costs, discard on the tray | `table_layout.gd` (anchors) |
| 2 | D: seats | Seat stations: plates, points, card back stacks, dev backs, knights, supply minis, active-seat lift, answer tokens; award board | none |
| 3 | E: bank and trade | Bank rack with piles and dev deck, trade mat (build, answer, withdraw), steal picker by clicking a seat, monopoly and year of plenty by clicking piles, bank and port trades | `hud.gd` removals for these widgets |
| 3 | F: motion | All `card_flights` on `CardArt` between anchors, pieces fly from the supply, trade and turn and phase motions, own-interaction motions; the 2D flat-token hand-over is deleted in 3D mode | `board_motion.gd` |
| 4 | G: finish | Ghost targets replace the gold bars, ticker and ledger, 3D settings board, game over sign, 1280x720 pass, delete every 2D widget from the 3D mode | `hud.gd`, `game_screen.gd` |
| 4 | verifier | Mouse-only playtest in 3D at normal speed, screenshots of every state, squint test | none |

Each agent keeps the game playable in 3D after its merge (the 2D widget a fixture replaces is removed in the same
change) and adds its fixtures to `tools/game_screenshots.gd` output.

## Acceptance
- In a 3D game no `Control` is visible over the board except none at all after wave 4 (headless check walks the tree).
- `ui_game.gd` plays a full 3D game by clicking only table controls and board targets, in instant and in normal
  speed (normal with a 900 ms step), with no script errors; the 2D run still passes.
- Every event in the motion table of `doc/design/3d-motion.md` plus own interactions has a 3D motion whose source and
  destination are anchors; a headless test plays every event once at normal speed and checks no count changes before
  its object arrives.
- Opponent hands, own hand, dev cards, bank, trade cards are `CardArt` meshes; the own supply shows exactly the
  remaining pieces (test against `view.own`/seat piece counts).
- Budgets: every new mesh within its `clay_kit_test.gd` budget; the table at 1600x900 in Compatibility stays above
  300 fps on this machine.
- Every `Label3D` is at least 13 px tall on screen at 1280x720 at the default camera (headless check).
- Gate green (`tools/check.sh`), test counts reported.
