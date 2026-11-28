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
## Rings of the relief top as shares of the outline: the chip disc ends at the first (a hex scaled by it), the last is the rim.
const RELIEF_RINGS: Array[float] = [0.4, 0.62, 0.82, 1.0]
const RELIEF_COLUMNS := 24
const WHEAT_SOIL := Color("#9A6B2A")
const WHEAT_SOIL_SHARE := 0.6

## The relief starts above the flat slab top so the two never fight for the same pixels.
const RELIEF_LIFT := 0.004
const FACET_SHADES: Array[float] = [0.86, 1.0, 1.12]
const BEACH_SHARE := 0.4

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
	if terrain == SiResource.WHEAT:
		top = top.lerp(WHEAT_SOIL, WHEAT_SOIL_SHARE) # deeper straw so the golden crop separates from the ground
	var sand := ClayPalette.mute(Palette.SAND)
	var side := ClayPalette.shade(top.lerp(sand, SAND_SHARE), 0.88)
	var base := ClayPalette.shade(sand, 0.62)
	var result := ClayBuilder.new()
	result.add_slab(hex_outline, HEIGHT, BEVEL, top, side, base, 0.78, 1, COLUMNS)
	_add_relief_top(result, terrain, top, sand)
	return result


## The tile top outside the chip disc as a ring grid of facets, each one of three shades of the terrain colour.
## It lies a hair above the slab's own flat top, which stays visible as the clear disc under the chip.
static func _add_relief_top(result: ClayBuilder, terrain: String, top: Color, sand: Color) -> void:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var generator := ClayRandom.for_tile(0, 0, terrain.hash())
	var rings: Array[PackedVector3Array] = []
	for ring in RELIEF_RINGS.size():
		var ring_points := PackedVector3Array()
		for column in RELIEF_COLUMNS:
			var angle := TAU * column / RELIEF_COLUMNS
			var radius: float = RELIEF_RINGS[ring] * hex_outline(angle, BEVEL if ring == RELIEF_RINGS.size() - 1 else 0.0)
			var position := Vector2(cos(angle), sin(angle)) * radius
			ring_points.append(Vector3(position.x, HEIGHT + ground(terrain, position.x, position.y), position.y))
		rings.append(ring_points)
	for ring in rings.size() - 1:
		for column in RELIEF_COLUMNS:
			var next := (column + 1) % RELIEF_COLUMNS
			var inner_first: Vector3 = rings[ring][column]
			var inner_second: Vector3 = rings[ring][next]
			var outer_first: Vector3 = rings[ring + 1][column]
			var outer_second: Vector3 = rings[ring + 1][next]
			for corners in [[inner_first, outer_first, outer_second], [inner_first, outer_second, inner_second]]:
				points.append_array(corners)
				var centre: Vector3 = (corners[0] + corners[1] + corners[2]) / 3.0
				var color := _facet_color(terrain, top, centre, generator)
				colors.append(color.lerp(sand, BEACH_SHARE) if ring == rings.size() - 2 else color)
	result.add_facets(points, colors)


static func _facet_color(terrain: String, top: Color, centre: Vector3, generator: RandomNumberGenerator) -> Color:
	var shade := FACET_SHADES[generator.randi() % FACET_SHADES.size()]
	if terrain == SiResource.WHEAT:
		shade = FACET_SHADES[0] if int(floor(centre.x * 3.2)) % 2 == 0 else FACET_SHADES[2]
	if terrain == SiResource.ORE:
		return ClayPalette.shade(top.lerp(Color(0.45, 0.46, 0.5), 0.25 * generator.randf()), shade)
	return ClayPalette.shade(top, shade)


## Height of the relief above the slab top (never below zero) at (`x`, `z`) of a tile; props sit on it. It fades out
## at the chip disc and at the rim.
static func ground(terrain: String, x: float, z: float) -> float:
	var distance := Vector2(x, z).length()
	var envelope := smoothstep(RELIEF_RINGS[0] - 0.05, RELIEF_RINGS[1], distance)
	envelope *= 1.0 - smoothstep(0.7, 0.88, distance)
	return RELIEF_LIFT + envelope * _relief(terrain, x, z)


static func _wave(x: float, z: float) -> float:
	return sin(x * 5.3 + 1.7) * sin(z * 4.9 + 0.3) * 0.5 + sin((x + z) * 7.1 + 0.6) * 0.5


static func _relief(terrain: String, x: float, z: float) -> float:
	match terrain:
		SiResource.SHEEP:
			return 0.05 * (_wave(x, z) * 0.5 + 0.5)
		SiResource.WOOD:
			return 0.04 * (_wave(x * 1.6, z * 1.6) * 0.5 + 0.5)
		SiResource.WHEAT:
			return 0.012 * (sin(x * 10.0) * 0.5 + 0.5)
		SiResource.CLAY:
			return 0.03 * roundf((_wave(x, z) * 0.5 + 0.5) * 2.0)
		SiResource.ORE:
			return 0.07 * absf(_wave(x * 1.3, z * 1.3))
		_:
			return 0.04 * (sin(x * 4.5 + z * 1.8) * 0.5 + 0.5)


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
