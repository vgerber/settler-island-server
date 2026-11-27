class_name TerrainPropsArt
extends RefCounted
## Clay props of one tile, placed by a hash of its cube coordinates (`q`, `r`), dense enough to read at the default
## zoom: pine and broadleaf forests, sheep with a fence, wheat rows with a haystack and a windmill, snowy peaks
## with a mine, a terraced clay pit with a kiln, dunes with a cactus. The mesh origin is the tile centre on the
## slab top (y = `HexSlabArt.HEIGHT` on the table); every prop stands on `HexSlabArt.ground`. Props stay between
## radius `RING_MIN` and `RING_MAX` (the number chip owns the middle, the settlements the corners), tall ones
## stay behind the chip (`TALL_FRONT_LIMIT`), and the robber's spot beside the chip is kept free.

const RING_MIN := 0.44
const RING_MAX := 0.7
## Tall props nearer the camera than this shrink (`_front_scale`) so they never hide the chip.
const TALL_FRONT_LIMIT := 0.15
## A prop's centre plus its `room` never reaches past this (the slab edge is at 0.85).
const EDGE_REACH := 0.79
const PLACEMENT_TRIES := 40
## Tall props nearer the camera shrink so their tops stay clear of the chip (about the camera's tilt).
const FRONT_SLOPE := 1.6
const FRONT_MIN_SCALE := 0.5
const WINDMILL_SIZE := 1.3
## Where the robber stands (`BoardArt.ROBBER_OFFSET`) and how much room it needs.
const ROBBER_SPOT := Vector2(-0.5, 0.05)
const ROBBER_ROOM := 0.2

static var _cache: Dictionary = {}


static func props(terrain: String, q: int, r: int) -> ArrayMesh:
	var key := "%s:%d:%d" % [terrain, q, r]
	if not _cache.has(key):
		_cache[key] = builder(terrain, q, r).to_mesh()
	return _cache[key]


static func builder(terrain: String, q: int, r: int) -> ClayBuilder:
	var result := ClayBuilder.new()
	var generator := ClayRandom.for_tile(q, r, terrain.hash())
	var taken: Array[Vector3] = [Vector3(ROBBER_SPOT.x, ROBBER_ROOM, ROBBER_SPOT.y)]
	match terrain:
		SiResource.CLAY:
			_add_clay(result, generator, taken)
		SiResource.WOOD:
			_add_wood(result, generator, taken)
		SiResource.SHEEP:
			_add_sheep(result, generator, taken)
		SiResource.WHEAT:
			_add_wheat(result, generator, taken)
		SiResource.ORE:
			_add_ore(result, generator, taken)
		_:
			_add_desert(result, generator, taken)
	return result


## A free spot for a prop of `room` radius on the ring, standing on the ground, or `Vector3.INF` when the tile is
## full. `taken` holds (x, room, z) of every claimed spot.
static func _claim(terrain: String, generator: RandomNumberGenerator, taken: Array[Vector3], room: float) -> Vector3:
	for attempt in PLACEMENT_TRIES:
		var angle := generator.randf() * TAU
		var radius := generator.randf_range(RING_MIN, minf(RING_MAX, EDGE_REACH - room))
		var spot := Vector2(cos(angle), sin(angle)) * radius
		if _is_free(spot, room, taken):
			taken.append(Vector3(spot.x, room, spot.y))
			return Vector3(spot.x, HexSlabArt.ground(terrain, spot.x, spot.y) - HexSlabArt.RELIEF_LIFT, spot.y)
	return Vector3.INF


## Scale that keeps a prop of `height` from standing over the chip when it is nearer the camera than the chip.
static func _front_scale(spot: Vector3, height: float) -> float:
	if spot.z <= TALL_FRONT_LIMIT:
		return 1.0
	return clampf((spot.z - 0.3) * FRONT_SLOPE / height, FRONT_MIN_SCALE, 1.0)


static func _is_free(spot: Vector2, room: float, taken: Array[Vector3]) -> bool:
	for other in taken:
		if Vector2(other.x, other.z).distance_to(spot) < other.y + room:
			return false
	return true


static func _ground_at(terrain: String, x: float, z: float) -> Vector3:
	return Vector3(x, HexSlabArt.ground(terrain, x, z) - HexSlabArt.RELIEF_LIFT, z)


