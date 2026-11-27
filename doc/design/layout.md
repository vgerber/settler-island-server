# Game screen layout and interaction flows

Scope: the in-game screen of the Godot client (`scenes/game.tscn`), briefly the lobby screens. Companion to
`doc/plans/godot-client.md`. Original design: genre conventions (board in the middle, hand at the bottom, opponents
at the side), no borrowed art, names or branding.

## Ground rules

1. **Legal actions drive every control.** A button, card, board target or dialog option is enabled only when a
   matching `SiAction` is in `GameState.legal_actions`, and the client sends that very object. Pickers (discard, year
   of plenty, monopoly, bank trade, steal) collect a choice and then look up the matching legal action; if none
   matches, the confirm button stays disabled. The one exception is `OfferTrade` (see "Player trade").
2. **Display logic is allowed, rule logic is not.** Deriving who is pending from `phase` (`Discard.remaining`,
   `trade.to`/`trade.answers`, else `view.current`) or which seats touch a tile is display. Deciding whether a move
   is allowed is not.
3. **Events are shown, the view is truth.** Each `GameUpdate` carries `events` and the new `view`. An `EventPlayer`
   (new, `scripts/hud/event_player.gd`) plays the events of one update in order with short animations, then commits
   the view to the HUD and board. Own input is disabled while a batch plays (at most 3 s per batch; a click on the
   board or Space skips to the end). Without this, a bot round (5 to 15 events in one update) is unreadable.
4. **Errors** (`GameState.refused`) show as a red toast; the screen keeps working.

## Scaling

The project uses `window/stretch/mode = canvas_items`, `aspect = expand`, base 1600x900. Design in base units; at
1280x720 everything is drawn at 0.8. Consequences:
- Minimum font 18 base units (14.4 px at 720p); numbers on cards 22. Minimum click target 40x40 base (32 px).
- `aspect = expand` gives extra width or height to the root; all regions are anchored so the extra goes to the
  board and the log.
- Below 800 real pixels of window height (`get_window().size.y`), the HUD switches to **compact**: log collapsed,
  opponent panels one line shorter, development cards stacked. That is the 1280x720 wireframe below.

## Regions at 1600x900 (base units)

```
0                                                                        1260          1600
+--------------------------------------------------------------------------------------------+ 0
| TopBar  [*] Seat 3 Mira - Main - your turn   | prompt: Build or trade  | bank W5 C3 S9 H1 O0 dev 14 [=] |
+------------------------------------------------------------------------+-------------------+ 48
|                                                                        | Opponents         |
|                                                                        | +---------------+ |
|                                                                        | |# Rolf (bot)  7| |
|                                 Board                                  | | res 5  dev 2  | |
|                         1260 x 676, island fit                         | | [army 3] [rd] | |
|                                                                        | +---------------+ |
|            Toasts (top centre of board, 480 wide, stack of 3)          | | ...  x3, 96 hi| |
|                                                                        | +---------------+ |
|                                                                        | Log / Chat   [v]| |
|                                                                        | turn 42: Rolf   | |
|                                                                        | rolled 8 ...    | |
|                                                                        |   (fills rest)  | |
+------------------------------------------------------------------------+                   | 724
| Own        | Hand: [Wood 3][Clay 1][Sheep 4][Wheat 0][Ore 2]  | Dev: [Kn 1][VP 1][new Mo] | [5][2] =7 |
| # Mira  6  |   each 72x100, count badge, total 10             |  64x100 each              | [ ROLL   ]|
| /10 pts    |                                                  |                           | [Rd][St][Ci]|
| rd 9 st 2  |                                                  |                           | [Dv][Tr][End]|
| ci 3       |                                                  |                           |           |
+--------------------------------------------------------------------------------------------+ 900
0      180                                                    760                        1100  1600
```

