# 3D motion: dice, pieces, cards (milestone 3)

Scope: how `Board3D` and the 3D card layer move, on top of `EventPlayer` (`doc/design/feedback.md`, plan
`doc/plans/godot-3d.md`). Original design, genre conventions only. Durations are nominal at speed 1 before `pace`.

## What EventPlayer really offers (differs from feedback.md)
The shipped `event_player.gd` has no `_step_<event>` functions and owns no tweens. It emits `beat_started`,
`event_started(event)` per event, waits `EventCues.hold_milliseconds(event) / (speed_factor * pace)` and finally
`_commit` emits `committed` with the new `shown_view`. Sounds come from `EventCues.hook` at event start. The 3D layer
hangs on those signals and follows three rules:
1. **Holds are the beat clock, motion overlaps.** Holds (150 to 350 ms) are short; a 3D animation usually runs longer
   than its hold and finishes while later events start. Order matters only where one animation needs another's
   result (dice before production, see Dice).
2. **Commit is the truth.** Animations never touch state; on `committed` every consumer redraws from `shown_view`.
   Anything still moving at commit is finished instantly by the consumer (`finish_all()`), never left in the air.
3. **Step functions live in the consumers.** Board3D and `CardLayer3D` each implement `_on_event_started(event)`
   dispatching to `_step_<variant>(event) -> Signal` (the `finished` signal of the tween started, or a zero timer),
   stored in a per-consumer `live: Array[Tween]`. EventPlayer stays renderer-agnostic. If a later event must wait for
   an earlier 3D animation, the wait is a raised hold in `EventCues.HOLD_MILLISECONDS` (a constant, no new
   mechanism). Only `DiceRolled` needs it (production must start when the faces are readable, about 620 ms).

Small EventPlayer changes this design needs: (a) `current_pace()` getter so consumers scale tweens by
`speed_factor * pace`; (b) a `sound_by_consumer` flag: for `DiceRolled`, `EventCues.hook` currently plays
`sfx_dice_land` at event start, but 3D plays `sfx_dice_shake` at start and land / `sfx_roll_seven` at contact itself;
(c) consumers register `finish_all()` which EventPlayer calls from `_collapse` and `_resync`.

## Dice: scripted tumble, not physics (recommendation)
Physics (`RigidBody3D`) cannot land on a known face without hacks (re-throw until it fits, or snap at the end), is
nondeterministic across machines (screenshots, replays) and its settle time is unbounded, which breaks the lag budget
(bots act every 600 ms). A scripted tumble is right by construction.

**Guaranteeing the faces.** The die mesh has a fixed face-to-normal map (`N(v)` for v in 1..6). Final orientation
`R_final` = shortest rotation taking `N(v)` to world +Y, composed with a yaw from a hash of (roll counter, die index)
so landings vary but are deterministic. A `tween_method` drives `t` from 0 to 1 and sets
`orientation = spin(axis, turns * (1 - ease(t))) * R_final` with 2 to 3 extra turns, so at `t = 1` the spin term is
the identity and the orientation is exactly `R_final` for any turn count. A unit test checks for every value 1..6
that the landed face normal is (0, 1, 0) within 1e-4 (and that the two dice show `first` and `second`).

**Motion.** Dice fly from the roller's seat edge to a fixed dice tray at the table edge nearest the camera (never
over the island):
- 0 to 120 ms: lift 0.6 hex (`TRANS_QUAD`, `EASE_OUT`); `sfx_dice_shake` at 0.
- 120 to 480 ms: parabolic arc (apex 0.8 hex) while spinning.
- 480 ms: first contact, `sfx_dice_land` (or `sfx_roll_seven` for sum 7, layered lower); contact shadow blob grows.
- 480 to 620 ms: one rebound (height 0.12 hex, two-step tween) with a small yaw slide.
- 620 to 700 ms: damped wobble (2 degrees) to rest.
Total 700 ms nominal (hold stays 350 ms, production flights start at the raised hold). Then the chips of the sum pulse
(scale 1.25, 130 ms) and tiles under the robber pulse grey. Dice rest on the tray until the next roll. At `pace` 2
the whole throw takes 350 ms. Collapse, `Off` or unfocused: dice teleport to the final faces, no sound. After a
resync dice show the last roll if the view carries it, otherwise they stay hidden until the next roll.