## A part placed at `position` with a yaw and a scale of its own.
static func _placed(position: Vector3, scale: Vector3, yaw := 0.0, tilt := Vector3.ZERO) -> Transform3D:
	var basis := Basis.from_euler(Vector3(tilt.x, yaw, tilt.z)) * Basis.from_scale(scale)
	return Transform3D(basis, position)


static func _varied(color: Color, generator: RandomNumberGenerator) -> Color:
	return ClayPalette.shade(color, generator.randf_range(0.88, 1.12))


# --- Wood ---------------------------------------------------------------------------------------------------


static func _add_wood(result: ClayBuilder, generator: RandomNumberGenerator, taken: Array[Vector3]) -> void:
	var count := generator.randi_range(13, 16)
	for index in count:
		var spot := _claim(SiResource.WOOD, generator, taken, 0.1)
		if not spot.is_finite():
			continue
		match index % 4:
			0, 1:
				_add_pine(result, generator, spot)
			2:
				_add_broadleaf(result, generator, spot)
			_:
				_add_stump(result, generator, spot)
	for index in 3:
		var bush := _claim(SiResource.WOOD, generator, taken, 0.07)
		if bush.is_finite():
			_add_bush(result, generator, bush)
	var log_spot := _claim(SiResource.WOOD, generator, taken, 0.1)
	if log_spot.is_finite():
		_add_log(result, generator, log_spot)


## Three stacked cones on a short trunk.
static func _add_pine(result: ClayBuilder, generator: RandomNumberGenerator, spot: Vector3) -> void:
	var crown := _varied(ClayPalette.mute(Palette.resource_pattern_color(SiResource.WOOD)), generator)
	var crown_light := _varied(ClayPalette.mute(Palette.PINE_LIGHT), generator)
	var trunk := ClayPalette.mute(ClayPalette.WOOD_BROWN)
	var size := generator.randf_range(0.85, 1.2) * _front_scale(spot, 0.55)
	var transform := _placed(spot, Vector3.ONE * size, generator.randf() * TAU)
	result.add_lathe(PackedVector2Array([Vector2(0.035, 0.0), Vector2(0.03, 0.1)]), transform, trunk, 0.5, 5)
	result.add_lathe(PackedVector2Array([Vector2(0.15, 0.06), Vector2(0.0, 0.28)]), transform, crown, 0.55, 6)
	result.add_lathe(PackedVector2Array([Vector2(0.115, 0.2), Vector2(0.0, 0.4)]), transform, crown_light, 0.7, 6)
	result.add_lathe(PackedVector2Array([Vector2(0.075, 0.34), Vector2(0.0, 0.52)]), transform, crown, 0.85, 6)


## A trunk with two clumps of leaves.
static func _add_broadleaf(result: ClayBuilder, generator: RandomNumberGenerator, spot: Vector3) -> void:
	var leaf := _varied(ClayPalette.mute(ClayPalette.LEAF_BRIGHT), generator)
	var trunk := ClayPalette.mute(ClayPalette.WOOD_BROWN)
	var size := generator.randf_range(0.9, 1.15) * _front_scale(spot, 0.5)
	var transform := _placed(spot, Vector3.ONE * size, generator.randf() * TAU)
	result.add_lathe(PackedVector2Array([Vector2(0.04, 0.0), Vector2(0.028, 0.2)]), transform, trunk, 0.5, 5)
	result.add_sphere(transform * Transform3D(Basis.from_scale(Vector3(0.15, 0.13, 0.15)), Vector3(0.0, 0.26, 0.0)), leaf, 0.6, 6)
	result.add_sphere(transform * Transform3D(Basis.from_scale(Vector3(0.1, 0.09, 0.1)), Vector3(0.05, 0.4, 0.02)), ClayPalette.shade(leaf, 1.12), 0.8, 6)


static func _add_stump(result: ClayBuilder, generator: RandomNumberGenerator, spot: Vector3) -> void:
	var trunk := ClayPalette.mute(ClayPalette.WOOD_BROWN)
	var cut := ClayPalette.mute(Palette.LOG_CUT)
	var transform := _placed(spot, Vector3.ONE * generator.randf_range(0.9, 1.2))
	result.add_lathe(PackedVector2Array([Vector2(0.06, 0.0), Vector2(0.05, 0.08)]), transform, trunk, 0.5, 6)
	result.add_lathe(PackedVector2Array([Vector2(0.05, 0.08), Vector2(0.0, 0.085)]), transform, cut, 1.0, 6)


