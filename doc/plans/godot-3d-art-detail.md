# Godot client: 3D art detail pass

User feedback 2026-11-27 on the milestone 3 table: "the assets look shit and lack detail". Decision: keep the
procedural clay kit (no external models) and rework the meshes in code. Low poly and flat-shaded stays the rule;
detail comes from more parts, shaped tile tops and facet colour variation, not from smooth meshes or textures.

## What is wrong now (default view, `.build/shots-final`)
- Tiles are flat single-colour slabs; the terrain reads only by colour.
- Props are few and tiny (a handful of trees, two sheep, scattered pebbles) and vanish at the default zoom.
- Settlements and cities are boxes; roads are plain sticks; the robber is a blob; piers are a plank strip.
- Water hexes are one flat teal; no coast, foam or beach.

## Rules
- Flat shading and vertex colours via `ClayBuilder` (new primitives go into `clay_builder.gd` as small appended
  functions; both agents may append, the lead merges both). Deterministic: hash of tile coordinates.
- Triangle budgets (raised by the lead in `clay_kit_test.gd`): slab 600, props 2500, tile 3400, chip 400,
  piece 700, robber 600, die 300, port 900, table 1500, water hex 200. Compatibility renderer stays at 60 fps or
  more at 1600x900 on this machine (measure with the existing fps probe).
- Picking, target points, chip and piece positions and the camera fit do not change.
- Review your own work by eye: render `tools/clay_gallery.gd` and `tools/game_screenshots.gd` (windowed runs use
  `--position 200,200`) and look at the stills before you report; attach the paths.

## Part A: terrain and sea (`hex_slab_art.gd`, `terrain_props_art.gd`, `water_art.gd`, `clay_palette.gd`, `table_light.gd`)
- Tile tops: a subdivided hex top with low relief per terrain (rolling hills for sheep, furrowed strips for wheat,
  lumpy ground for wood, stepped pit for clay, rocky base for ore, dune ripples for desert); each facet picks one of
  three shades of the terrain colour; a flat clear disc in the centre for the chip; a sand or earth rim edge.
- Props fill the tile around the chip and read at the default zoom:
  - Wood: 10-14 trees in two or three kinds (stacked-cone pine, round broadleaf, a stump or log), bushes.
  - Sheep: 4-5 sheep with body, head and legs, a fence run, bushes or flowers.
  - Wheat: rows of stalk bundles in two shades, a haystack, a small windmill or barn.
  - Ore: two or three faceted peaks with snow caps, scree rocks, a mine entrance with a timber frame.
  - Clay: terraced pit, brick stacks, a kiln with chimney.
  - Desert: dunes, a dead tree or cactus, bleached rocks.
- Sea: water hexes with facet shade variation and a gentle height offset; the ring next to land gets a lighter
  shoal colour and foam; land tiles show a beach where they meet water.
- Lighting: warm key light with shadows on pieces and props, cool fill; check both renderers.

## Part B: pieces and furniture (`piece_art.gd`, `robber_art.gd`, `port_art.gd`, `chip_art.gd`, `die_art.gd`, `table_art.gd`, `award_art.gd`)
- Settlement: house on a stone base, walls in the seat colour, roof in a darker shade of it with overhang, door,
  windows, chimney.
- City: larger hall plus a tower with crenellations or spire and a second building, on a base plate.
- Road: a seat-coloured road bed with chamfered ends and plank or stone detail; seat colour stays dominant.
- Robber: hooded, cloaked figure on a round base; reads dark against every terrain.
- Pier: separate planks, posts, crates or sacks of the port's resource, a rope, a small moored boat; flag kept.
- Chip: bevelled rim, numbers and pips kept legible (6 and 8 red).
- Table and seat stands: plank grain by facet shade, rim moulding. Dice: rounded corners, pips kept.
- Seat colours: every seat stays recognisable on every terrain (the gallery swatch row).

## Acceptance
- `tools/check.sh` green; `clay_kit_test.gd` passes with the new budgets; the mouse-only UI test passes on 3D.
- Gallery and in-game stills at 1600x900 in Compatibility and Forward+, reviewed by the lead and the user.
- At least 60 fps at 1600x900 in Compatibility at the default view.
