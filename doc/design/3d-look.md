# 3D table: look directions

Input for milestone 3 (`doc/plans/godot-3d.md`). Three directions for the table and island, one recommendation.
All three stay original (genre conventions only: hexes, number chips, a robber, two dice), need no commercial
assets, and tie into `Palette` (`client/godot/scripts/palette.gd`) so the 2D HUD, cards and dialogs sit on the 3D
scene without a style break. Board layout comes from `board_geometry.gd` (2D x/y become table x/z; hex unit = 1.0
tile radius, corners and edges unchanged, so placement targets and picking colliders reuse the same points).

Shared by all directions: the table top is Walnut (`Palette.TABLE`) with a procedural grain shader; seats keep
`SEAT_COLORS` plus the dark/light outline rule (in 3D an inverted-hull outline or a rim-light term, see each
direction); hot numbers 6 and 8 stay `HOT_NUMBER`; budget is 60 fps at 1600x900 on integrated graphics.

## Direction A: painted low-poly diorama

**Mood:** a small island model on a dark table, faceted and hand-painted, readable at a glance, cheerful.

- **Tiles:** hex prism 0.18 high, bevelled top edge, flat-shaded, Sand (`#D9C48F`) base rim. Terrain colour from
  `Palette` terrain colours, pattern colours for props.
  - Clay: three stepped slabs (a clay pit) with 2-3 stacked brick blocks.
  - Wood: 5-7 cone-stack pines (two stacked cones, `#244A2D` body, `#4F8457` tip), placed by a fixed hash.
  - Sheep: gently domed top, grass tufts (small quads), 2-3 sheep (squashed spheres, dark head, `FLEECE`).
  - Wheat: ridged field (shader stripes), 12-16 stalk bundles (thin prisms).
  - Ore: 3-4 jagged rock prisms, `#DCE0E5` snow cap on the tallest.
  - Desert: two low flat dunes, otherwise bare.
- **Sea and coast:** one large plane in Deep water with a cheap scrolling-stripe shader (no refraction); Shoal as a
  slightly raised translucent hex ring per coastal tile; one sand rim as the beach.
- **Number chips:** 0.05 high cylinders in `CARD_STOCK`, `Label3D` number (Bitter Bold, MSDF), pips as tiny
  cylinders; 6 and 8 in `HOT_NUMBER`; tilted 20 degrees toward the default camera.
- **Ports:** wooden pier: plank strip from the two coast corners out over the water, two posts, a crate or sack
  per resource, ratio on a hanging sign (`Label3D`).
- **Robber:** faceted pawn (lathe profile via `SurfaceTool`, 8 sides), charcoal with a cream band; hops on move.
- **Seat pieces:** road = long bevelled box; settlement = gabled house prism; city = house plus tower with a
  stepped roof. Flat seat colour, inverted-hull outline in `OUTLINE` (cream for Charcoal).
- **Lighting and shadow:** one warm `DirectionalLight3D` at about 45 degrees with a single shadow map (orthogonal
  mode, no cascades needed for a table), warm flat ambient tinted `#3A2C23`, no SSAO, dark vignette background.
- **Camera:** perspective, FOV 40, 55 degrees pitch, board centred, orbit +-35 degrees yaw, zoom 0.7-1.4x, reset.
- **Palette tie-in:** nearly 1:1 (flat terrain colours, outlines, chip stock).
- **Cost:** procedural only: `PrimitiveMesh` plus `SurfaceTool` for pawn and roofs; about 1.5-2 weeks. Features:
  `MeshInstance3D`, `MultiMeshInstance3D` for trees, stalks and rocks, `StandardMaterial3D` with vertex colour or
  one tiny spatial shader, `Label3D`, one shadow-casting light. Performance: very light (a few hundred instances,
  about 60 draw calls); fine on Compatibility, one directional shadow is supported there.

## Direction B: wooden tabletop game pieces

**Mood:** a physical game in play: turned and carved wood, stained board, warm and tactile; closest to the 2D
"map table by lamplight" parchment-and-wood feel.

- **Tiles:** thick (0.3) chamfered hex tiles. The top is a painted surface: terrain colour plus the 2D motifs
  from `board_painter.gd` rendered once at startup into an `ImageTexture` per terrain (via `SubViewport`), with a
  noise normal map for slight grain and a darker bevel. No 3D props, so information is in the print and
  legibility is the best of the three.
- **Sea and coast:** the island sits in a carved wooden frame; the sea is a recessed tray in satin-lacquer Deep
  water (low roughness, slow normal-map scroll) with a Shoal rim; the beach is a raised sand inlay.
- **Number chips:** turned round discs in `CARD_STOCK`, number embossed, pips below, set in a shallow recess.
- **Ports:** inlaid dock tokens: a plank bridge across the sea edge with a round resource medallion.
- **Robber:** turned wooden pawn (lathe profile, 16 sides, dark stain) on a ring base.
- **Seat pieces:** road = rounded bar; settlement = cube with roof; city = two blocks, one taller. Satin seat
  colours, inverted-hull keyline in cream or dark.