static func _add_log(result: ClayBuilder, generator: RandomNumberGenerator, spot: Vector3) -> void:
	var trunk := ClayPalette.mute(ClayPalette.WOOD_BROWN)
	var heading := generator.randf() * PI
	var lying := Transform3D(Basis(Vector3.UP, heading) * Basis(Vector3.FORWARD, PI * 0.5), spot + Vector3(0.0, 0.035, 0.0))
	result.add_lathe(PackedVector2Array([Vector2(0.035, -0.09), Vector2(0.035, 0.09)]), lying, trunk, 0.6, 5)
	result.add_lathe(PackedVector2Array([Vector2(0.035, 0.09), Vector2(0.0, 0.092)]), lying, ClayPalette.mute(Palette.LOG_CUT), 1.0, 5)


static func _add_bush(result: ClayBuilder, generator: RandomNumberGenerator, spot: Vector3) -> void:
	var size := generator.randf_range(0.05, 0.075)
	var color := _varied(ClayPalette.mute(ClayPalette.BUSH_GREEN), generator)
	result.add_sphere(_placed(spot + Vector3(0.0, size * 0.4, 0.0), Vector3(size, size * 0.75, size), generator.randf() * TAU), color, 0.6, 5)


# --- Sheep --------------------------------------------------------------------------------------------------


static func _add_sheep(result: ClayBuilder, generator: RandomNumberGenerator, taken: Array[Vector3]) -> void:
	_add_fence(result, generator, taken)
	for index in generator.randi_range(4, 5):
		var spot := _claim(SiResource.SHEEP, generator, taken, 0.17)
		if spot.is_finite():
			_add_sheep_at(result, spot, generator.randf() * TAU, generator.randf_range(0.9, 1.1))
	for index in 4:
		var spot := _claim(SiResource.SHEEP, generator, taken, 0.06)
		if spot.is_finite():
			_add_bush(result, generator, spot)
	for index in 7:
		var spot := _claim(SiResource.SHEEP, generator, taken, 0.04)
		if spot.is_finite():
			_add_flower(result, generator, spot)


## A fence run of posts and two rails along a chord at the back of the tile.
static func _add_fence(result: ClayBuilder, generator: RandomNumberGenerator, taken: Array[Vector3]) -> void:
	var wood := ClayPalette.mute(Palette.LOG_CUT)
	var centre_angle := generator.randf_range(PI * 1.1, PI * 1.9)
	var heading := centre_angle + PI * 0.5
	var along := Vector2(cos(heading), sin(heading))
	var middle := Vector2(cos(centre_angle), sin(centre_angle)) * 0.62
	for index in 5:
		var spot := middle + along * (index - 2.0) * 0.14
		taken.append(Vector3(spot.x, 0.07, spot.y))
		var base := _ground_at(SiResource.SHEEP, spot.x, spot.y)
		result.add_box(Transform3D(Basis(Vector3.UP, -heading), base + Vector3(0.0, 0.05, 0.0)), Vector3(0.016, 0.055, 0.016), wood, 0.6)
	for height in [0.04, 0.075]:
		var rail := _ground_at(SiResource.SHEEP, middle.x, middle.y) + Vector3(0.0, height, 0.0)
		result.add_box(Transform3D(Basis(Vector3.UP, -heading), rail), Vector3(0.3, 0.011, 0.011), ClayPalette.shade(wood, 0.9), 0.8)


## A fleece body, a dark head with ears, four dark legs and a tail tuft.
static func _add_sheep_at(result: ClayBuilder, position: Vector3, yaw: float, size: float) -> void:
	var fleece := ClayPalette.mute(Palette.FLEECE)
	var face := ClayPalette.mute(ClayPalette.SHEEP_FACE)
	var heading := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3.ONE * size), position)
	result.add_sphere(heading * Transform3D(Basis.from_scale(Vector3(0.14, 0.1, 0.1)), Vector3(0.0, 0.1, 0.0)), fleece, 0.6, 6)
	result.add_sphere(heading * Transform3D(Basis.from_scale(Vector3(0.08, 0.07, 0.08)), Vector3(-0.04, 0.16, 0.0)), ClayPalette.shade(fleece, 1.03), 0.9, 5)
	result.add_sphere(heading * Transform3D(Basis.from_scale(Vector3(0.05, 0.045, 0.04)), Vector3(0.15, 0.13, 0.0)), face, 0.8, 5)
	result.add_box(heading * Transform3D(Basis(Vector3.UP, 0.0), Vector3(0.14, 0.17, 0.035)), Vector3(0.012, 0.025, 0.012), face, 0.9)
	result.add_box(heading * Transform3D(Basis(Vector3.UP, 0.0), Vector3(0.14, 0.17, -0.035)), Vector3(0.012, 0.025, 0.012), face, 0.9)
	for leg in [Vector2(0.07, 0.035), Vector2(0.07, -0.035), Vector2(-0.07, 0.035), Vector2(-0.07, -0.035)]:
		result.add_box(heading * Transform3D(Basis.IDENTITY, Vector3(leg.x, 0.03, leg.y)), Vector3(0.014, 0.03, 0.014), face, 0.5)


