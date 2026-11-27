class_name PieceArt
extends RefCounted
## Road, settlement and city as faceted clay, in neutral light grey with baked AO so one mesh serves every seat:
## `ClayMaterials.piece(seat)` tints it (and sets the rim colour of the outline rule). Origin at the base
## centre, resting on y = 0. Pieces are small enough to sit on a tile corner or edge without covering the chip.
## The road lies along local x, `ROAD_LENGTH` long (0.16 to 0.84 of a hex side like the 2D painter); the board
## turns it with `Basis(Vector3.UP, atan2(-edge_direction.y, edge_direction.x))` for a 2D direction.
## Houses face the camera with the ridge along x; a city is a house with a tower on its +x side.

const ROAD_LENGTH := 0.68
const ROAD_RADIUS := 0.062
const BODY := Color(0.96, 0.96, 0.96)
const ROOF := Color(0.6, 0.6, 0.6)
## The roof is this much higher than it is deep: a pitch of about 55 degrees, which reads from a camera at 55 to 58.
const ROOF_RISE := 1.4
const ROOF_OVERHANG := 0.03

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


## A faceted bar: a six-sided capsule, a little flattened.
static func _build_road(result: ClayBuilder) -> void:
	var body := Basis.from_scale(Vector3(1.0, 0.85, 1.0)) * Basis(Vector3.BACK, -PI * 0.5)
	var transform := Transform3D(body, Vector3(0.0, ROAD_RADIUS * 0.85, 0.0))
	var half_length := ROAD_LENGTH * 0.5 - ROAD_RADIUS
	result.add_lathe(ClayBuilder.capsule_profile(ROAD_RADIUS, half_length, 1), transform, BODY, 0.62, 6)


static func _build_settlement(result: ClayBuilder) -> void:
	_add_house(result, Vector3.ZERO, Vector3(0.115, 0.08, 0.1))


static func _build_city(result: ClayBuilder) -> void:
	_add_house(result, Vector3(-0.085, 0.0, 0.0), Vector3(0.125, 0.085, 0.105))
	_add_tower(result, Vector3(0.13, 0.0, 0.0))


## A box with a steep gable roof (the slope faces the camera and is lighter than the wall).
static func _add_house(result: ClayBuilder, centre: Vector3, half: Vector3) -> void:
	result.add_box(Transform3D(Basis.IDENTITY, centre + Vector3(0.0, half.y, 0.0)), half, BODY, 0.5)
	var depth := half.z + ROOF_OVERHANG
	var eave := centre + Vector3(0.0, half.y * 2.0, 0.0)
	result.add_gable(Transform3D(Basis.IDENTITY, eave), half.x + ROOF_OVERHANG, depth, depth * ROOF_RISE, ROOF, 0.85)


static func _add_tower(result: ClayBuilder, centre: Vector3) -> void:
	var half := Vector3(0.07, 0.14, 0.07)
	result.add_box(Transform3D(Basis.IDENTITY, centre + Vector3(0.0, half.y, 0.0)), half, BODY, 0.5)
	var cap := centre + Vector3(0.0, half.y * 2.0, 0.0)
	result.add_gable(Transform3D(Basis.IDENTITY, cap), half.x + 0.02, half.z + 0.02, 0.1, ROOF, 0.85)
