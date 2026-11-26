# Game feel: feedback, animation and sound hooks

Scope: how the Godot client turns server events into motion, sound cues and readable "who did what" feedback.
Original design; genre conventions (dice, flying cards, a highlighted active seat) only. Builds on
`doc/plans/godot-client.md` (Board, Hud, `GameState`) and the generated `SiEvent*` classes.

## Facts the design rests on
- One `GameUpdate` per applied action: `events` (in rule order) then the new `view` and `legal_actions`
  (`client/godot/scripts/game_state.gd`). There is no intermediate view: what the board looked like *between* two
  events of one update is never sent, so the client animates on top of the previous view and commits the new one.
- Bots act on a timer, default 600 ms after the previous action (`settler_island_server/src/config.rs`,
  `SETTLER_BOT_DELAY_MILLISECONDS`; tests use 50 ms). A bot turn is typically 3 to 6 updates within 2 to 4 s, so
  animations for one update must normally finish inside ~600 ms or the queue grows.
- Redaction (`settler_island_game/src/event.rs`, `Event::visible_to`): `ResourceStolen.resource` is null unless the
  viewer is thief or victim; `DevelopmentCardBought.card` is null unless the viewer is the buyer. Everything else is
  public, including discards, trades and monopoly amounts.
- `ResourcesProduced` carries seat and counts, not the source tile. Sources are derived for display only (see
  "Production"); a wrong guess is cosmetic because the committed view is authoritative.
- Typical orders: roll = `DiceRolled`, `ResourcesProduced`*, `PhaseChanged`; build = `ResourcesPaid`,
  `SettlementPlaced|RoadPlaced|CityBuilt`, `LongestRoadChanged`?, `GameWon`?, `PhaseChanged`?;
  end turn = `TurnEnded`, `TurnStarted`, `PhaseChanged`.

## Architecture: the `EventPlayer` node

```
GameState --changed(events)--> EventPlayer --beat signals--> Board (overlay), Hud (counts, seats, log)
                                    |  owns: shown_view, shown_legal_actions, FlightLayer (CanvasLayer)
                                    +--> Sfx (hook names only), Toasts
```

`EventPlayer` (`scripts/feedback/event_player.gd`, `class_name EventPlayer`, extends `Node`) is a child of the `game`
scene. `GameScreen.begin` creates `GameState`, then `_player.bind(state, _board, _hud)`. Board and Hud keep
`bind(state)` for `act` and `seat`, but **draw from `player.shown_view` and pick from `player.shown_legal_actions`**,
not from `state.view`. That one indirection is what makes "events play before the view applies" possible without
touching `GameState`.

### Queue model
A *beat* is one update: `{events: Array[SiEvent], view: SiPlayerView, legal_actions: Array[SiAction]}`.
`GameState.changed` pushes a beat (an empty event list from `act` only clears `shown_legal_actions` at once, so a
double click cannot send twice). The player runs one beat at a time:
1. For each event in order: look up its *step* (table below), `await` the step's tween; steps of one event run in
   parallel, events run in sequence (a few marked "overlaps" start before the previous one ends).
2. Commit: `shown_view = beat.view`, `shown_legal_actions = beat.legal_actions`, emit `committed`. Board redraws from
   the new view (pieces it just animated are now drawn by `BoardPainter` exactly where the overlay landed, so the
   overlay is freed in the same frame), Hud resyncs every number from the view.
3. Next beat.

Animations never change state: Hud counters that tick during a beat are display offsets that the commit overwrites.
A bug in an animation therefore cannot leave a wrong count on screen after the beat.

### Lag budget (never more than ~1.5 s behind)
- `backlog_ms` = remaining time of the running beat + nominal durations of all queued beats.
- Speed factor `pace = clamp(backlog_ms / 1500, 1.0, 4.0)` multiplies `Engine`-independent tween speed (each tween
  is created with `set_speed_scale(pace * settings_speed)`); recomputed whenever a beat is pushed.
- If `backlog_ms / pace` still exceeds 1500 ms (more than ~6 s of nominal animation queued, e.g. after a reconnect
  or a long trade negotiation between bots), **collapse**: drop the queued beats' animations, keep only their
  *must-show* events (marked M in the table), play those as toasts/log lines, and commit the last view directly.