static func _add_flower(result: ClayBuilder, generator: RandomNumberGenerator, spot: Vector3) -> void:
	var colors: Array[Color] = [ClayPalette.FLOWER_WHITE, ClayPalette.FLOWER_PINK, ClayPalette.FLOWER_YELLOW]
	var color := ClayPalette.mute(colors[generator.randi() % colors.size()])
	result.add_sphere(_placed(spot + Vector3(0.0, 0.03, 0.0), Vector3(0.022, 0.018, 0.022)), color, 0.9, 5)


# --- Wheat --------------------------------------------------------------------------------------------------


static func _add_wheat(result: ClayBuilder, generator: RandomNumberGenerator, taken: Array[Vector3]) -> void:
	_add_windmill(result, generator, taken)
	_add_haystack(result, generator, taken)
	var straw := ClayPalette.mute(ClayPalette.STRAW)
	var straw_dark := ClayPalette.mute(ClayPalette.STRAW_DARK)
	var ear := ClayPalette.mute(ClayPalette.EAR_GOLD)
	var rows := 6
	for row in rows:
		var z := -0.62 + row * 0.25 * 0.84
		var color := straw if row % 2 == 0 else straw_dark
		for step in 12:
			var x := -0.75 + step * 0.136 + (0.05 if row % 2 == 0 else 0.0)
			var spot := Vector2(x, z)
			if spot.length() < RING_MIN or spot.length() > RING_MAX + 0.05 or not _is_free(spot, 0.04, taken):
				continue
			_add_sheaf(result, generator, _ground_at(SiResource.WHEAT, x, z), color, ear)


## A bundle of stalks: a tapered sheaf with a golden ear on top.
static func _add_sheaf(result: ClayBuilder, generator: RandomNumberGenerator, spot: Vector3, color: Color, ear: Color) -> void:
	var lean := Vector3(generator.randf_range(-0.12, 0.12), 0.0, generator.randf_range(-0.12, 0.12))
	var transform := _placed(spot, Vector3.ONE * generator.randf_range(0.9, 1.15), generator.randf() * TAU, lean)
	result.add_lathe(PackedVector2Array([Vector2(0.05, 0.0), Vector2(0.04, 0.12), Vector2(0.012, 0.19)]), transform, color, 0.5, 5)
	result.add_lathe(PackedVector2Array([Vector2(0.03, 0.15), Vector2(0.028, 0.2), Vector2(0.0, 0.27)]), transform, ear, 0.8, 5)


static func _add_haystack(result: ClayBuilder, generator: RandomNumberGenerator, taken: Array[Vector3]) -> void:
	var spot := _claim(SiResource.WHEAT, generator, taken, 0.15)
	if not spot.is_finite():
		return
	var hay := ClayPalette.mute(ClayPalette.STRAW)
	var profile := PackedVector2Array([Vector2(0.15, 0.0), Vector2(0.15, 0.06), Vector2(0.115, 0.14), Vector2(0.05, 0.2), Vector2(0.0, 0.22)])
	result.add_lathe(profile, _placed(spot, Vector3.ONE), hay, 0.55, 7)


