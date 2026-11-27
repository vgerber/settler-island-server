class_name PieceArt
extends RefCounted
## Road, settlement and city as soft clay, in neutral light grey with baked AO so one mesh serves every seat:
## `ClayMaterials.piece(seat)` tints it (and sets the rim colour of the outline rule). Origin at the base
## centre, resting on y = 0. Pieces are small enough to sit on a tile corner or edge without covering the chip.
## The road lies along local x, `ROAD_LENGTH` long (0.16 to 0.84 of a hex side like the 2D painter); the board
## turns it with `Basis(Vector3.UP, atan2(-edge_direction.y, edge_direction.x))` for a 2D direction.
## Houses face the camera with the ridge along x; a city is a house with a tower on its +x side.

const ROAD_LENGTH := 0.68
const ROAD_RADIUS := 0.062
const BODY := Color(0.84, 0.84, 0.84)
const ROOF := Color(0.98, 0.98, 0.98)
const ROOF_SLOPE := 0.85
const ROOF_THICKNESS := 0.02

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


## A rolled sausage, a little flattened.
static func _build_road(result: ClayBuilder) -> void:
	var body := Basis.from_scale(Vector3(1.0, 0.85, 1.0)) * Basis(Vector3.BACK, -PI * 0.5)
	var transform := Transform3D(body, Vector3(0.0, ROAD_RADIUS * 0.85, 0.0))
	var half_length := ROAD_LENGTH * 0.5 - ROAD_RADIUS
	result.add_lathe(ClayBuilder.capsule_profile(ROAD_RADIUS, half_length), transform, BODY, 0.62, 16)


static func _build_settlement(result: ClayBuilder) -> void:
	_add_house(result, Vector3.ZERO, Vector3(0.115, 0.08, 0.1))


static func _build_city(result: ClayBuilder) -> void:
	_add_house(result, Vector3(-0.085, 0.0, 0.0), Vector3(0.125, 0.085, 0.105))
	_add_tower(result, Vector3(0.13, 0.0, 0.0))


## A blob house: a round box with a gable roof of two tilted slabs, a ridge roll and a filler under the ridge.
static func _add_house(result: ClayBuilder, centre: Vector3, half: Vector3) -> void:
	result.add_round_box(Transform3D(Basis.IDENTITY, centre + Vector3(0.0, half.y, 0.0)), half, 0.035, BODY, 0.5)
	var depth := half.z + 0.025
	var rise := depth * tan(ROOF_SLOPE)
	var eave := centre + Vector3(0.0, half.y * 2.0 - 0.01, 0.0)
	var slab_half := Vector3(half.x + 0.03, ROOF_THICKNESS * 0.5, depth / cos(ROOF_SLOPE) * 0.5 + 0.012)
	for side in [-1.0, 1.0]:
		var tilt := Basis(Vector3.RIGHT, side * ROOF_SLOPE)
		result.add_round_box(Transform3D(tilt, eave + Vector3(0.0, rise * 0.5, side * depth * 0.5)), slab_half, 0.008, ROOF, 0.82)
	var filler_half := Vector3(half.x, rise * 0.5, 0.03)
	result.add_round_box(Transform3D(Basis.IDENTITY, eave + Vector3(0.0, rise * 0.5 - 0.005, 0.0)), filler_half, 0.012, BODY, 0.8)
	var roll := Basis(Vector3.BACK, -PI * 0.5)
	var ridge := eave + Vector3(0.0, rise + 0.006, 0.0)
	result.add_lathe(ClayBuilder.capsule_profile(0.021, half.x + 0.012, 4), Transform3D(roll, ridge), ROOF, 0.9, 8)


static func _add_tower(result: ClayBuilder, centre: Vector3) -> void:
	var half := Vector3(0.07, 0.14, 0.07)
	result.add_round_box(Transform3D(Basis.IDENTITY, centre + Vector3(0.0, half.y, 0.0)), half, 0.03, BODY, 0.5)
	var cap := centre + Vector3(0.0, half.y * 2.0, 0.0)
	result.add_round_box(Transform3D(Basis.IDENTITY, cap + Vector3(0.0, 0.018, 0.0)), Vector3(0.085, 0.018, 0.085), 0.014, ROOF, 0.75)
	var dome := Transform3D(Basis.from_scale(Vector3(0.055, 0.065, 0.055)), cap + Vector3(0.0, 0.04, 0.0))
	result.add_sphere(dome, ROOF, 0.85, 12)
