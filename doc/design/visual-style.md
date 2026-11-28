# Visual style: Godot client

Art direction for `client/godot/`. Working title of the look: **map table by lamplight**. The board is a hand-inked
map lying on a dark walnut table; the UI is parchment and card stock laid on that table; pieces read like painted
wooden tokens with an ink outline. Everything is drawn with `_draw` primitives first, so no external art is needed;
fonts are the only assets. Original design: genre conventions (hexes, number chips with pips, a robber pawn, two
dice) are used, but no colours, shapes, names or icons of any commercial edition or app.

Design resolution is the project's base viewport, **1600x900** (`stretch/mode = canvas_items`); at 1280x720
everything renders at 0.8x. All pixel sizes below are at 1600x900. Rule that follows: no text under 16 px at base
(12.8 px at 720p) and no click target under 32 px at base.

## 1. Palette

Contrast ratios are WCAG 2 relative-luminance ratios. Colour-blind checks are CIELAB ΔE after Machado 2009
simulation (deuteranopia, protanopia, tritanopia, severity 1.0); a pair is "safe" at ΔE >= 15, the script used is
reproducible from the hex values below.

### Terrain, sea, table

| Role | Name | Hex | Pattern colour | Rel. luminance |
|---|---|---|---|---|
| Wood (forest) | Pine | `#33603D` | `#244A2D` trees, `#4F8457` tips | 0.094 |
| Sheep (pasture) | Meadow | `#A2C46A` | `#86A852` tufts, `#F6F1E4` sheep | 0.482 |
| Wheat (fields) | Harvest | `#EDC24F` | `#C99A2E` stalks | 0.572 |
| Clay (pits) | Terracotta | `#B5653D` | `#8E4A2A` bricks, `#D08A5F` mortar | 0.195 |
| Ore (mountains) | Slate | `#7A8492` | `#5A636F` rock, `#DCE0E5` snow | 0.227 |
| Desert | Dune | `#EADDB6` | `#D3C291` dunes | 0.726 |
| Sea | Deep water | `#2A6672` | `#357A86` wave marks | 0.112 |
| Shallow rim | Shoal | `#3E8790` | – | – |
| Beach / tile grout | Sand | `#D9C48F` | – | – |
| Table (screen background) | Walnut | `#2A1F19` | `#33261F` grain lines | – |

Terrain luminance is spread on purpose (wood < clay ≈ ore < sheep < wheat < desert) so tiles separate in greyscale
too. Closest terrain pairs: normal vision sheep/desert ΔE 35; deuteranopia sheep/clay 21; protanopia wood/clay 16,
sheep/wheat 18; tritanopia sheep/ore 21. The pairs near the limit are the ones the motifs (section 3) separate:
trees vs bricks, tufts vs stalks.

### Seats

| Seat | Name | Fill | Outline | Keyline (outer halo) |
|---|---|---|---|---|
| 0 | Crimson | `#D41F3A` | `#231C17` | `#F4EFE3` |
| 1 | Cobalt | `#2F4FE0` | `#231C17` | `#F4EFE3` |
| 2 | Rose | `#FF8AC0` | `#231C17` | `#F4EFE3` |
| 3 | Plum | `#4A2680` | `#F4EFE3` | `#231C17` |

The seats use hues no terrain has (the board is orange, green, yellow, grey, teal): a red-magenta, a blue, a pink and
a violet, so they pop on every tile, the sea and the walnut. Matte clay pieces keep these saturated but muted by
`ClayPalette.seat`. Lightness is spread (L* 46, 41, 72, 25) so a colour-blind player still has a second cue.

Seat vs seat, minimum ΔE (Machado simulations): normal 36, deuteranopia 40, protanopia 34, tritanopia 32. The one
weak seat/terrain pair is Crimson on Terracotta and Pine under red-green blindness (deut 6, prot 7); the cream keyline
and the rim light cover it, and Crimson is the only warm seat.

Every piece still gets an outline plus a contrasting keyline: the outline `#231C17` is dark against every terrain and
the sea, and the cream keyline has 6.4:1 against Pine and 5.6:1 against the sea. Plum inverts it (cream outline). So
a piece separates from the ground by a dark-light double line, and seats differ by fill.

HUD redundancy: each seat also has an emblem drawn next to its name and on its cards in the HUD: Crimson circle,
Cobalt triangle, Rose square, Plum diamond.

### UI surfaces and text