## A white tower with a cap and four sails turned toward the camera.
static func _add_windmill(result: ClayBuilder, generator: RandomNumberGenerator, taken: Array[Vector3]) -> void:
	var spot := _claim(SiResource.WHEAT, generator, taken, 0.14)
	if not spot.is_finite():
		return
	var wall := ClayPalette.mute(ClayPalette.PLASTER)
	var cap := ClayPalette.mute(ClayPalette.BARN_RED)
	var wood := ClayPalette.mute(ClayPalette.WOOD_BROWN)
	var base := Transform3D(Basis.from_scale(Vector3.ONE * WINDMILL_SIZE * _front_scale(spot, 0.55)), spot)
	result.add_lathe(PackedVector2Array([Vector2(0.11, 0.0), Vector2(0.075, 0.3)]), base, wall, 0.55, 6)
	result.add_lathe(PackedVector2Array([Vector2(0.09, 0.3), Vector2(0.0, 0.42)]), base, cap, 0.8, 6)
	var hub := Vector3(0.0, 0.3, 0.08)
	result.add_box(base * Transform3D(Basis.IDENTITY, hub), Vector3(0.02, 0.02, 0.02), wood, 1.0)
	var sail_turn := generator.randf() * PI * 0.5
	for arm in 4:
		var turn := Basis(Vector3.BACK, sail_turn + arm * PI * 0.5)
		var sail := base * Transform3D(turn, hub + turn * Vector3(0.0, 0.11, 0.025))
		result.add_box(sail, Vector3(0.025, 0.1, 0.006), ClayPalette.mute(ClayPalette.PLASTER), 0.9)


# --- Ore ----------------------------------------------------------------------------------------------------


static func _add_ore(result: ClayBuilder, generator: RandomNumberGenerator, taken: Array[Vector3]) -> void:
	for index in generator.randi_range(2, 3):
		var spot := _claim(SiResource.ORE, generator, taken, 0.2)
		if spot.is_finite():
			_add_peak(result, generator, spot, index == 0)
	var mine := _claim(SiResource.ORE, generator, taken, 0.12)
	if mine.is_finite():
		_add_mine(result, mine)
	for index in 9:
		var spot := _claim(SiResource.ORE, generator, taken, 0.05)
		if spot.is_finite():
			_add_scree(result, generator, spot)


## A faceted cone peak with a snow cap on the upper half; the first peak is the tallest.
static func _add_peak(result: ClayBuilder, generator: RandomNumberGenerator, spot: Vector3, tallest: bool) -> void:
	var rock := _varied(ClayPalette.mute(Palette.resource_pattern_color(SiResource.ORE)), generator)
	var rock_light := ClayPalette.mute(Palette.RESOURCE_COLORS[SiResource.ORE]).lightened(0.1)
	var snow := ClayPalette.mute(Palette.PEAK_SNOW)
	var height := generator.randf_range(0.5, 0.58) if tallest else generator.randf_range(0.34, 0.44)
	height *= _front_scale(spot, height)
	var radius := height * generator.randf_range(0.36, 0.42)
	var yaw := generator.randf() * TAU
	var transform := _placed(spot, Vector3.ONE, yaw)
	var body := PackedVector2Array([Vector2(radius, 0.0), Vector2(radius * 0.78, height * 0.3), Vector2(radius * 0.5, height * 0.62)])
	result.add_lathe(body, transform, rock, 0.5, 5)
	result.add_lathe(PackedVector2Array([Vector2(radius * 0.5, height * 0.62), Vector2(radius * 0.3, height * 0.85), Vector2(0.0, height)]), transform, rock_light, 0.8, 5)
	var cap := PackedVector2Array([Vector2(radius * 0.4, height * 0.7), Vector2(radius * 0.26, height * 0.88), Vector2(0.0, height + 0.004)])
	result.add_lathe(cap, _placed(spot, Vector3.ONE * 1.04, yaw), snow, 0.9, 5)


## A timber-framed mine mouth facing the camera.
static func _add_mine(result: ClayBuilder, spot: Vector3) -> void:
	var wood := ClayPalette.mute(ClayPalette.WOOD_BROWN)
	var dark := ClayPalette.mute(ClayPalette.DARK_CLAY)
	var rock := ClayPalette.mute(ClayPalette.STONE_GREY)
	result.add_box(Transform3D(Basis.IDENTITY, spot + Vector3(0.0, 0.055, -0.03)), Vector3(0.1, 0.055, 0.07), rock, 0.5)
	result.add_box(Transform3D(Basis.IDENTITY, spot + Vector3(0.0, 0.045, 0.045)), Vector3(0.055, 0.045, 0.012), dark, 1.0)
	for side in [-1.0, 1.0]:
		result.add_box(Transform3D(Basis.IDENTITY, spot + Vector3(side * 0.06, 0.05, 0.055)), Vector3(0.012, 0.05, 0.012), wood, 0.7)
	result.add_box(Transform3D(Basis.IDENTITY, spot + Vector3(0.0, 0.105, 0.055)), Vector3(0.075, 0.012, 0.014), wood, 0.8)