- A beat whose update answers the local player's own `act` plays at `pace >= 2`: the player already knows what they
  did; the feedback confirms, it does not narrate.
- `GameStarted` (initial or resync after an error) clears the queue, kills tweens, commits at once.

### Skipping when unfocused
`EventPlayer._notification`: on `NOTIFICATION_APPLICATION_FOCUS_OUT` set `instant = true`; on `FOCUS_IN` clear it.
While `instant`, beats commit immediately, sounds are muted, log lines are still written, and must-show events are
collected into a "While you were away" digest (max 6 lines, oldest dropped) shown as one toast on focus-in. The
turn-start cue for the local player still fires (sound + window attention via
`DisplayServer.window_request_attention()`), so a backgrounded player learns it is their turn.

### Interface (signals and calls)
```gdscript
class_name EventPlayer extends Node
signal committed                          # shown_view / shown_legal_actions changed; Board+Hud redraw
signal beat_started(events: Array[SiEvent])
signal event_started(event: SiEvent)      # Hud appends the log line here, in sync with the animation
signal idle                               # queue drained; Hud enables action buttons
var shown_view: SiPlayerView
var shown_legal_actions: Array[SiAction]
var flight_layer: FlightLayer             # CanvasLayer, layer 10, above Board and Hud
func bind(state: GameState, board: Board, hud: Hud) -> void
func shown_legal_of(script: Script) -> Array[SiAction]
func is_busy() -> bool
```
Calls the player makes into Board (all positions in Board-local pixels, converted with
`board.get_global_transform_with_canvas() * point` before handing them to the flight layer):
`corner_position(corner)`, `edge_midpoint_position(edge)`, `tile_center_position(tile)` (the last two are new
one-liners next to the existing `corner_position`), `spawn_piece(kind, seat, point) -> Node2D` (an overlay child
drawn with the same `BoardPainter` shapes), `pulse_tile(tile, color)`, `set_robber_offset(tile, Vector2)`.
Calls into Hud: `seat_anchor(seat) -> Vector2` (global centre of that seat's panel, card stack area),
`hand_anchor(resource) -> Vector2` (own hand slot), `bank_anchor() -> Vector2`, `dice_anchor() -> Vector2`,
`bump_count(seat, resource_or_minus_one, delta)` (display offset), `flash_seat(seat, kind)`, `set_waiting(text)`.
Each step is a small function `func _step_<event>(event) -> Signal` returning the `finished` signal of the tween it
started (or of a zero-length `create_timer`), so the runner is a flat loop with `await`.

## Techniques
- **Tween only, no AnimationPlayer.** Every animation depends on runtime positions (tile, seat panel, hand slot), so
  code-built tweens are shorter than keyframed tracks. `create_tween()` on the moving node, `set_trans(TRANS_CUBIC)`
  / `TRANS_BACK` for landings, `tween_method` for arcs (quadratic Bézier from start through a control point 30% of
  the distance above the midpoint). The player keeps an array of live tweens and `kill()`s them on collapse/resync.
- **FlightLayer**: a `CanvasLayer` (layer 10) holding pooled `CardToken` nodes (`Node2D` with a `_draw` of a rounded
  rect, resource colour and glyph; or a neutral back). Pool of 24, reused; never freed during a game. Being a
  separate CanvasLayer, cards fly over both the Board `Control` and Hud panels without reparenting.
- **Board overlay pieces** stay children of Board (below the flight layer) so they scale with the island.
- Dice are two `Control`s in the Hud dice area; faces are drawn with `_draw` (pips), so no textures are needed.
- No `_process` polling for animation; the only `_process` is the "waiting" dots (or a looping tween instead).

## Event-to-feedback table
Durations are nominal at speed 1 before `pace`. Q = queues (awaited in sequence); P = parallel with the next event
(overlaps); M = must-show (survives collapse as a toast/log line). "Card back" = neutral card face, used whenever the
viewer may not know the resource.

| Event | Feedback | ms | Q/P | M |
|---|---|---|---|---|
| `SettlementPlaced` | Overlay settlement drops onto the corner from 0.6 hex above, scale 1.3 to 1, `TRANS_BACK`; ring ripple in seat colour; `sfx_place_settlement`. Setup round: also a soft pulse on its adjacent tiles. | 350 | Q | |
| `RoadPlaced` | Road grows from the end touching the seat's network to the other end (`tween_method` on length); `sfx_place_road`. | 250 | Q | |
| `CityBuilt` | Settlement overlay scales up and morphs into city shape (cross-fade two overlays), brief seat-colour flash; `sfx_build_city`. | 400 | Q | |
| `DiceRolled` | See "Dice". Ends with matching number chips pulsing. | 700 | Q | M (sum) |
| `ResourcesProduced` | See "Production": cards fly tile to seat. All `ResourcesProduced` of one beat start together. | 450 | P | |
| `ResourcesPaid` | Cards fly from the seat panel (own: from the hand slots, face up) to the bank anchor, 60 ms stagger; `sfx_pay`. Public counts, so faces are shown for every seat. | 350 | P | |
| `RobberMoved` | Robber lifts (y -0.4 hex, 120 ms), glides along an arc to the new tile (300 ms), lands with a small shake; target tile dims to 60% while the robber stands on it; `sfx_robber_move`. | 500 | Q | M |
| `CardsDiscarded` | Cards fly seat to bank face up (discards are public), 40 ms stagger, slight fan; seat panel flashes amber; `sfx_discard`. Several seats' discards in one beat play together. | 450 | P | M if own |
| `ResourceStolen` | One card flies victim panel to thief panel. Face shown only when `resource != null` (viewer is thief or victim), otherwise card back. Victim panel shakes 3 px; own loss: `sfx_stolen_from_me`, own gain: `sfx_steal`. | 500 | Q | M if involved |
| `BankTraded` | `gave` cards fly seat to bank, then `received` cards bank to seat (overlapping by 150 ms); `sfx_trade_bank`. | 600 | Q | |
| `TradeOffered` | Offer bubble pops out of the offerer's panel (scale 0.6 to 1), shows give/receive glyph rows; addressed seat (or all) panels get an "?" badge; `sfx_trade_offer`; if the local seat is addressed, see "Turn-start cue" (soft variant). | 300 | Q | M if to me |
| `TradeAnswered` | Answering seat's badge turns into a check or cross with a 150 ms pop; `sfx_trade_accept` / `sfx_trade_reject`. | 200 | Q | |
| `TradeCompleted` | Both card sets cross in the air between the two seat panels (faces shown, trades are public), bubble closes; `sfx_trade_done`. | 600 | Q | M |
| `TradeCancelled` | Bubble shrinks and fades; badges clear; `sfx_trade_cancel`. | 200 | Q | |
| `DevelopmentCardBought` | Card flies from the development deck anchor (Hud bank area) to the seat. Buyer sees the face land in the dev-card row (`card != null`); others see a back. `sfx_dev_buy`. | 450 | Q | |
| `DevelopmentCardPlayed` | Card rises from the seat panel to screen centre-top, flips face up (scale.x 1 to 0 to 1, 300 ms), holds 300 ms with its name, then fades; `sfx_dev_play_<card>`. Knight: robber step follows as its own event. | 800 | Q | M |
| `MonopolyTaken` | From every other seat panel, cards of that resource fly to the taker in parallel; the event has only the total, so `amount` face-up tokens leave the other panels spread evenly and the commit sets the true counts; `sfx_monopoly`. | 700 | Q | M |
| `YearOfPlentyTaken` | Two face-up cards fly bank to seat; `sfx_dev_gain`. | 400 | Q | |
| `LongestRoadChanged` | Award badge flies from previous holder (or Hud centre) to the new holder's panel; the holder's road segments glow once on the board (if holder known); `null` holder: badge fades to the centre. `sfx_award_road`. | 600 | Q | M |
| `LargestArmyChanged` | Same as above with the army badge; `sfx_award_army`. | 600 | Q | M |
| `TurnEnded` | Seat highlight fades out (150 ms). | 150 | P | |
| `TurnStarted` | Highlight slides to the new seat panel; local seat: turn-start cue. | 300 | Q | |
| `PhaseChanged` | No animation; Hud phase label cross-fades. `Discard` / `TradeOffered` / `Steal` update the waiting indicator; `Finished` hands over to the victory screen. | 0 | P | |
| `GameWon` | Victory screen (below). Never collapsed, never skipped (shown on focus-in if unfocused). | 2000+ | Q | M |

Unknown event types (protocol grew before the client): log line only, 0 ms, never an error.

## Dice
Two die `Control`s in the Hud dice area, 56 px. On `DiceRolled`:
1. Tumble 450 ms: each die tweens `rotation` by 2 to 3 full turns (`TRANS_QUART`, `EASE_OUT`) while a `tween_method`
   swaps the drawn face every 60 ms through a deterministic sequence derived from the final value (no
   `randi()`, so replays and screenshots are stable). `sfx_dice_shake` at start, `sfx_dice_land` at end.
2. Settle 120 ms: scale 1.15 to 1 on landing, faces show `first` and `second`; sum label pops beside them.
3. Reveal 130 ms: every tile chip with that number pulses (scale 1.25, `TRANS_BACK`); tiles under the robber pulse
   grey instead, which explains a missing production without words.
4. A 7: the dice area flashes the robber colour and the chips do not pulse; `sfx_roll_seven`.
The roller's seat panel shows a small die glyph for the rest of the turn. Last roll stays visible until the next.

## Production
For each `ResourcesProduced` in a beat: source tiles = tiles of `shown_view` (the previous view) whose `number`
equals the roll of this beat, whose index is not `board.robber`, and that touch a corner with a building of that
seat; one token per resource unit, emitted from a matching tile of that resource (round-robin when several tiles
match). In setup (no `DiceRolled` in the beat) the sources are the tiles around the corner of this beat's
`SettlementPlaced`. If no source is found (rules changed, odd data) the tokens start at the bank anchor.
Flight: token spawns at the tile centre at scale 0.4, pops to 1 (80 ms), arcs to the seat anchor (own seat: the hand
slot of that resource) in 370 ms, 50 ms stagger per token, max 12 tokens per seat (beyond that one token carries a
"+n" label). On landing: `bump_count(seat, resource, +1)` and a 1-frame tick on the counter; `sfx_card_gain` at most
once per 80 ms (rate-limited so 8 cards do not machine-gun).

## Card movement and hidden identities
- One helper: `fly_cards(from: Vector2, to: Vector2, resources: Array[int], face_up: bool, stagger_ms: int) -> Signal`
  (`resources` in the protocol's count layout; face_up false draws backs, still one token per unit).
- Face rule: show the face when the event carries the resource (all events except a redacted steal and an unknown
  dev card). The redacted steal is the only hidden resource flow, and it always shows a back to third seats.
- Own hand: tokens land on the matching resource slot; others: on the seat panel's card stack, whose count is the
  only number shown for opponents (as the view gives `resource_count` only).
- Leaving cards (paid, discarded, stolen from me) lift *out of* the slot first: the slot count drops at departure,
  arriving counts rise at landing, so the eye follows a single card.

## Active seat and "waiting for X"
- Seat panels: the current seat (`shown_view.current`) gets a 3 px seat-colour border and a slow breathing glow
  (looping tween on modulate alpha 0.7 to 1.0, 1200 ms period); other panels sit at 85% brightness.
- Waiting indicator: one line under the dice area, derived from `shown_view.phase` and `shown_view.trade` only:
  `Discard` = "Waiting for <names> to discard" (from `remaining`); `TradeOffered` = "Waiting for answers: <names
  without an answer>"; `Steal`/`MoveRobber` = "<name> is moving the robber"; otherwise "<name> is playing" (or nothing
  on the local turn). Animated trailing dots. Every seat that the line names also gets a small hourglass badge on its
  panel. When the local seat is among those waited on, the line reads "Your move: discard 4 cards" in the accent
  colour instead.
- Bots get a "thinking" variant of the glow (faster, 600 ms) so a 600 ms bot pause reads as activity, not a hang.

## Turn-start cue for the local player
On commit of a beat that makes `GameState.is_my_turn()` true where the previous shown view did not (or that adds the
local seat to a waiting list): own panel border pulses twice (2 x 250 ms), a banner "Your turn" slides in from the top
edge of the board (200 ms in, 900 ms hold, 200 ms out, non-blocking, `mouse_filter = IGNORE`), and the newly legal
primary button (Roll, or Discard dialog) does one scale bounce. `sfx_turn_start` (or `sfx_attention` for the softer
discard/trade variant). Unfocused window: `window_request_attention()` plus the sound only.

## Toasts for errors
Reuse `main.gd`'s `show_toast(text)` for transport errors; in game, `GameState.refused` is shown by a `Toasts`
`VBoxContainer` (top-right of the game scene, max 3 visible, newest on top, 3 s each, 4 s for errors) so a toast
never covers the board centre or the action bar. Each toast slides in 150 ms and fades out 250 ms. Kinds: `error`
(red edge, `sfx_error`), `info` (digest, collapse summaries), `alert` (stolen from me, trade offered to me). Errors
are never queued behind animations: they bypass the `EventPlayer` queue.

## Victory screen
On `GameWon`: the queue stops taking new beats (the game is over), the board dims to 50% over 400 ms, the winner's
panel tweens to screen centre and scales 1.6, a ring of seat-colour confetti tokens bursts out of the flight-layer
pool (24 tokens, radial tweens 900 ms, gravity via `TRANS_QUAD` `EASE_IN` on y), and the overlay shows the final
standings sorted by points from `shown_view.players` with award badges. "Back to lobbies" appears after 1200 ms so a
stray click does not skip it. Local win: `sfx_victory`; otherwise `sfx_game_over`. Clicking anywhere completes the
intro animations instantly (kills tweens, jumps to end state).

## Sound hooks
No audio files yet. An autoload `Sfx` (`scripts/feedback/sfx.gd`) exposes `play(hook: StringName)` and looks up
`res://audio/<hook>.ogg`; a missing file is silently ignored (one `push_warning` per hook per session), so hooks can
be wired now and filled later. Pool of 6 `AudioStreamPlayer`s on bus `Sfx`; the same hook within 80 ms is dropped.
Hooks: `sfx_place_settlement`, `sfx_place_road`, `sfx_build_city`, `sfx_dice_shake`, `sfx_dice_land`,
`sfx_roll_seven`, `sfx_card_gain`, `sfx_pay`, `sfx_discard`, `sfx_robber_move`, `sfx_steal`, `sfx_stolen_from_me`,
`sfx_trade_bank`, `sfx_trade_offer`, `sfx_trade_accept`, `sfx_trade_reject`, `sfx_trade_done`, `sfx_trade_cancel`,
`sfx_dev_buy`, `sfx_dev_play_knight`, `sfx_dev_play_road_building`, `sfx_dev_play_year_of_plenty`,
`sfx_dev_play_monopoly`, `sfx_dev_play_victory_point`, `sfx_monopoly`, `sfx_dev_gain`, `sfx_award_road`,
`sfx_award_army`, `sfx_turn_start`, `sfx_attention`, `sfx_error`, `sfx_victory`, `sfx_game_over`, `sfx_ui_click`,
`sfx_ui_hover`.

## Settings
`Settings` autoload (`scripts/settings.gd`), stored in `user://settings.cfg` next to `session.cfg`:
- `animation_speed`: `Off` (0: every beat commits instantly, the log and toasts still work), `Fast` (2.0), `Normal`
  (1.0, default), `Relaxed` (0.75). Multiplies into every tween's speed scale with `pace`.
- `sound_volume` (0 to 1, bus volume), `sound_enabled`.
- `skip_when_unfocused` (default on).
Changes apply to the next tween; a gear button on the game screen opens a small `PopupPanel` with these four rows.
The headless tests set `animation_speed = Off` so `GameState`-driven tests stay as fast as today.

## Readability of others' turns (summary)
A bot turn at default delay reads as: highlight slides to the seat, dice tumble, chips pulse, cards fly to whoever
produced, the bot's build drops in with its payment flying to the bank, the highlight leaves. The log line for each
event appears when its animation starts (`event_started`), so the log and the board never disagree.

## Testing hooks
- `EventPlayer` runs headless; with `animation_speed = Off` it must commit every beat synchronously (unit-testable
  by feeding beats and checking `shown_view` identity).
- A deterministic "replay" scene feeds a recorded game's updates with a fixed delay, for screenshot checks of
  mid-animation frames (`tools/screenshot.gd` style, output under `.build/`).
- Check: backlog never exceeds 1.5 s with `SETTLER_BOT_DELAY_MILLISECONDS=50` (collapse path) and 600 (normal).
