class_name HexSlabArt
extends RefCounted
## The chamfered, flat-shaded hex slab of one terrain with baked vertex AO. Units: hex radius 1 (corner distance),
## pointy top like `BoardGeometry`, 2D x/y become 3D x/z. The mesh sits on y = 0 and its top is `HEIGHT` high;
## props, chips and pieces of a tile rest on y = `HEIGHT` (the tile origin is the tile centre on the table).

const DESERT := "Desert"
const HEIGHT := 0.16
const BEVEL := 0.07
## Slab apothem: the true hex apothem (sqrt 3 / 2) less a seam, so neighbours show a clay groove.
const APOTHEM := 0.8517
## Share of the corner's half angle (30 degrees) the outline reaches; 1 is a sharp hex.
const CORNER_REACH := 1.0
## How much of the lower wall turns to beach sand.
## Twelve columns: a corner and an edge midpoint every 30 degrees, so the edges are straight.
const COLUMNS := 12
const SAND_SHARE := 0.55

static var _cache: Dictionary = {}


static func terrains() -> Array[String]:
	var result: Array[String] = []
	result.append_array(SiResource.VALUES)
	result.append(DESERT)
	return result


static func slab(terrain: String) -> ArrayMesh:
	if not _cache.has(terrain):
		_cache[terrain] = builder(terrain).to_mesh()
	return _cache[terrain]


static func builder(terrain: String) -> ClayBuilder:
	var top := ClayPalette.mute(terrain_color(terrain))
	var sand := ClayPalette.mute(Palette.SAND)
	var side := ClayPalette.shade(top.lerp(sand, SAND_SHARE), 0.88)
	var base := ClayPalette.shade(sand, 0.62)
	var result := ClayBuilder.new()
	result.add_slab(hex_outline, HEIGHT, BEVEL, top, side, base, 0.78, 1, COLUMNS)
	return result


static func terrain_color(terrain: String) -> Color:
	if terrain == DESERT:
		return Palette.DESERT
	return Palette.resource_color(terrain)


## Distance from the tile centre to the hex outline at `angle`, pulled in by `inset`.
## Same shape as a hex (edge midpoints at 0, 60, ... degrees).
static func hex_outline(angle: float, inset: float) -> float:
	var offset := fposmod(angle + PI / 6.0, PI / 3.0) - PI / 6.0
	# The ray angle is bent toward the edge normal; at CORNER_REACH 1 the corner is sharp and the edges are straight.
	var bent := CORNER_REACH * (PI / 6.0) * sin(offset * 3.0)
	return (APOTHEM - inset) / cos(bent)