- **Lighting and shadow:** warm lamp: one `SpotLight3D` above the table (about 70 degree cone), soft shadows
  with raised blur, dim ambient, light pool falling off to the Walnut edges.
- **Camera:** perspective, FOV 35, 60 degrees pitch, orbit +-45 degrees, zoom 0.6-1.3x, plus a low "from my seat"
  preset at 30 degrees.
- **Palette tie-in:** exact, plus lacquer shine; fits the HUD parchment and walnut best.
- **Cost:** geometry is simple (chamfered hexes, lathe profiles) but baked textures and normal maps add shader
  work; about 2-3 weeks. Features: `SpotLight3D`, `StandardMaterial3D` roughness and normal, `NoiseTexture2D`,
  `SubViewport` baking. Performance: medium; fine on Forward+ integrated GPUs; on Compatibility spot shadows
  work but cost more fill, so drop the soft blur there.

## Direction C: soft clay miniature

**Mood:** a stop-motion tabletop diorama in plasticine: rounded, squishy, slightly imperfect, friendly.

- **Tiles:** hex slabs with large rounded edges (smoothed `SurfaceTool` mesh or vertex-displaced), fingerprint
  noise in the normal map. Props are pinched blobs: clay = lumpy mound with pressed brick rectangles; wood =
  round-top trees on short trunks; sheep = three merged spheres; wheat = rolled strands; ore = rounded boulders;
  desert = smooth ripples.
- **Sea and coast:** soft blue clay sheet with wavy ridges (vertex displacement shader); sand as a thin rolled coil.
- **Number chips:** flat clay discs with pressed numbers (baked texture).
- **Ports:** rolled-plank pier with two blob posts and a small flag carrying the ratio.
- **Robber:** soft pawn with a bulbous head, dark clay.
- **Seat pieces:** road = rounded sausage; settlement = blob house with a rolled roof; city = blob house plus
  tower. Matte seat colour; the outline rule is met with a rim-light term (no hull).
- **Lighting and shadow:** soft top light with strong ambient fill, `SSAO` for contact softness, large soft
  shadows, light glow; optional depth of field via `CameraAttributesPractical`.
- **Camera:** perspective, FOV 38, 58 degrees pitch, orbit +-40 degrees, zoom 0.7-1.4x.
- **Palette tie-in:** hues kept, saturation lowered about 10% (matte clay); chip numbers must be re-checked for
  contrast because texture noise softens edges.
- **Cost:** highest: smooth bevelled hexes and blob props need custom meshes or displacement, plus normal maps;
  about 3-4 weeks. Features: SSAO, soft shadows, DoF, glow. Performance: heaviest. SSAO and glow are Forward+
  features (not Compatibility); on integrated graphics expect roughly 40-60 fps at 1600x900 unless SSAO is
  dropped, and the look degrades without it. (Estimates, not measured.)

## Comparison

| | A diorama | B wooden pieces | C clay |
|---|---|---|---|
| Legibility of terrain and targets | high (silhouettes) | highest (print) | medium |
| Fit with 2D HUD | good | best | fair |
| Procedural-only effort | 1.5-2 weeks | 2-3 weeks | 3-4 weeks |
| Compatibility / web renderer | fine | fine (no soft blur) | poor (SSAO) |
| Integrated GPU | light | medium | heavy |
| Animation friendliness (drop, dust, hop) | very good | good | very good |

## Recommendation

**Direction A (painted low-poly diorama), borrowing B's warm lamp feel, walnut table, and turned-wood chips and
pawn.** Reasons:

1. Cheapest to produce fully in code with no external assets: primitives, cones and `MultiMeshInstance3D`.
   Props make terrain readable by silhouette from the default angle, so the colour-blind separation already used
   in 2D (trees vs bricks, tufts vs stalks) survives.
2. Fast and renderer-neutral: one shadow-casting light and no SSAO, so 60 fps on integrated graphics in
   Compatibility is realistic and the web export stays open. Forward+ only adds optional polish.
3. Flat-shaded, hard-coloured pieces carry the dark/light outline rule (inverted hull) that the 2D style needs for
   the weak seat-vs-terrain pairs.
4. Procedural props are deterministic (hash from tile coordinates), so screenshots compare in tests.
5. B stays an upgrade path (a material swap on the same geometry); C would need new meshes.

## Decisions for the user

1. Direction: A diorama (recommended), B wooden pieces, or C clay?
2. Renderer: Compatibility (web export possible, fewer effects) or Forward+ (desktop only, SSAO and richer shadows)?
3. Tile props: full props (trees, sheep, rocks) or flat printed motifs only (cleaner, cheaper)?
4. Sea: calm animated shader (recommended) or static colour (cheapest)?
5. Assets: procedural only, or allow CC0 models later for pawn and dice (sources to be verified then)?

Not done: no proof-of-concept stills were rendered, and no CC0 sources are named because none were verified.
