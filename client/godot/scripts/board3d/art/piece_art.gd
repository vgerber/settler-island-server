class_name PieceArt
extends RefCounted
## Road, settlement and city as faceted clay, in neutral light grey with baked AO so one mesh serves every seat:
## `ClayMaterials.piece(seat)` tints it (and sets the rim colour of the outline rule). Origin at the base
## centre, resting on y = 0. Pieces are small enough to sit on a tile corner or edge without covering the chip.
## The road lies along local x, `ROAD_LENGTH` long (0.16 to 0.84 of a hex side like the 2D painter); the board
## turns it with `Basis(Vector3.UP, atan2(-edge_direction.y, edge_direction.x))` for a 2D direction.
## Houses face the camera (+z) with the ridge along x; a city is a hall with a tower on its +x side and a
## smaller house on its -x side, on a stone base plate.

const ROAD_LENGTH := 0.68
const ROAD_RADIUS := 0.062
const BODY := Color(0.96, 0.96, 0.96)
const ROOF := Color(0.46, 0.46, 0.46)
## The roof is this much higher than it is deep: a pitch of about 55 degrees, which reads from a camera at 55 to 58.
const ROOF_RISE := 0.95
const ROOF_OVERHANG := 0.035
## Grey levels of the neutral mesh; the seat tint multiplies them, so the walls carry the seat colour and the
## stone, trim and openings are darker or lighter shades of it.
const STONE := Color(0.62, 0.62, 0.62)
const TRIM := Color(0.8, 0.8, 0.8)
const OPENING := Color(0.22, 0.22, 0.22)
const WOOD := Color(0.4, 0.4, 0.4)

static var _cache: Dictionary = {}


static func road() -> ArrayMesh:
	return _mesh("road", _build_road)


static func settlement() -> ArrayMesh:
	return _mesh("settlement", _build_settlement)


static func city() -> ArrayMesh:
	return _mesh("city", _build_city)


static func _mesh(key: String, build: Callable) -> ArrayMesh:
	if not _cache.has(key):
		var result := ClayBuilder.new()
		build.call(result)
		_cache[key] = result.to_mesh()
	return _cache[key]


## A bed with chamfered ends, kerb stones along both edges and cross planks between them.
static func _build_road(result: ClayBuilder) -> void:
	var half_length := ROAD_LENGTH * 0.5
	var half_width := ROAD_RADIUS
	var chamfer := 0.05
	var outline := PackedVector2Array([
		Vector2(-half_length, -half_width + chamfer), Vector2(-half_length + chamfer, -half_width),
		Vector2(half_length - chamfer, -half_width), Vector2(half_length, -half_width + chamfer),
		Vector2(half_length, half_width - chamfer), Vector2(half_length - chamfer, half_width),
		Vector2(-half_length + chamfer, half_width), Vector2(-half_length, half_width - chamfer),
	])
	var bed_height := 0.04
	result.add_prism(Transform3D.IDENTITY, outline, bed_height, STONE, 0.6)
	for side in [-1.0, 1.0]:
		var kerb := Transform3D(Basis.IDENTITY, Vector3(0.0, bed_height + 0.012, side * (half_width - 0.012)))
		result.add_box(kerb, Vector3(half_length - chamfer - 0.01, 0.012, 0.012), BODY, 0.8)
	var planks := 8
	var span := (half_length - chamfer) * 2.0
	for index in planks:
		var along := -span * 0.5 + span * (index + 0.5) / planks
		var plank := Transform3D(Basis.IDENTITY, Vector3(along, bed_height + 0.008, 0.0))
		var shade := 1.0 if index % 2 == 0 else 0.86
		result.add_box(plank, Vector3(span / planks * 0.5 - 0.006, 0.008, half_width - 0.028), ClayPalette.shade(BODY, shade), 0.85)


static func _build_settlement(result: ClayBuilder) -> void:
	_add_house(result, Vector3.ZERO, Vector3(0.115, 0.065, 0.095), true)


static func _build_city(result: ClayBuilder) -> void:
	result.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.016, 0.0)), Vector3(0.285, 0.016, 0.14), STONE, 0.6)
	var base := Vector3(0.0, 0.032, 0.0)
	_add_house(result, base + Vector3(-0.185, 0.0, 0.0), Vector3(0.07, 0.05, 0.075), false)
	_add_house(result, base + Vector3(-0.025, 0.0, 0.0), Vector3(0.12, 0.09, 0.095), true)
	_add_tower(result, base + Vector3(0.175, 0.0, 0.0))


## Stone course, walls, a gable roof with overhang and ridge beam, and (when `detailed`) door, windows and a chimney.
static func _add_house(result: ClayBuilder, centre: Vector3, half: Vector3, detailed: bool) -> void:
	var stone_height := 0.018
	var stone_half := Vector3(half.x + 0.012, stone_height, half.z + 0.012)
	result.add_box(Transform3D(Basis.IDENTITY, centre + Vector3(0.0, stone_height, 0.0)), stone_half, STONE, 0.6)
	var wall_base := centre + Vector3(0.0, stone_height * 2.0, 0.0)
	result.add_box(Transform3D(Basis.IDENTITY, wall_base + Vector3(0.0, half.y, 0.0)), half, BODY, 0.55)
	var eave := wall_base + Vector3(0.0, half.y * 2.0, 0.0)
	var depth := half.z + ROOF_OVERHANG
	var length := half.x + ROOF_OVERHANG
	result.add_gable(Transform3D(Basis.IDENTITY, eave), length, depth, depth * ROOF_RISE, ROOF, 0.8)
	result.add_box(Transform3D(Basis.IDENTITY, eave + Vector3(0.0, depth * ROOF_RISE, 0.0)), Vector3(length + 0.004, 0.008, 0.012), TRIM, 0.9)
	_add_shingle_rows(result, eave, length, depth)
	if detailed:
		_add_openings(result, wall_base, half)
		_add_chimney(result, eave + Vector3(half.x * 0.55, 0.0, -half.z * 0.35))