- **TopBar** (48 high): turn banner with seat colour swatch and name, a one-line prompt for the own seat ("Place a
  settlement", "Discard 4 cards", "Waiting for Rolf..."), then bank counts as five small resource chips, the
  development deck count, and a menu button (leave, sound, fast animations).
- **Board** (1260x676): the existing `Board` control. Only board overlays live here (target highlights, ghost
  pieces, floaters, robber popover).
- **Opponents column** (right, 340 wide): one `PlayerPanel` per other seat in seat order starting after the own seat,
  so the order matches the turn order. Below it the log.
- **BottomBar** (176 high, full width): own summary, resource hand, development hand, dice plus action bar.

### Godot tree and anchors (`scenes/game.tscn`)

```
GameScreen (Control, full rect)
  Board            Control  anchors full; offset_top 48, offset_right -340, offset_bottom -176
  Hud              Control  anchors full, mouse_filter IGNORE (children STOP)
    TopBar         PanelContainer  preset TOP_WIDE, offset_bottom 48
      Margin       MarginContainer  margins 12/4/12/4
        Row        HBoxContainer   separation 16
          TurnBanner   HBoxContainer (ColorRect 20x20 swatch, Label)      size_flags_h FILL
          Prompt       Label  size_flags_h EXPAND_FILL, centred, clip
          BankRow      HBoxContainer  5 x ResourceChip (icon 24 + count) + DevDeckChip
          MenuButton   MenuButton 40x40
    SideColumn     VBoxContainer  preset RIGHT_WIDE, offset_left -340, offset_top 48, offset_bottom -176, separation 8
      Opponents    VBoxContainer  separation 6; children PlayerPanel (custom_minimum_size 340x96)
      LogPanel     PanelContainer size_flags_v EXPAND_FILL
        Header     HBoxContainer (Label "Log", collapse Button)
        Scroll     ScrollContainer -> RichTextLabel (bbcode, seat-coloured names, fit_content)
    BottomBar      PanelContainer  preset BOTTOM_WIDE, offset_top -176
      Margin       MarginContainer margins 12/8/12/8
        Row        HBoxContainer separation 20
          OwnSummary   VBoxContainer  custom_minimum_size 160x0
          HandRow      HBoxContainer  separation 8; 5 x ResourceCard 72x100
          VSeparator
          DevRow       HBoxContainer  separation 6; DevCard 64x100 per kind (count badge)
          Spacer       Control size_flags_h EXPAND_FILL
          DiceBox      VBoxContainer  2 x Die 56x56 in an HBox + sum Label
          ActionGrid   GridContainer columns 3, separation 6; buttons 64x56, Roll/End span via wider 200x56 row
  Overlay          Control  anchors full, mouse_filter IGNORE
    Toasts         VBoxContainer anchored top centre of the board rect, width 480, offset_top 60
    Dialog         CenterContainer over the board rect; hosts one modal panel at a time
```

`PlayerPanel` (340x96): left a 8-wide stripe in seat colour; row 1 name (bot marker "bot" suffix), points large on
the right; row 2 resource card count (card icon + number, red when > 7) and development card count; row 3 badges:
knights played, "army" badge when `largest_army == seat`, "road" badge when `longest_road == seat`, pieces left as
small text. The pending state shows as a pulsing border plus a status line ("rolling", "discarding 4",
"answering trade", "thinking").

Player names are not in `SiPlayerView`; the game screen keeps the `SiLobbyDetails.seats` from the last
`LobbyState` (main.gd already receives it) and falls back to "Seat N". Seat colours: fixed palette indexed by seat,
same as the board painter.

## Regions at 1280x720 (real pixels, compact)

```
0                                                              1008          1280
+--------------------------------------------------------------------------------+ 0
| [*] Seat 3 Mira - Main     | Build or trade |  W5 C3 S9 H1 O0  dev 14 [=]      | 38
+----------------------------------------------------------------+---------------+
|                                                                | # Rolf      7 |
|                                                                | res 5 dev 2 A |
|                           Board                                +---------------+ 
|                    1008 x 541, island fit                      | # Kai       5 |
|                                                                | res 2 dev 0 R |
|                                                                +---------------+
|                                                                | # Lin       4 |
|                                                                | res 9! dev 1  |
|                                                                +---------------+
|                                                                | [Log (3 new)] |
+----------------------------------------------------------------+---------------+ 579
| # Mira 6/10 | [W3][C1][S4][H0][O2] 58x80 | [Dev 3 v] | [5][2]=7 [ROLL ] [Rd][St][Ci] |
| rd9 st2 ci3 |                            |           |          [Dv][Tr][End]       |
+--------------------------------------------------------------------------------+ 720
```

- Same tree, scaled 0.8: TopBar 38, side column 272, bottom bar 141, board 1008x541.
- Compact switches: `PlayerPanel` drops row 3 into single-letter badges at the end of row 2 (A army, R road) and
  becomes 72 base high; the log collapses into a button that opens it as a popup over the side column and shows an
  unread count; development cards collapse into one stacked card "Dev 3" that opens a small popover with the cards
  and their play buttons.

## Board targets: one decision for all phases

**Decision: forced phases use direct click; the Main phase uses armed build modes.**

- Forced phases (`SetupSettlement`, `SetupRoad`, `MoveRobber`, `RoadBuilding`) have exactly one kind of target and
  nothing else to do, so their targets are highlighted at once and one click sends the action. An extra "arm" click
  would add nothing.
- In `Main`, building spends cards and the three kinds overlap (a city target sits on a settlement corner; a
  road and a settlement near each other compete for the cursor). Showing every legal road, settlement and city at
  once fills the board with rings. So the action bar has Road, Settlement and City buttons; a button is enabled when
  at least one `BuildRoad`/`BuildSettlement`/`BuildCity` is legal and its tooltip shows the cost. Pressing it arms
  the mode: the board highlights only that kind, the button stays pressed, the prompt says "Place a road (Esc to
  cancel)". A click on a target sends the action and disarms. Esc, right click or pressing the button again
  disarms. Keys 1/2/3 arm road/settlement/city.