| Token | Hex | Use | Contrast |
|---|---|---|---|
| `table` | `#2A1F19` | screen background | – |
| `parchment` | `#F2E8D2` | panels, dialogs | – |
| `parchment_deep` | `#E6D8BA` | inset rows, list stripes | ink 10.8:1 |
| `card_stock` | `#FBF5E6` | cards, chips base | ink 13.9:1 |
| `ink` | `#2E241C` | text on light surfaces | 12.5:1 on parchment |
| `ink_muted` | `#6B5A45` | secondary text on parchment | 5.4:1 |
| `cream` | `#F3EADB` | text on table / dark panels | 13.5:1 on walnut |
| `cream_muted` | `#BFAE95` | secondary text on walnut | 7.4:1 |
| `border` | `#8A6A44` | panel and button borders | – |
| `accent` | `#1E6B63` | primary button (teal lacquer) | white 6.3:1 |
| `accent_hover` | `#26807A` | | white 4.7:1 |
| `accent_pressed` | `#15524C` | | white 9.0:1 |
| `button` | `#E2D3B2` | secondary button | ink 10.3:1 |
| `disabled_fill` / `disabled_text` | `#D9CDB5` / `#7A6E5E` | disabled controls | 3.2:1 (exempt, still legible) |
| `danger` | `#A3332A` | leave, reject, discard warnings | white 6.9:1 |
| `focus` | `#E8A93A` on dark, `#8C5A0E` on light | focus ring, target highlight | 7.8:1 / 4.8:1 |
| `hot_number` | `#B5281F` | 6 and 8 on chips | 5.5:1 on chip |

## 2. Typography

Two families, both SIL Open Font License, from Google Fonts. Add under `client/godot/assets/fonts/` with their
licence files:

- `Bitter-Bold.ttf`, `Bitter-SemiBold.ttf`, `Bitter-OFL.txt` (slab serif: headings, chip numbers, dice totals,
  card titles; slab numerals stay readable at 14 px and feel printed).
- `AtkinsonHyperlegible-Regular.ttf`, `AtkinsonHyperlegible-Bold.ttf`, `AtkinsonHyperlegible-OFL.txt` (body, buttons,
  event log; designed for low-vision legibility, distinct 1/l/I and 6/8/9).

Import settings: antialiasing on, hinting light, `generate_mipmaps` off, MSDF **on** for Bitter-Bold (board text is
drawn at many sizes as the board scales), off for Atkinson.

| Style | Font | Size (base) | Use |
|---|---|---|---|
| Display | Bitter Bold | 40 | screen titles, game over |
| Heading | Bitter SemiBold | 28 | panel titles |
| Subheading | Bitter SemiBold | 22 | player names, dialog sections |
| Body | Atkinson Regular | 20 | default theme font |
| Body strong | Atkinson Bold | 20 | buttons, counts |
| Small | Atkinson Regular | 16 | event log, captions, tooltips |
| Board text | Bitter Bold | in hex units | chips 0.26 / 0.30, port rates 0.18 |

Line spacing: Label `line_spacing` 2. Numbers in counts use Atkinson Bold, never the muted colour.

## 3. Board rendering (procedural)

Layer order in `Board._draw`: table, sea with wave marks, shoal rim, sand rim, tiles, tile motifs, chips, ports,
roads, buildings, robber, targets, hover preview.

- **Sea:** fill the board rect with Deep water; scatter wave marks on a fixed grid (every 0.9 hex units, offset every
  other row, skip points within 1.25 of any tile centre): each mark is two short arcs, `draw_arc` radius 0.12, 0.02
  wide, in `#357A86`. Deterministic, no RNG, so screenshots compare.
- **Coast:** shoal hexes at scale 1.18 (as now, Shoal colour), then sand hexes at scale 1.05, then tiles at 0.955.
  The sand shows as a beach around the island and as thin grout between tiles, replacing the light `TILE_EDGE`
  polyline. Tile outline: 0.02 wide, terrain colour darkened 0.25.
- **Shading:** each tile gets a soft inner light: a second hexagon at scale 0.80 offset (−0.03, −0.04) in the terrain
  colour lightened 0.06. One extra polygon, reads as a slight bevel.