## Pieces
All pieces are meshes in seat colour built by one `PieceFactory.build(kind, seat)`. Board3D owns **static** pieces,
kept as dictionaries `corner -> node` and `edge -> node` and synced on `committed` from `shown_view` (diff, no
rebuild). Animated pieces are **ghosts** under `Pieces/Ghosts`.

**Hand-off without flicker or double piece.** On `SettlementPlaced`, `RoadPlaced` or `CityBuilt` the ghost spawns and
the static set does not change, because it still follows the previous `shown_view`. On `committed` Board3D first
syncs the statics (the new piece appears at the exact transform the ghost ends on) and frees the ghost in the same
call, before the next frame renders. A ghost still tweening at commit is jumped to its end transform first. Ghost and
static share the mesh factory so they are identical; transient VFX (dust, ring) are separate particle nodes that free
themselves. Robber: one node, the tween moves the real robber and commit re-asserts its position from the view
(idempotent), so a double robber cannot exist.

| Piece | Motion | Total | Easing |
|---|---|---|---|
| Settlement | spawn 0.7 hex above at scale 1.25, drop; contact squash (y 0.85 for 60 ms), settle to 1; one-shot dust ring particles (8, 300 ms, low alpha) and a seat-colour ripple | 350 ms | drop `QUAD` `EASE_IN`, squash `BACK` `EASE_OUT` |
| Road | grows along its axis from the end touching the seat's network (pivot at that end), 0 to 1, small lift in the middle; dust at the far end | 250 ms | `CUBIC` `EASE_OUT` |
| City | settlement ghost scales xz 1.15 and fades while the city rises from y -0.3 to 0; emission flash in seat colour | 400 ms | `BACK` `EASE_OUT` |
| Robber | lift 0.4 hex (120 ms), arc with apex +0.3 (300 ms), landing wobble (80 ms); old tile un-dims, new tile dims to 60% | 500 ms | lift `QUAD`, arc `SINE`, wobble `ELASTIC` |
| Setup placements | as above plus a soft pulse on the adjacent tiles | +100 ms | |

## Cards
### Recommendation: 2D hand in the HUD, 3D flights over the table (hybrid)
- (A) Real 3D hand in a `SubViewport`: needs its own camera, hover/click/drag forwarded by hand, textures for text,
  a second render pass. The hand is the most-clicked element and must stay robust.
- (B) All 2D, flights too (as milestone 2): cheapest, but cards do not cross the 3D board.
- **(C) chosen:** the hand stays the existing 2D card widgets (clicks, tooltips, scale settings all work) with a fan
  (rotation, arc, hover lift) and a light pseudo-3D tilt (shader skew). Cards *in flight* are 3D `CardToken3D`
  quads (thin rounded boxes) in the table scene; hidden seats' stacks live at the table edge (mats from the plan) in
  world space, so flights to and from other seats are pure 3D. Flights that end in or start from the own hand
  hand over: the 3D card projects to the slot via `camera.unproject_position`, a 2D token takes over for the last
  120 ms (or first 120 ms when leaving the hand) and the 3D one is released in the same frame (1-frame overlap).

**Visual and pooling.** One mesh (0.5 x 0.7 hex, 0.01 thick); face textures pre-baked at startup from the existing 2D
card drawing (6 resource faces, dev faces, one back), no per-frame `ViewportTexture`. `CardToken3D.show_face(id)`
with -1 meaning back. Pool of 32 created at scene load, `acquire()`/`release()` (hide, reset transform), never freed;
when empty the oldest flight finishes instantly and its token is reused. A token for a hidden card is created with
id -1, so the node never holds an identity the viewer should not know.

**Flight shape.** Quadratic Bezier in world space, apex 0.25 times the distance above the table, 1.5 turns of
flip over the first 40%, landing flat; stagger 50 ms, at most 12 per seat (then one token carries "+n").

### Flights per event
- Production: tile centre to stand (others) or hand slot (own), 370 ms, tile hops.
- Pay and discard: hand slot (card lifts out first, 2D to 3D handover) or stand to bank deck, face up, 60 / 40 ms
  stagger, discard fans out and the stand flashes amber.
- Steal: victim stand to thief stand, face only when `resource != null`, otherwise a back; victim stand shakes.
- Bank trade: gave to bank, then received from bank, 150 ms overlap.
- Player trade: both sets cross over the table centre at different apex heights so they do not clip.
- Dev buy: deck at table edge to stand; face only for the buyer, landing in the 2D dev row via handover.
- Dev play: card rises to a show position above the table front, flips face up, holds 300 ms, drops on the discard pile.
- Monopoly: `amount` face-up tokens from the other stands to the taker (the commit fixes true counts).
- Year of plenty: two cards bank to seat.