- After a build the mode stays armed when the same kind is still legal and the player held Shift (fast road chains);
  otherwise it disarms. The board exposes `set_target_filter(kinds: Array[Script])`; the HUD sets it, the board still
  builds targets only from legal actions.
- Hover on a target draws a translucent ghost piece in the own colour; the pointer becomes a hand. Invalid spots
  never react.

## Flows

### Setup placement
1. `TurnStarted`/`PhaseChanged` to `SetupSettlement` for the own seat: prompt "Place your first settlement"
   (round 2: "second settlement, it yields its neighbours' resources"); the turn banner pulses once; every legal
   `PlaceSettlement` corner shows a soft pulsing ring.
2. Hover shows the ghost settlement; click sends `PlaceSettlement`. The piece drops in (scale 1.3 to 1.0, 150 ms).
3. Phase `SetupRoad`: the new settlement gets a glow; legal `PlaceRoad` edges (only next to it) highlight. Click sends.
4. Round 2 settlement: `ResourcesProduced` for the own seat flies one card per resource from each adjacent tile into
   the hand (300 ms each, staggered 80 ms).
5. Other seats: their panel is pending ("placing"); their placement animates the same way at the event player's
   pace. The setup order (1-2-3-4-4-3-2-1) shows as a small arrow next to the pending panel.

### Rolling and production
1. Phase `Roll` for the own seat: the Roll button is the large primary button (Space also rolls); if `PlayKnight` is
   legal, the Knight dev card is highlighted too ("play before rolling").
2. `DiceRolled`: both dice tumble 600 ms, settle on the values, the sum appears next to them. The log line follows.
3. Tiles with the rolled number flash (outline brightens, 2 pulses); the tile with the robber shows the robber
   shaking and a strike-through on the chip, so a blocked tile is visible.
4. `ResourcesProduced` per seat: own seat gets cards flying from the tiles into the hand cards, whose count badges
   tick up; other seats get "+3" floaters on their panel (count only, since `resource_count` is what they may see,
   but the event lists resources per seat publicly, so the floater may show small icons).
5. Nothing produced: toast "No production" for the own seat only when it had buildings on that number blocked by
   the robber ("Robber blocks 6 on Clay"), else silent.
6. A 7: dice turn red, banner toast "Seven: robber moves", then the Discard or MoveRobber flow.

### Building (Main phase)
Arm via button or key, click a highlighted target (see above). `ResourcesPaid` animates the spent cards from the hand
to the bank chips in the top bar; `SettlementPlaced`/`CityBuilt`/`RoadPlaced` drop the piece. Points change: the own
summary number pops (scale 1.2, 200 ms). `LongestRoadChanged`/`LargestArmyChanged`: the badge slides from the old
holder's panel to the new one, toast "Kai takes the longest road (+2)".

