class_name TerrainPropsArt
extends RefCounted
## Clay props of one tile, placed by a hash of its cube coordinates (`q`, `r`), dense enough to read at the default
## zoom: pine and broadleaf forests, sheep with a fence, ploughed wheat rows with a windmill, hay cart and stook, snowy peaks
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
const WINDMILL_SIZE := 1.2
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

const SOIL := Color("#6E4B30")
const POPPY_RED := Color("#C8412F")
const RIPENING_GREEN := Color("#A8A940")
const RIPE_AMBER := Color("#C98A2E")
const CROP_REACH := 0.76
const ROW_PITCH := 0.046
const TRACK_HALF := 0.035
const MIN_ROW := 0.07


static func _add_wheat(result: ClayBuilder, generator: RandomNumberGenerator, taken: Array[Vector3]) -> void:
	_add_windmill(result, generator, taken)
	_add_hay_cart(result, generator, taken)
	var stook := _claim(SiResource.WHEAT, generator, taken, 0.07)
	if stook.is_finite():
		_add_stook(result, generator, stook)
	for index in 4:
		var poppy := _claim(SiResource.WHEAT, generator, taken, 0.02)
		if poppy.is_finite():
			_add_poppy(result, generator, poppy)
	_add_field(result, generator, taken)


## Two fields of long straight rows split by a track; the track runs at a seeded angle and the second field's
## rows cross the first one's.
static func _add_field(result: ClayBuilder, generator: RandomNumberGenerator, taken: Array[Vector3]) -> void:
	var track_angle := generator.randf_range(0.0, PI)
	var track_normal := Vector2(-sin(track_angle), cos(track_angle))
	var track_offset := generator.randf_range(-0.12, 0.12)
	var turn := generator.randf_range(0.5, 1.0) * (1.0 if generator.randf() < 0.5 else -1.0)
	var tones: Array[Color] = [ClayPalette.STRAW, RIPENING_GREEN]
	var angles: Array[float] = [track_angle, track_angle + turn]
	for side in 2:
		var sign := 1.0 if side == 0 else -1.0
		var tone := ClayPalette.mute(tones[side])
		_add_rows(result, angles[side], tone, taken, track_normal * sign, track_offset * sign)
	_add_track(result, track_angle, track_offset, taken)


## Rows at `angle`, kept to the half plane `normal . p >= offset + TRACK_HALF`.
static func _add_rows(result: ClayBuilder, angle: float, tone: Color, taken: Array[Vector3], normal: Vector2, offset: float) -> void:
	var along := Vector2(cos(angle), sin(angle))
	var across := Vector2(-along.y, along.x)
	var count := int(CROP_REACH / ROW_PITCH)
	for row in range(-count, count + 1):
		var shift := row * ROW_PITCH
		var shade := 0.95 + 0.1 * float(posmod(row, 2))
		for span in _free_spans(along, across, shift, normal, offset + TRACK_HALF, taken):
			_add_row(result, along, across * shift, span, ClayPalette.shade(tone, shade))


## The stretches of a line (`across * shift + along * t`) that lie inside the crop disc and the half plane and
## outside the chip and every claimed prop.
static func _free_spans(along: Vector2, across: Vector2, shift: float, normal: Vector2, limit: float, taken: Array[Vector3]) -> Array[Vector2]:
	var reach := sqrt(maxf(CROP_REACH * CROP_REACH - shift * shift, 0.0))
	var low := -reach
	var high := reach
	var origin := across * shift
	var slope := normal.dot(along)
	var base := normal.dot(origin) - limit
	if absf(slope) < 0.0001:
		if base < 0.0:
			return []
	elif slope > 0.0:
		low = maxf(low, -base / slope)
	else:
		high = minf(high, -base / slope)
	var spans: Array[Vector2] = [Vector2(low, high)]
	spans = _cut_circle(spans, along, origin, Vector2.ZERO, RING_MIN + 0.01)
	for other in taken:
		spans = _cut_circle(spans, along, origin, Vector2(other.x, other.z), other.y + 0.03)
	return spans


