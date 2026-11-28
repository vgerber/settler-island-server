# HUD drafts: comparison and recommendation

Four directions for replacing the flat HUD. Each meets the two hard requirements on paper: state is shown in the 3D
scene, and cards are 3D objects (own hand in a camera-fixed rig, opponent backs, bank stacks, trade cards). They
differ in how much of the screen they give to the board and how much they build as table furniture.

| Draft | Idea in one line | Mockups |
|---|---|---|
| [Clear Table](clear-table.md) | Full-bleed board, pawns on the seat trays, a thin walnut frame at the edges. | [build](clear-table-build.png), [trade](clear-table-trade.png) |
| [Crafted Table](crafted-table.md) | Full-bleed board, every control is a table fixture: sign, bell, build slab, bank rack, award board. | [build](crafted-table-build.png), [trade](crafted-table-trade.png) |
| [Card Table](card-table.md) | One held fan at the bottom holds resources, dev cards and the build actions as recipe cards. | [build](card-table-build.png), [trade](card-table-trade.png) |
| [Seat Mats](seat-mats.md) | The island sits in an inset; four felt mats on the rim, one per player, plus build board and bank. | [build](seat-mats-build.png), [trade](seat-mats-trade.png) |

The current screens are in [current/](current/).

## Requirement 3: every action is a proper animation

Added by the user after the drafts. It applies to whichever draft is built. Nothing appears, disappears or changes
count in a snap: each action, own or remote, moves real objects from where they were to where they go.
Examples: a card leaves the hand tray, a piece leaves the supply and lands on the board, the bell is struck, an offer
slides out on the sea. Counts change when the moving object arrives. Cut-short and "animations off" paths stay as
today (`finish_all`).

What `board3d/motion/` covers today, and what is missing:

| Area | Today | Missing |
|---|---|---|
| Dice, production, building, robber, awards, win | Tumble, pulses, drop/grow/morph, robber hop, badge flight, confetti | Pieces come from nowhere instead of the seat's supply; the road grow was made for the old mesh |
| Cards (pay, produce, steal, discard, bank, trade, dev, monopoly, year of plenty) | Flat two-quad tokens on a curve; the end over the 2D hand is a flat 2D token | Real card meshes (thickness, bevel) that land in the 3D hand tray, seat trays and bank rack and stack there |
| Trade offered, answered, cancelled | No 3D motion, HUD panel only | Offer cards slide out at the offerer's side; answers as a tick/cross flip at each seat; cancel slides back |
| Turn started, ended; phase changed | HUD banner and glow only | Bell strike, seat lamp moves to the next seat, sign or banner turns over on a phase change (discard, robber, setup) |
| Own interactions (pick build, select cards, open trade, choose a steal victim) | Instant HUD state changes | Lift and hover of the chosen card or piece, ghost piece follows the cursor, selected cards rise in the tray |

## Comparison

| | Clear Table | Crafted Table | Card Table | Seat Mats |
|---|---|---|---|---|
| Removes the uncanny feel | Mostly. Beige panels, grey buttons and 2D dice are gone. The draft calls itself the most "app" of the four: small walnut plates still float over the table. | Best. Almost every control is an object (bell, slab, rack, sign). One material family. | Partly. The hand feels physical, but plaques stay 2D, and the trade mat is a big dialog over the middle of the board. | Partly. Mats match the table, but the island goes back into a framed window, which the diagnosis named as a cause. |
| Board visibility | Best. Island fills about 60% of the frame, nothing covers a hex. | Very good. Same framing; fixtures sit on the sea. The prompt sign and trade mat cover sea only. | Weak. The fan overlaps the bottom hexes unless the camera moves up. The trade mat covers the centre of the board. | Good but small. Nothing ever covers a hex, but the island shrinks to about 48% of the frame. Tile chips need a scale-up at 720p. |
| State on the board (requirement 1) | Good. Raised and lit pawn, tokens, ghost targets, robber light. Opponent detail is thin by default. | Very good. Lit station, tokens, award board that shows unclaimed awards and their thresholds. | Good. Adds "Robber blocks 8" and rings on producing and blocked chips. | Best. Verb props (dice cup, hammer, scale) at the acting mat, port ownership rings, robber label, supply pieces on every mat. |
| 3D cards (requirement 2) | Yes. Small stacks; bank stacks are tiny. | Yes. Hand tray, bank rack, backs on the seat trays. | Furthest. Build actions are cards too. | Yes. Large backs on every mat; easy to count. |
| Legibility at 1280x720 | Weakest. Bank cards fall to about 24x30 px, pieces-left icons are tiny. | Mixed. Hand holds 66x90. Mini cost cards on the build slab fall to about 11x15 px. | Good. Recipe cards and costs are large. Recipe names at 14 px are near the floor. | Best on paper. But the mockups draw the mats flat; in 3D the top and side mats will foreshorten. |
| Fit with the 3D clay table | Good. | Best. Bell, trays and rack look like they belong to the same table. | Good for cards, weaker for the 2D plaques and the centre mat. | Mixed. Large saturated felt rectangles (red, blue) compete with the island. |
| Effort | Lowest. About 3 waves. | High. About 6 sequential tasks; the most modelling. | High. About 3 to 4 agent-weeks. | Highest. About 4 to 5 agent-weeks, 5 waves; camera framing changes too. |
| Main risk | Too minimal: players miss subtle cues; bank and edges hard to read. | Busy table with eight fixtures; many new meshes. | Input routing between the fan viewport and the board camera; build-as-card is unfamiliar. | Shrinks the board; flat mockups hide perspective problems. |

Mockup caveats, shared by all four: backgrounds are old renders, so ghost targets are drawn over the old gold bars
and look heavier than they will in the engine. Fonts are stand-ins. Judge ghosts and sizes in the engine.

## Recommendation

Build **Crafted Table**. It is the only draft that removes the "app glued to a scene" feel without shrinking the
board, and its controls explain themselves (bell ends the turn, a pile of cards is a hand). Stage it so the first
wave equals Clear Table: thin frame, banner, ticker, 3D hand, seat stations. The fixtures (bell, slab, rack, award
board) follow. Every wave then ships a better screen.

Graft these:
- From **Seat Mats**: one colour per meaning (gold = points and awards, teal = you can act, warm lamp = whose turn,
  red-orange = refusal). Verb props at the acting seat. Supply pieces and award sockets at every seat. Port
  ownership rings and the robber label. Clockwise seat order. The state-source test (banner, lamp and tokens agree
  in every phase) and the headless 13 px label test.
- From **Card Table**: Bitter for every digit (Atkinson's zero is slashed; a font feature may not exist to turn it
  off). Larger cost display on the build actions: mini cards at least 18x24 px at 720p, with "need 1 more" under
  them. "Robber blocks 8" and rings on producing and blocked chips. The bank as one clear row with six counts.
- From **Clear Table**: the camera-fixed hand rig details (fixed order, hollow slots, reading spot, picking against the
  resting pose). Hide controls that do not apply instead of greying them. Clean view on H as a test that the scene
  alone carries the state.
- Reject from Card Table: the trade mat in the board centre. Trade stays on the sea at the offerer's side.

## Questions for you

1. The board can fill the whole window with objects at its edges (Crafted, Clear), or sit in an inset with a frame
   that nothing ever overlaps (Seat Mats). Which do you prefer?
2. Should build actions be pieces on a wooden slab beside the hand (Crafted), or cards in the hand fan that you play
   (Card Table)?
3. How much opponent detail should be visible without hovering: name, points, cards, dev cards and awards only, or also
   pieces left and knights on every seat?