`BuyDevelopmentCard`: button "Card" with cost tooltip; on `DevelopmentCardBought` a face-down card flies from the
top-bar deck to the dev row and flips (own seat) or to the panel (others, stays face down).

### Development cards
- Dev row shows one card per kind with a count; cards in `own.new_development_cards` are dimmed with a "new" corner
  tag (not playable this turn). Victory point cards show with a star and are never clickable.
- A card is clickable only when its play action is legal (`PlayKnight`, `PlayRoadBuilding`, any `PlayYearOfPlenty`,
  any `PlayMonopoly`); a clickable card lifts 8 units on hover.
- Knight: sends `PlayKnight`, then the MoveRobber flow. Road building: sends `PlayRoadBuilding`; phase
  `RoadBuilding` with direct-click edges, prompt "Free road 1 of 2" from `roads_left`.
- Year of plenty: dialog with the five resources twice (first pick, second pick, same allowed); the confirm button
  enables when the pair matches a legal `PlayYearOfPlenty` (resources the bank lacks are disabled because no legal
  action contains them). Monopoly: dialog with five resource buttons, each enabled when a legal `PlayMonopoly` has
  it. `MonopolyTaken`: cards fly from every panel to the hand; toast "Mira takes 5 Wheat".

### Robber after a 7
1. Phase `Discard`: each seat in `remaining` with a count > 0 is pending ("discarding 4" on its panel).
2. Own seat pending: a **discard dialog** opens over the board, not over the hand, so the hand stays visible. The
   dialog shows the hand as five resource columns with +/- (or click a hand card to move one into the dialog's
   discard tray, right click to take it back). Header "Discard 4 of 10". "Discard" enables when the selected
   counts equal a legal `Discard.resources`. No cancel: the dialog is the only thing to do; the board stays visible
   for context.
3. Own seat not pending: no dialog; the prompt says "Waiting for 2 players to discard". `CardsDiscarded` shows
   cards flying from that panel to the bank.
4. Phase `MoveRobber` (own seat): prompt "Move the robber"; every legal `MoveRobber` tile shows a highlight on its
   number chip; hovering a tile shows the colour dots of seats with buildings on its corners (who could be robbed).
   Click sends. The robber slides to the tile (250 ms).
5. Phase `Steal`: a popover anchored at the robber tile lists one button per legal `Steal` victim: seat colour,
   name, card count. The matching opponent panels pulse too and are clickable as an alternative. When there is
   exactly one victim, still show the popover (one click, no auto-steal: the player should see who was robbed).
6. `ResourceStolen`: thief and victim see the actual resource card fly between hand and panel (`resource` is set
   for them); everyone else sees a face-down card. Toast for the victim: "Rolf stole 1 Ore".

### Bank and port trade
1. "Trade" button opens the **trade panel** as a dialog over the lower half of the board with two tabs: Bank and
   Players. Bank is the default tab when any `BankTrade` is legal.
2. Bank tab: top row "Give" with the five resources, each enabled when some legal `BankTrade` has that `give`;
   bottom row "Get", enabled for the `receive` values legal with the selected give. The rate label ("4:1", "3:1",
   "2:1") comes from a display lookup of own buildings on ports; the protocol action carries no rate (see open
   questions). "Trade" sends the matching action; the panel stays open for chained trades and refreshes from the
   new legal actions. `BankTraded` animates cards hand to bank and back.

### Player trade
1. Players tab (own turn, phase `Main`): two resource rows, "You give" and "You get", each with +/- counters;
   "You give" counters are capped by the own hand (display), "You get" by nothing. Target: "Everyone" or one seat
   chip. "Offer" sends `OfferTrade`.
2. `OfferTrade` is not in `legal_actions` (the server cannot enumerate offers), so the Players tab is enabled when
   `EndTurn` is legal (own turn, Main phase), and the server validates; a refused offer shows its error as a toast.