## Collapse, instant, unfocused, speed
- `finish_all()` on every consumer kills tweens, jumps ghosts and tokens to the end state, releases pooled tokens and
  frees ghosts; called by EventPlayer on collapse, resync (`GameStarted`) and focus-out. The next `committed` is a
  plain redraw.
- `animation_speed = Off` (`speed_factor == 0`) or unfocused: consumers check `player.animated()` (already includes
  `_instant()`) and create nothing: no ghosts, no particles, no tweens; sounds follow `sound_enabled` and the
  EventPlayer rule (muted while unfocused). Headless tests use `Off`.
- Speed: every tween gets `set_speed_scale(speed_factor * current_pace())`, so the lag budget of 1.5 s holds for 3D
  motion too; the own player's beats already play at higher pace per feedback.md.
- Performance: one-shot `GPUParticles3D` pool of 4, blob shadows for flying cards, no per-frame allocations.

## Event table
| Event | 3D animation | ms | Sound hook |
|---|---|---|---|
| `DiceRolled` | scripted tumble to server faces, bounce, settle; chips pulse | 700 | `sfx_dice_shake` at 0; `sfx_dice_land` at 480 (`sfx_roll_seven` for 7) |
| `ResourcesProduced` | tile to stand/hand flights, tile hop | 450 | `sfx_card_gain` (rate limited) |
| `ResourcesPaid` | hand/stand to bank | 350 | `sfx_pay` |
| `SettlementPlaced` | ghost drop, squash, dust ring | 350 | `sfx_place_settlement` at contact (about 230) |
| `RoadPlaced` | grow from network end, dust | 250 | `sfx_place_road` at 100 |
| `CityBuilt` | settlement morphs up to city, flash | 400 | `sfx_build_city` |
| `RobberMoved` | lift, arc, wobble; tile dim | 500 | `sfx_robber_move` (at landing) |
| `CardsDiscarded` | hand/stand to bank, fanned | 450 | `sfx_discard` |
| `ResourceStolen` | one card stand to stand (back unless involved), victim shake | 500 | `sfx_steal` / `sfx_stolen_from_me` |
| `BankTraded` | give to bank, receive from bank | 600 | `sfx_trade_bank` |
| `TradeOffered` | HUD bubble, stand glow | 300 | `sfx_trade_offer` |
| `TradeAnswered` | badge check/cross, stand glow colour | 200 | `sfx_trade_accept` / `sfx_trade_reject` |
| `TradeCompleted` | both sets cross over the table | 600 | `sfx_trade_done` |
| `TradeCancelled` | badge clears | 200 | `sfx_trade_cancel` |
| `DevelopmentCardBought` | deck to stand, face for buyer only | 450 | `sfx_dev_buy` |
| `DevelopmentCardPlayed` | rise, flip, hold, drop to discard pile | 800 | `sfx_dev_play_<card>` |
| `MonopolyTaken` | tokens from other stands to taker | 700 | `sfx_monopoly` |
| `YearOfPlentyTaken` | bank to seat, two cards | 400 | `sfx_dev_gain` |
| `LongestRoadChanged` | badge flies to holder's stand, road meshes glow | 600 | `sfx_award_road` |
| `LargestArmyChanged` | same with army badge | 600 | `sfx_award_army` |
| `TurnEnded` / `TurnStarted` | stand highlight fades / moves | 150 / 300 | `sfx_turn_start` for own seat (existing cue) |
| `PhaseChanged` | none | 0 | none |
| `GameWon` | winner stand rises, confetti from pool | 2000+ | `sfx_victory` / `sfx_game_over` |

Unknown events: log line only, no motion.

## Decisions for the user
1. **Dice:** scripted tumble (recommended: deterministic, bounded 700 ms) or physics throw with forced result
   (richer, needs re-throw or snap, unbounded settle).
2. **Hand:** hybrid, 2D hand with 3D flights (recommended), full 3D hand in a SubViewport (immersive, much more input
   work), or keep 2D flights (cheapest, loses the 3D feel).
3. **Dice landing:** fixed tray at the table edge (recommended, never hides the island) or throw over the island
   centre (more dramatic, covers pieces for about 1 s).
4. **Dice sound timing:** let the 3D consumer play shake/land at the animation (recommended, needs the
   `sound_by_consumer` flag) or keep the event-start hook (land sound about 480 ms early).