static func _cut_circle(spans: Array[Vector2], along: Vector2, origin: Vector2, centre: Vector2, radius: float) -> Array[Vector2]:
	var offset := centre - origin
	var middle := offset.dot(along)
	var gap := radius * radius - (offset.length_squared() - middle * middle)
	if gap <= 0.0:
		return spans
	var half := sqrt(gap)
	var result: Array[Vector2] = []
	for span in spans:
		if span.x < middle - half:
			result.append(Vector2(span.x, minf(span.y, middle - half)))
		if span.y > middle + half:
			result.append(Vector2(maxf(span.x, middle + half), span.y))
	return result


## A soil strip with a low ridge of crop on it and a lighter line of ears along the top.
static func _add_row(result: ClayBuilder, along: Vector2, origin: Vector2, span: Vector2, tone: Color) -> void:
	if span.y - span.x < MIN_ROW:
		return
	var middle := origin + along * (span.x + span.y) * 0.5
	var half_length := (span.y - span.x) * 0.5
	var ground := _ground_at(SiResource.WHEAT, middle.x, middle.y)
	var heading := Basis(Vector3.UP, -atan2(along.y, along.x))
	var ears := ClayPalette.shade(ClayPalette.mute(ClayPalette.EAR_GOLD), tone.v + 0.1)
	result.add_box(Transform3D(heading, ground + Vector3(0.0, 0.004, 0.0)), Vector3(half_length, 0.004, ROW_PITCH * 0.5), ClayPalette.mute(SOIL), 0.5)
	result.add_box(Transform3D(heading, ground + Vector3(0.0, 0.017, 0.0)), Vector3(half_length, 0.013, 0.011), tone, 0.5)
	result.add_box(Transform3D(heading, ground + Vector3(0.0, 0.034, 0.0)), Vector3(half_length, 0.004, 0.007), ears, 0.8)


## A pale packed-earth track between the fields.
static func _add_track(result: ClayBuilder, angle: float, offset: float, taken: Array[Vector3]) -> void:
	var along := Vector2(cos(angle), sin(angle))
	var across := Vector2(-along.y, along.x)
	var track := ClayPalette.mute(ClayPalette.STRAW).lerp(ClayPalette.mute(SOIL), 0.5)
	for span in _free_spans(along, across, offset, Vector2.ZERO, -1.0, taken):
		if span.y - span.x < MIN_ROW:
			continue
		var middle := across * offset + along * (span.x + span.y) * 0.5
		var ground := _ground_at(SiResource.WHEAT, middle.x, middle.y)
		var heading := Basis(Vector3.UP, -atan2(along.y, along.x))
		result.add_box(Transform3D(heading, ground + Vector3(0.0, 0.004, 0.0)), Vector3((span.y - span.x) * 0.5, 0.004, TRACK_HALF), track, 0.6)


## A tied sheaf standing in the field: a fat straw cone with a band and a tuft of ears on top.
static func _add_stook(result: ClayBuilder, generator: RandomNumberGenerator, spot: Vector3) -> void:
	var straw := ClayPalette.mute(ClayPalette.STRAW)
	var band := ClayPalette.mute(ClayPalette.WOOD_BROWN)
	var scale := _front_scale(spot, 0.22)
	var transform := _placed(spot, Vector3.ONE * scale * generator.randf_range(0.9, 1.1), generator.randf() * TAU)
	result.add_lathe(PackedVector2Array([Vector2(0.065, 0.0), Vector2(0.06, 0.05), Vector2(0.032, 0.14), Vector2(0.018, 0.17)]), transform, ClayPalette.shade(straw, 0.95), 0.5, 6)
	result.add_lathe(PackedVector2Array([Vector2(0.04, 0.1), Vector2(0.04, 0.12)]), transform, band, 0.9, 6)
	result.add_lathe(PackedVector2Array([Vector2(0.02, 0.16), Vector2(0.05, 0.19), Vector2(0.02, 0.25), Vector2(0.0, 0.27)]), transform, ClayPalette.mute(ClayPalette.EAR_GOLD), 0.8, 6)


static func _add_poppy(result: ClayBuilder, generator: RandomNumberGenerator, spot: Vector3) -> void:
	var stem := ClayPalette.mute(ClayPalette.BUSH_GREEN)
	result.add_box(_placed(spot + Vector3(0.0, 0.035, 0.0), Vector3.ONE), Vector3(0.005, 0.035, 0.005), stem, 0.8)
	result.add_sphere(_placed(spot + Vector3(0.0, 0.08, 0.0), Vector3(0.024, 0.016, 0.024), generator.randf() * TAU), _varied(ClayPalette.mute(POPPY_RED), generator), 0.9, 5)