3. Phase `TradeOffered`, addressed seats: a **trade card** shows in the side column between the opponents and the log, never over the island (not modal):
   offerer colour and name, "gives 2 Wood, wants 1 Ore", buttons Accept (only when `AcceptTrade` is legal, which
   also means the player holds the cards) and Decline (`RejectTrade`). The own hand highlights the cards that would
   leave it.
4. Offerer: the trade panel turns into a status view with one row per addressed seat: waiting (pulsing dots),
   accepted (green, with a Confirm button for its legal `ConfirmTrade{with}`), declined (grey). "Withdraw" sends
   `CancelTrade`. Bots answer quickly; the event player still shows each answer for 400 ms.
5. `TradeCompleted`: cards cross between the two panels/hand; toast "Traded with Kai". `TradeCancelled`: the trade
   card slides out; toast for addressed seats "Offer withdrawn".

### End of turn and waiting
- "End turn" (`EndTurn`, Enter key) is the primary button once the roll is done; Roll and End turn share the same
  wide slot so the main button never moves.
- While other seats play, all own buttons are disabled, the prompt reads "Waiting for Rolf (bot)", and Rolf's panel
  has the pending border plus a three-dot "thinking" indicator. Multi-seat waits (discard, trade answers) mark every
  pending seat. A human seat pending more than 20 s shows a small timer on its panel (display only).
- `TurnStarted` for the own seat: short chime, turn banner flashes, the window requests attention when unfocused.

### Game over
`GameWon` / phase `Finished`: the event player finishes the batch, then a centred overlay (520x420) dims the board:
winner colour and name, "wins with 10 points", a ranking table (seat, name, points, knights, badges), buttons
"Show board" (hides the overlay, a small "Results" button stays in the top bar) and "Back to lobbies" (sends
`LeaveLobby`). The own result line is highlighted.

## Feedback table

| Event | Board | HUD | Toast | Log |
|---|---|---|---|---|
| TurnStarted | - | banner, pending border moves | own turn only | yes |
| DiceRolled | number tiles flash, blocked tile marked | dice tumble, sum | 7 only | yes |
| ResourcesProduced | cards fly from tiles | hand badges / panel floaters | - | yes, per seat |
| Road/Settlement/City | piece drops | points pop | - | yes |
| ResourcesPaid, BankTraded | - | cards to/from bank chips | - | trades only |
| DevelopmentCardBought | - | card flies from deck | - | yes |
| DevelopmentCardPlayed | - | card flips face up on panel 800 ms | yes | yes |
| CardsDiscarded | - | cards from panel to bank | - | yes |
| RobberMoved | robber slides | - | - | yes |
| ResourceStolen | - | card victim to thief | victim and thief | yes |
| Trade offered/answered/completed | - | trade card, status rows | completed, cancelled | yes |
| Longest road / largest army | - | badge slides between panels | yes | yes |
| GameWon | - | overlay | - | yes |
| Server error (`refused`) | - | - | red, 4 s | no |

Toasts: max three stacked, 3 s, newest on top, seat-coloured left stripe. Log lines use seat-coloured names and keep
the whole game (RichTextLabel, auto-scroll unless the user scrolled up).

## Lobby screens (brief)
- Lobby browser: keep the current two columns (list left, create right). List rows show name, owner, seats as
  filled/total dots, points to win, lock icon, "running" tag; double click joins. Password field appears only when
  the selected lobby has one.
- Lobby room: a centred panel with one seat card per seat in its seat colour (name, "you", "bot (medium)", "open");
  the owner sees "Add bot" on open seats and "Remove" on bot seats directly on the card instead of a separate row.
  Start is enabled for the owner when no seat is open; others see "Waiting for the owner to start".

## Open questions for the lead
- `OfferTrade` cannot be listed in `legal_actions`; the client gates the offer builder on `EndTurn` being legal.
  A boolean `can_offer_trade` in the view (or one template action) would keep the "legal actions drive the UI" rule.
- `BankTrade` has no rate field; the rate label needs a display lookup of ports. Adding `rate` to the action (or
  per-resource rates to `SiOwnView`) would remove it.
- Seat names are not in the game view; the client relies on the last `LobbyState`. A rejoin goes through
  `JoinLobby`, so `LobbyState` arrives before `GameStarted`, but this should be confirmed.