## Dark rows along the camera-facing slope read as shingles.
static func _add_shingle_rows(result: ClayBuilder, eave: Vector3, length: float, depth: float) -> void:
	var rise := depth * ROOF_RISE
	var slope := Vector3(0.0, rise, -depth).normalized()
	var turn := Basis(Vector3.RIGHT, -atan2(rise, depth))
	var outward := Vector3(0.0, depth, rise).normalized()
	for row in [0.3, 0.6]:
		var point := eave + Vector3(0.0, rise * row, depth * (1.0 - row)) + outward * 0.003
		result.add_box(Transform3D(turn, point), Vector3(length - 0.006, 0.0025, 0.004), ClayPalette.shade(ROOF, 0.65), 1.0)
	var edge := eave + Vector3(0.0, 0.0, depth) + outward * 0.002
	result.add_box(Transform3D(turn, edge + slope * 0.01), Vector3(length, 0.004, 0.01), TRIM, 0.9)


static func _add_openings(result: ClayBuilder, wall_base: Vector3, half: Vector3) -> void:
	var front := half.z + 0.003
	var door_height := minf(half.y * 0.72, 0.058)
	result.add_box(Transform3D(Basis.IDENTITY, wall_base + Vector3(-half.x * 0.3, door_height * 0.5, front)), Vector3(0.022, door_height * 0.5, 0.004), WOOD, 0.9)
	var window_y := half.y * 1.15
	var window := Vector3(0.018, 0.016, 0.004)
	result.add_box(Transform3D(Basis.IDENTITY, wall_base + Vector3(half.x * 0.42, window_y, front)), window, OPENING, 1.0)
	result.add_box(Transform3D(Basis.IDENTITY, wall_base + Vector3(half.x * 0.42, window_y - 0.019, front + 0.003)), Vector3(0.022, 0.003, 0.005), TRIM, 1.0)
	var side := Transform3D(Basis(Vector3.UP, PI * 0.5), wall_base + Vector3(half.x + 0.003, window_y, 0.0))
	result.add_box(side, window, OPENING, 1.0)


static func _add_chimney(result: ClayBuilder, eave: Vector3) -> void:
	var height := 0.1
	result.add_box(Transform3D(Basis.IDENTITY, eave + Vector3(0.0, height * 0.5, 0.0)), Vector3(0.018, height * 0.5, 0.018), STONE, 0.7)
	result.add_box(Transform3D(Basis.IDENTITY, eave + Vector3(0.0, height + 0.006, 0.0)), Vector3(0.024, 0.006, 0.024), TRIM, 0.9)
	result.add_box(Transform3D(Basis.IDENTITY, eave + Vector3(0.0, height + 0.016, 0.0)), Vector3(0.011, 0.005, 0.011), OPENING, 1.0)


## A stone-banded tower: shaft, a wider crenellated gallery, a small spire, an arrow slit and a flag.
static func _add_tower(result: ClayBuilder, centre: Vector3) -> void:
	var half := Vector3(0.065, 0.13, 0.065)
	result.add_box(Transform3D(Basis.IDENTITY, centre + Vector3(0.0, half.y, 0.0)), half, BODY, 0.5)
	result.add_box(Transform3D(Basis.IDENTITY, centre + Vector3(0.0, 0.012, 0.0)), Vector3(0.075, 0.012, 0.075), STONE, 0.6)
	result.add_box(Transform3D(Basis.IDENTITY, centre + Vector3(0.0, half.y * 2.0 + 0.008, 0.0)), Vector3(0.082, 0.008, 0.082), TRIM, 0.8)
	result.add_box(Transform3D(Basis.IDENTITY, centre + Vector3(0.0, half.y * 0.95, half.z + 0.003)), Vector3(0.008, 0.026, 0.004), OPENING, 1.0)
	var gallery := centre + Vector3(0.0, half.y * 2.0 + 0.016, 0.0)
	for corner_x in [-1.0, 1.0]:
		for corner_z in [-1.0, 1.0]:
			var merlon := Transform3D(Basis.IDENTITY, gallery + Vector3(corner_x * 0.069, 0.014, corner_z * 0.069))
			result.add_box(merlon, Vector3(0.014, 0.014, 0.014), BODY, 0.8)
	result.add_pyramid(Transform3D(Basis.IDENTITY, gallery + Vector3(0.0, 0.0, 0.0)), 0.058, 0.058, 0.13, ROOF, 0.8)
	result.add_box(Transform3D(Basis.IDENTITY, gallery + Vector3(0.0, 0.15, 0.0)), Vector3(0.003, 0.02, 0.003), WOOD, 0.9)
	result.add_box(Transform3D(Basis.IDENTITY, gallery + Vector3(0.016, 0.16, 0.0)), Vector3(0.016, 0.01, 0.002), TRIM, 1.0)