## A cart of hay: a plank bed on two wheels, a mound of straw and a pair of shafts.
static func _add_hay_cart(result: ClayBuilder, generator: RandomNumberGenerator, taken: Array[Vector3]) -> void:
	var spot := _claim(SiResource.WHEAT, generator, taken, 0.14)
	if not spot.is_finite():
		return
	var wood := ClayPalette.mute(ClayPalette.WOOD_BROWN)
	var straw := ClayPalette.mute(ClayPalette.STRAW)
	var scale := _front_scale(spot, 0.2)
	var base := _placed(spot, Vector3.ONE * scale, generator.randf() * TAU)
	result.add_box(base * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.07, 0.0)), Vector3(0.12, 0.012, 0.07), wood, 0.6)
	for side in [-1.0, 1.0]:
		result.add_box(base * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.1, side * 0.068)), Vector3(0.12, 0.02, 0.008), ClayPalette.shade(wood, 1.12), 0.7)
		var wheel := base * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.055, side * 0.08))
		result.add_lathe(PackedVector2Array([Vector2(0.0, -0.008), Vector2(0.055, -0.008), Vector2(0.055, 0.008), Vector2(0.0, 0.008)]), wheel, ClayPalette.shade(wood, 0.8), 0.6, 6)
		result.add_box(base * Transform3D(Basis(Vector3.BACK, 0.12 * side), Vector3(-0.2, 0.07, side * 0.03)), Vector3(0.09, 0.008, 0.008), wood, 0.8)
	result.add_sphere(base * Transform3D(Basis.from_scale(Vector3(0.115, 0.07, 0.065)), Vector3(0.0, 0.13, 0.0)), straw, 0.55, 7)
	result.add_sphere(base * Transform3D(Basis.from_scale(Vector3(0.07, 0.05, 0.05)), Vector3(0.03, 0.17, 0.0)), ClayPalette.shade(straw, 1.1), 0.8, 6)


## A plastered tower on a stone foot with a red cap, a door and four lattice sails turned toward the camera.
static func _add_windmill(result: ClayBuilder, generator: RandomNumberGenerator, taken: Array[Vector3]) -> void:
	var spot := _claim(SiResource.WHEAT, generator, taken, 0.15)
	if not spot.is_finite():
		return
	var wall := ClayPalette.mute(ClayPalette.PLASTER)
	var cap := ClayPalette.mute(ClayPalette.BARN_RED)
	var wood := ClayPalette.mute(ClayPalette.WOOD_BROWN)
	var stone := ClayPalette.mute(ClayPalette.STONE_GREY)
	var base := Transform3D(Basis.from_scale(Vector3.ONE * WINDMILL_SIZE * _front_scale(spot, 0.6)), spot)
	result.add_lathe(PackedVector2Array([Vector2(0.125, 0.0), Vector2(0.115, 0.07)]), base, stone, 0.5, 7)
	result.add_lathe(PackedVector2Array([Vector2(0.105, 0.07), Vector2(0.07, 0.32)]), base, wall, 0.55, 7)
	result.add_lathe(PackedVector2Array([Vector2(0.085, 0.32), Vector2(0.088, 0.335), Vector2(0.0, 0.46)]), base, cap, 0.8, 7)
	result.add_box(base * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.07, 0.1)), Vector3(0.025, 0.04, 0.012), wood, 0.7)
	result.add_box(base * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.22, 0.082)), Vector3(0.016, 0.02, 0.01), wood, 0.7)
	var hub := Vector3(0.0, 0.32, 0.09)
	result.add_box(base * Transform3D(Basis.IDENTITY, hub), Vector3(0.018, 0.018, 0.022), wood, 1.0)
	var sail_turn := generator.randf() * PI * 0.5
	for arm in 4:
		var turn := Basis(Vector3.BACK, sail_turn + arm * PI * 0.5)
		var frame := base * Transform3D(turn, hub + turn * Vector3(0.0, 0.12, 0.03))
		result.add_box(frame, Vector3(0.006, 0.12, 0.004), wood, 0.9)
		var cloth := base * Transform3D(turn, hub + turn * Vector3(0.016, 0.145, 0.034))
		result.add_box(cloth, Vector3(0.016, 0.08, 0.003), ClayPalette.mute(ClayPalette.PLASTER), 0.9)


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
