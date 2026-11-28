# Table UI art style (3D low poly)

One style for every fixture of the 3D table UI (`doc/plans/godot-table-ui.md`). It extends the clay kit the board
already uses; a fixture that would look out of place next to the settlement, the dice tray or a pier is wrong.

## Construction
- Built in code with `ClayBuilder` primitives only (`add_box`, `add_bevelled_box`, `add_prism`, `add_pyramid`,
  `add_lathe`, `add_slab`, `add_gable`, `add_facets`, `add_sphere`): flat shaded, vertex colours, baked AO through
  `ao_floor`. No textures, no imported models, no smooth normals.
- Low poly: few large facets, chunky proportions, a small bevel (0.01 to 0.02) on every visible wooden or clay edge,
  slightly toy-like scale (thicker than real). Detail comes from parts and shade steps, not from triangle count.
- Shade steps: a main colour, one lighter (`ClayPalette.shade(color, 1.1)`) for top facets and trim, one darker (0.7
  to 0.85) for grooves, undersides and inlays. Never more than three tones per part.
- Units: hex circumradius 1.0; the table top is at y 0, sea hexes at `WaterArt.HEIGHT`. Origin at the base centre,
  resting on y = 0, front facing +z (toward the camera).
- Materials: `ClayMaterials.terrain()` for neutral fixtures, `ClayMaterials.piece(seat)` for seat-tinted parts (model
  them light grey so the tint carries), `ClayMaterials.stock()` for chips and cards.

## Materials and colours
| Material | Colour | Use |
|---|---|---|
| Walnut | `#5A3E2A` main, `#7B5634` top, `#3F2B1A` grooves | racks, trays, plates, sign, bell base, ledger |
| Light wood | `#B58A5A` | inlays, card holder floors, mat border |
| Brass | `#C9A46A`, light `#E8C77C`, dark `#8E6A28` | bell, name label rims, award sockets, hinges |
| Clay | terrain and seat colours via `ClayPalette` | pieces, tokens, card glyphs |
| Card stock | `#FBF5E6` (`CHIP_FACE`), rim `#7A5E3A` | card faces, chips |
| Felt | `#2F5D52` muted teal | trade mat surface only |
| Dev plum | `#5B4378` | dev card backs and borders |
| Lantern | `#FFF1C9` | hover rim, "you can act" glow; nothing else |
| Points gold | `#F3C54A` | points chips, award plaques only |
| Danger | `#A3332A` | missing cost outline, decline token |

## Shared shapes
- **Card:** bevelled slab 0.36 x 0.5 x 0.014, corner chamfer 0.03. Face: a card-stock border 0.025 wide around a
  coloured field; the glyph is raised geometry (0.006) in the centre. Back: walnut with a brass diamond. Dev cards:
  plum border and one cut corner. No text on cards.
- **Chip:** the tile-chip hexagon, small (radius 0.09), card stock with a rim; a `Label3D` digit floats 0.002 above
  it. Gold rim for points, brown for counts, plum for dev counts.
- **Plate:** walnut bevelled board with a brass rim line, a seat-colour stripe at the left, `Label3D` text on it.
- **Token:** a clay disc 0.12 across, 0.03 thick, with a raised symbol (tick, cross, three dots, scale).
- Every fixture stands on its own walnut base or on the table, never floating, with a `BlobShadow`.

## Text
`Label3D` only on plates, chips and the sign; Bitter Bold for digits and titles, Atkinson Hyperlegible for labels;
cream `#F3EADB` on walnut, ink `#231C17` on card stock. No slashed zero. Text faces the camera at the default pitch
(tilted with its plate), not billboarded, so it sits in the world.

## Budgets (triangles)
Card 160, chip 60, token 120, plate 150, supply rack (empty) 900, bank rack 900, bell 600, sign 500, award board 600,
trade mat 500, ledger 400, settings board 900.