- **Motifs** replace the text resource label. They sit in two bands, upper centred at (0, −0.55) and lower at
  (0, +0.55), each at most 0.7 wide and 0.3 tall, so they clear the chip (radius 0.3) and the corner pieces.
  The hover tooltip of a tile names the terrain for anyone who wants the word.
  - Wood: three conifers per band (0.22 apart): two stacked triangles in `#244A2D`, a 0.03 light stroke on the
    upper-left edge in `#4F8457`, a 0.03 x 0.05 trunk.
  - Sheep: upper band three grass tufts (three short lines fanning up, `#86A852`); lower band two sheep: three
    overlapping cream circles r 0.05 plus a `#2E241C` head dot r 0.025.
  - Wheat: three sheaves per band: a 0.025 stalk and three chevrons (polylines) up its top, `#C99A2E`.
  - Clay: two courses of three bricks per band, rounded rects 0.16 x 0.07 drawn as polygons in `#8E4A2A` with the
    upper course offset half a brick; mortar is the terrain colour showing through.
  - Ore: two peaks per band: a triangle in `#5A636F` with a snow cap (the top third, `#DCE0E5`) and a 0.02 ridge
    line.
  - Desert: two dune arcs per band (`draw_arc`, 0.03 wide, `#D3C291`) and one small rock (ellipse polygon). No chip,
    so a third dune arc sits at the centre.
- **Number chips:** disc r 0.30 in `card_stock`, a drop shadow (same disc offset (0.015, 0.025), `#000000` alpha
  0.28), rim 0.025 in `#7A5E3A`, an inner hairline ring at r 0.25 (0.01, alpha 0.35). Number in Bitter Bold, 0.26
  high in `ink`; 6 and 8 at 0.30 in `hot_number` plus a second rim ring, so "hot" is not carried by colour alone.
  Pips under the number: r 0.022, spacing 0.065, y +0.17, same colour as the number.
- **Ports:** a two-plank pier from each coast corner to the marker: two parallel lines 0.035 wide in `#7B5634`,
  0.05 apart, with cross ties every 0.1 in `#5C3F26`. The marker is a badge r = `PORT_RADIUS`: `card_stock` fill,
  drop shadow like chips. Generic 3:1: rim 0.03 in `ink`, text "3:1" Bitter Bold 0.20. Specific 2:1: rim 0.06 in the
  resource's terrain colour, "2:1" at 0.16 above a 0.16 mini resource icon (section 4) below. No coloured fill with
  text on top (avoids the current white-on-Wood case).
- **Roads:** capsule from 0.16 to 0.84 of the edge: keyline 0.24 wide, outline 0.19, fill 0.12 (round caps via
  `draw_line` plus `draw_circle` at both ends), and a 0.03 highlight line along the upper side in fill lightened 0.25.
- **Settlement:** keep the house silhouette; draw keyline (polygon grown by 0.035), outline 0.03, fill, then the
  roof triangle in fill lightened 0.18 (a lit roof face) and a door rect 0.05 x 0.08 in fill darkened 0.35.
- **City:** keep the current silhouette (twice the footprint); add the lit roof face on the tall part, two windows
  0.04 square in the low wing in fill darkened 0.35, keyline like settlements.
- **Robber:** an original hooded figure: a bell-shaped cloak polygon (base 0.34 wide, 0.42 tall) with a hood
  circle, fill `#3A3036`, a cream keyline 0.035 (6.0:1 on Pine, 9.4:1 fill vs Dune), a short lantern glint (circle
  r 0.03 in `#E8A93A`) at the hood. Drop shadow ellipse under it (`#000000` alpha 0.3). Position beside the chip
  as now.
- **Targets:** "lantern" highlight instead of white. Corner: ring r 0.13 in `#F3C54A`, 0.04 wide, over a dark halo
  ring 0.07 wide in `#231C17` alpha 0.45; fill alpha 0.25. Edge: dashed line (three dashes) in `#F3C54A` over the dark
  halo. Tile: ring r 0.42 around the chip. Alpha pulses 0.6 → 1.0 with a 1.2 s sine while targets exist
  (`queue_redraw` from `_process` only then). Hover: the piece preview in own seat colour at alpha 0.85 plus a solid
  `#F3C54A` ring.
- **Last change marker:** tiles that produced on the last roll get a 0.06 cream ring for 1.5 s; the piece placed by
  the last event gets a fading ring, so other players' moves are visible.

## 4. Icons, cards, dice

**Resource icons** (one drawing function per resource, in a shared `ResourceArt` helper that takes a centre and
a size, used by tiles, ports, cards and HUD; sizes 20, 28, 44 px):
Wood a log (rounded rect plus end circle with a ring), Sheep a fleece (cloud of four circles), Wheat a sheaf
(three stalks and chevrons, tied with a band), Clay two stacked bricks, Ore a faceted stone (pentagon with two
facet lines in lighter and darker slate). Icons are filled in the pattern colour with a 1.5 px `ink` outline, so
they work on parchment and on the terrain colour.