static func _add_scree(result: ClayBuilder, generator: RandomNumberGenerator, spot: Vector3) -> void:
	var colors: Array[Color] = [ClayPalette.STONE_GREY, ClayPalette.STONE_DARK, Palette.resource_pattern_color(SiResource.ORE)]
	var color := _varied(ClayPalette.mute(colors[generator.randi() % colors.size()]), generator)
	var size := generator.randf_range(0.035, 0.065)
	var tilt := Vector3(generator.randf_range(-0.4, 0.4), 0.0, generator.randf_range(-0.4, 0.4))
	result.add_sphere(_placed(spot + Vector3(0.0, size * 0.35, 0.0), Vector3(size, size * 0.7, size * 0.9), generator.randf() * TAU, tilt), color, 0.6, 5)


# --- Clay ---------------------------------------------------------------------------------------------------


static func _add_clay(result: ClayBuilder, generator: RandomNumberGenerator, taken: Array[Vector3]) -> void:
	_add_kiln(result, generator, taken)
	for index in 2:
		var spot := _claim(SiResource.CLAY, generator, taken, 0.17)
		if spot.is_finite():
			_add_terraced_mound(result, generator, spot)
	for index in 4:
		var spot := _claim(SiResource.CLAY, generator, taken, 0.1)
		if spot.is_finite():
			_add_brick_stack(result, spot, generator)
	for index in 6:
		var spot := _claim(SiResource.CLAY, generator, taken, 0.05)
		if spot.is_finite():
			_add_clump(result, generator, spot)


## Three steps, like the wall of a clay pit.
static func _add_terraced_mound(result: ClayBuilder, generator: RandomNumberGenerator, spot: Vector3) -> void:
	var clay := _varied(ClayPalette.mute(Palette.resource_pattern_color(SiResource.CLAY)), generator)
	var profile := PackedVector2Array([
		Vector2(0.17, 0.0), Vector2(0.17, 0.045), Vector2(0.125, 0.05), Vector2(0.125, 0.1), Vector2(0.08, 0.105), Vector2(0.08, 0.15), Vector2(0.0, 0.155)
	])
	result.add_lathe(profile, _placed(spot, Vector3.ONE, generator.randf() * TAU), clay, 0.55, 7)


## Three bricks, two on the bottom and one across the top.
static func _add_brick_stack(result: ClayBuilder, spot: Vector3, generator: RandomNumberGenerator) -> void:
	var brick := ClayPalette.shade(ClayPalette.mute(ClayPalette.BRICK_LIGHT), generator.randf_range(0.9, 1.1))
	var yaw := generator.randf() * TAU
	var half := Vector3(0.095, 0.045, 0.05)
	var turn := Basis(Vector3.UP, yaw)
	for side in [-1.0, 1.0]:
		result.add_box(Transform3D(turn, spot + turn * Vector3(0.0, half.y, side * 0.055)), half, brick, 0.6)
	var top := Basis(Vector3.UP, yaw + PI * 0.5)
	result.add_box(Transform3D(top, spot + Vector3(0.0, half.y * 3.0, 0.0)), half, ClayPalette.shade(brick, 1.08), 0.8)


## A domed kiln with a dark door and a chimney.
static func _add_kiln(result: ClayBuilder, generator: RandomNumberGenerator, taken: Array[Vector3]) -> void:
	var spot := _claim(SiResource.CLAY, generator, taken, 0.15)
	if not spot.is_finite():
		return
	var shell := ClayPalette.mute(ClayPalette.KILN_RED)
	var dark := ClayPalette.mute(ClayPalette.DARK_CLAY)
	var dome := PackedVector2Array([Vector2(0.13, 0.0), Vector2(0.13, 0.06), Vector2(0.105, 0.12), Vector2(0.06, 0.17), Vector2(0.0, 0.185)])
	var base := Transform3D(Basis.from_scale(Vector3.ONE * _front_scale(spot, 0.32) * 1.2), spot)
	result.add_lathe(dome, base, shell, 0.55, 7)
	result.add_box(base * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.04, 0.115)), Vector3(0.04, 0.04, 0.02), dark, 1.0)
	result.add_lathe(PackedVector2Array([Vector2(0.032, 0.14), Vector2(0.028, 0.3)]), base * Transform3D(Basis.IDENTITY, Vector3(-0.04, 0.0, -0.05)), ClayPalette.shade(shell, 0.85), 0.7, 5)


static func _add_clump(result: ClayBuilder, generator: RandomNumberGenerator, spot: Vector3) -> void:
	var clay := _varied(ClayPalette.mute(Palette.resource_pattern_color(SiResource.CLAY)), generator)
	var size := generator.randf_range(0.035, 0.06)
	result.add_sphere(_placed(spot + Vector3(0.0, size * 0.3, 0.0), Vector3(size, size * 0.6, size), generator.randf() * TAU), clay, 0.6, 5)


# --- Desert -------------------------------------------------------------------------------------------------


static func _add_desert(result: ClayBuilder, generator: RandomNumberGenerator, taken: Array[Vector3]) -> void:
	var cactus := _claim(HexSlabArt.DESERT, generator, taken, 0.1)
	if cactus.is_finite():
		_add_cactus(result, generator, cactus)
	var dead := _claim(HexSlabArt.DESERT, generator, taken, 0.12)
	if dead.is_finite():
		_add_dead_tree(result, generator, dead)
	var ripple := ClayPalette.mute(Palette.DESERT_PATTERN)
	for index in 4:
		var spot := _claim(HexSlabArt.DESERT, generator, taken, 0.14)
		if spot.is_finite():
			var yaw := generator.randf() * PI
			var length := generator.randf_range(0.14, 0.2)
			result.add_sphere(_placed(spot + Vector3(0.0, 0.01, 0.0), Vector3(length, 0.028, length * 0.6), yaw), _varied(ripple, generator), 0.75, 6)
	for index in 6:
		var spot := _claim(HexSlabArt.DESERT, generator, taken, 0.05)
		if spot.is_finite():
			_add_bleached_rock(result, generator, spot)


## A trunk with two upturned arms.
static func _add_cactus(result: ClayBuilder, generator: RandomNumberGenerator, spot: Vector3) -> void:
	var green := ClayPalette.mute(ClayPalette.CACTUS_GREEN)
	var transform := _placed(spot, Vector3.ONE * generator.randf_range(0.9, 1.15), generator.randf() * TAU)
	result.add_lathe(PackedVector2Array([Vector2(0.045, 0.0), Vector2(0.045, 0.2), Vector2(0.0, 0.25)]), transform, green, 0.55, 6)
	for side in [-1.0, 1.0]:
		var arm := transform * Transform3D(Basis.IDENTITY, Vector3(side * 0.07, 0.1 + 0.03 * side, 0.0))
		result.add_lathe(PackedVector2Array([Vector2(0.026, 0.0), Vector2(0.026, 0.1), Vector2(0.0, 0.125)]), arm, ClayPalette.shade(green, 1.08), 0.7, 5)
		result.add_box(transform * Transform3D(Basis.IDENTITY, Vector3(side * 0.035, 0.1 + 0.03 * side, 0.0)), Vector3(0.035, 0.016, 0.016), green, 0.8)


## A bare trunk with a few stiff branches.
static func _add_dead_tree(result: ClayBuilder, generator: RandomNumberGenerator, spot: Vector3) -> void:
	var wood := ClayPalette.mute(Palette.DESERT_ROCK).darkened(0.35)
	var transform := _placed(spot, Vector3.ONE, generator.randf() * TAU)
	result.add_lathe(PackedVector2Array([Vector2(0.034, 0.0), Vector2(0.018, 0.24)]), transform, wood, 0.55, 5)
	for branch in 3:
		var turn := Basis(Vector3.UP, branch * 2.1) * Basis(Vector3.FORWARD, 0.9)
		var origin := Vector3(0.0, 0.14 + branch * 0.045, 0.0)
		result.add_box(transform * Transform3D(turn, origin + turn * Vector3(0.0, 0.07, 0.0)), Vector3(0.011, 0.07, 0.011), wood, 0.8)


static func _add_bleached_rock(result: ClayBuilder, generator: RandomNumberGenerator, spot: Vector3) -> void:
	var rock := _varied(ClayPalette.mute(ClayPalette.BONE), generator)
	var size := generator.randf_range(0.035, 0.065)
	result.add_sphere(_placed(spot + Vector3(0.0, size * 0.35, 0.0), Vector3(size, size * 0.7, size * 0.85), generator.randf() * TAU), rock, 0.6, 5)