**Resource cards** (hand and pickers): 72 x 100 px, radius 8, `card_stock` fill, 1 px `border`, shadow 3 px
offset (0, 2) alpha 0.30. Top 60 % is a band in the terrain colour with the 44 px icon, the bottom shows the name
in Atkinson Bold 16 `ink`. The count of identical cards is a badge in the top right corner: circle r 13, `ink`
fill, `cream` Atkinson Bold 16. Selected card: lifted 8 px with a 2 px `focus` border. Stacks fan with 22 px
overlap when the hand exceeds 7 cards.

**Development cards:** same size and stock, band colour by kind of action, all with `cream` icons:

| Kind | Band | Icon (primitives) |
|---|---|---|
| Knight | `#4A3F63` dusk violet | kite shield with a vertical bar |
| Road building | `#5B4A36` umber | two road capsules in a V |
| Year of plenty | `#3F6B5A` deep sage | two resource coins and a plus |
| Monopoly | `#7A3E4A` wine | four short arrows pointing into a circle |
| Victory point | `#9C7424` brass (`ink` icon) | a five-point star on a pennant |

Card back (other players' hands, deck): `#5B3F2C` leather with a cream double border inset 5 px and a small compass
rose (four triangles). Bought-this-turn cards are dimmed (modulate alpha 0.55) with a "new" corner tag.

**Dice:** two 48 px squares, radius 9, `card_stock` fill, 1.5 px `ink` border, shadow 3 px. Pips r 4.5 in `ink`,
standard layouts on a 3x3 grid at 25 / 50 / 75 %. Rolling: 6 random faces over 450 ms with a ±8° wobble, then the
result; the total shows beside them in Bitter Bold 28. A 7 tints both die borders `danger` and shows the robber
glyph next to the total.

## 5. Godot theme (`client/godot/theme/main_theme.tres`)

Set it as `gui/theme/custom` in `project.godot`; `default_font` = AtkinsonHyperlegible-Regular, `default_font_size`
= 20. Colours below are the tokens from section 1. Use one `StyleBoxFlat` per entry, `anti_aliasing` on,
`corner_detail` 6.

| Type / state | bg | border (width) | radius | shadow (size, offset, alpha) | content margins (l t r b) |
|---|---|---|---|---|---|
| `Panel`, `PanelContainer` | parchment | border (2) | 10 | 8, (0, 4), 0.35 | 16 14 16 14 |
| `PopupPanel`, `AcceptDialog` panel | parchment | border (2) | 12 | 16, (0, 8), 0.45 | 20 18 20 18 |
| `TooltipPanel` | `#2E241C` | none | 6 | 4, (0, 2), 0.4 | 10 6 10 6 |
| `Button` normal | button | border (1) | 8 | 2, (0, 2), 0.30 | 16 8 16 8 |
| `Button` hover | `#EADDBE` | `#6E5233` (1) | 8 | 3, (0, 2), 0.30 | same |
| `Button` pressed | `#D3C29C` | `#6E5233` (1) | 8 | none, content shifted 1 px down | 16 9 16 7 |
| `Button` disabled | disabled_fill | `#C2B597` (1) | 8 | none | same |
| `Button` focus | transparent | focus `#8C5A0E` (2), `expand_margin` 3 | 10 | none | – |
| `LineEdit` normal / focus | card_stock | border (1) / `#8C5A0E` (2) | 6 | none | 10 6 10 6 |
| `ItemList`, `Tree` | card_stock | border (1) | 8 | none | 6 6 6 6 |
| `ProgressBar` background / fill | `#D9CDB5` / accent | none | 6 | none | – |
| `HSeparator` | line `#C9B48E`, 1 px | – | – | – | – |

Font colours: `Button` `font_color` ink, `font_hover_color` ink, `font_pressed_color` ink, `font_disabled_color`
disabled_text, `font_focus_color` ink; `Label` `font_color` ink; `LineEdit` `font_color` ink,
`font_placeholder_color` ink_muted, `caret_color` ink, `selection_color` `#1E6B6366`; `TooltipLabel` cream at 16.
`Button` `h_separation` 8, minimum height 40 (32 hard floor).

Type variations (set `theme_type_variation` on the node):
- `AccentButton` (base `Button`): normal accent, hover accent_hover, pressed accent_pressed, border none, font
  white `#FFFFFF` Atkinson Bold. For the one main action per screen: Roll, End turn, Start game, Join.
- `DangerButton`: normal danger, hover `#B8443A`, pressed `#86271F`, white text. Leave, Reject, Remove bot.
- `GhostButton`: transparent normal, hover `#FFFFFF1A` on table, cream text; for small toolbar actions on walnut.
- `TablePanel` (base `PanelContainer`): bg `#3A2C23`, border `#4E3B2E` (1), radius 10, cream text; the HUD rails
  that sit on the table around the board.
- `SeatPanel`: like Panel plus a 6 px left border in the seat colour (`border_width_left` 6), radius 10; current
  turn adds `focus` `#E8A93A` 2 px outline via a second `StyleBoxFlat` with `expand_margin` 2.
- `Toast` (base `PanelContainer`): bg `#2E241C` alpha 0.94, radius 10, cream text, shadow 10, (0, 4), 0.5; error
  toasts get a 4 px left border in danger.
- `TitleLabel` / `HeadingLabel` (base `Label`): Bitter Bold 40 / Bitter SemiBold 28, cream on table, ink on parchment
  (`HeadingLabelDark` for the cream one).
- `CountLabel`: Atkinson Bold 20, ink.

Screens sit on the walnut table: `main.tscn` gets a full-rect `ColorRect` in `table` (with a faint vignette later)
under every screen; forms (connect, lobby browser, lobby room) are centred parchment `PanelContainer`s 640–880 px
wide, never full-width.

Layout spacing scale: 4, 8, 12, 16, 24, 32 px. Containers use `separation` 12; panels pad 16.

## 6. Concrete changes to `board_painter.gd`

1. Replace the colour constants with the palette: `TERRAIN` (Pine, Meadow, Harvest, Terracotta, Slate), `DESERT`
   `#EADDB6`, `SEA` `#2A6672`, `COAST` → `SHOAL` `#3E8790`, add `SAND` `#D9C48F`, `OUTLINE` `#231C17`, `KEYLINE`
   `#F4EFE3`, `CHIP` `#FBF5E6`, `CHIP_TEXT` `#2E241C`, `HOT_NUMBER` `#B5281F`, `CHIP_RIM` `#7A5E3A`, `PIER`
   `#7B5634`, `PIER_TIE` `#5C3F26`, `TARGET` `#F3C54A`, `ROBBER` `#3A3036`; drop `TILE_EDGE` and `HIGHLIGHT`.
2. `SEAT_COLORS` → Crimson, Cobalt, Rose, Plum; add `static func seat_outline(seat)` and
   `seat_keyline(seat)` (Plum inverts) and use them in `_draw_road`, `_draw_settlement`, `_draw_city`.
3. `draw_sea`: wave marks on the fixed grid; then shoal (1.18) and sand (1.05) hexes.
4. `_draw_tile`: scale 0.955, darker same-hue outline 0.02, bevel polygon, `_draw_motif(tile)`; delete
   `_draw_resource_label` (the tile tooltip in `Board` takes over the name).
5. New `_draw_motif` dispatching to one small function per terrain (each under ~15 lines, using `_polygon`,
   `_circle`, a new `_line(from, to, width, color)` helper in hex units). Resource icon drawing moves to a shared
   `scripts/art/resource_art.gd` so the HUD reuses it via `draw_*` on its own controls.
6. `_draw_chip`: shadow disc, hairline inner ring, second rim for 6/8; font from Bitter Bold.
7. `_draw_port`: plank pier with ties, badge with coloured rim and mini icon instead of coloured fill and name text.
8. `_draw_road`: keyline layer, round caps, highlight line.
9. `_draw_settlement` / `_draw_city`: keyline (grow polygon outward from its centroid by 0.035 hex units), lit roof
   face, door and windows.
10. `draw_robber`: hooded figure with cream keyline, lantern glint and shadow ellipse.
11. Targets: `TARGET` colour over a dark halo, dashed edge targets, `pulse: float` parameter passed in by `Board`
    (which owns the time and only redraws per frame while targets exist).
12. Font: `_font` from `preload("res://assets/fonts/Bitter-Bold.ttf")` instead of the theme default, so board
    numerals stay slab when the UI font changes.
13. A shadow helper `_shadow_circle(center, radius)` (offset (0.015, 0.025), black alpha 0.28) shared by chips,
    port badges and the robber; pieces get no blurred shadow (cost), only the keyline.

Verification after the change: rerun `tools/board_screenshot.gd` at 1600x900 and 1280x720, compare
`board_setup.png` / `board_middle.png`, and view one copy in greyscale (ImageMagick
`-colorspace Gray`) and through a deuteranopia simulator to confirm the tiles still separate.
