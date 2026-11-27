class_name TerrainPropsArt
extends RefCounted
## Clay props of one tile, placed by a hash of its cube coordinates (`q`, `r`): mounds with bricks,
## cone trees, sheep of a few facets, wheat strands, faceted boulders, desert ripples. The mesh origin
## is the tile centre on the slab top (y = `HexSlabArt.HEIGHT` on the table). Props stay between radius 0.5
## and 0.8 of the tile (the number chip owns the middle, the settlements the corners); the desert is low
## enough to leave the robber standing on it.

const RING_MIN := 0.56
const RING_MAX := 0.62
## Slots toward the camera (+z) sit on the outer ring so tall props do not hide the chip.
const FRONT_SINE := 0.45

static var _cache: Dictionary = {}


static func props(terrain: String, q: int, r: int) -> ArrayMesh:
	var key := "%s:%d:%d" % [terrain, q, r]
	if not _cache.has(key):
		_cache[key] = builder(terrain, q, r).to_mesh()
	return _cache[key]


static func builder(terrain: String, q: int, r: int) -> ClayBuilder:
	var result := ClayBuilder.new()
	var generator := ClayRandom.for_tile(q, r, terrain.hash())
	match terrain:
		SiResource.CLAY:
			_add_clay(result, generator)
		SiResource.WOOD:
			_add_wood(result, generator)
		SiResource.SHEEP:
			_add_sheep(result, generator)
		SiResource.WHEAT:
			_add_wheat(result, generator)
		SiResource.ORE:
			_add_ore(result, generator)
		_:
			_add_desert(result, generator)
	return result


## Evenly spread slot positions on the prop ring, each nudged, starting at a random angle.
static func _slots(generator: RandomNumberGenerator, count: int) -> Array[Vector3]:
	var slots: Array[Vector3] = []
	var start := generator.randf() * TAU
	for index in count:
		var angle := start + TAU * index / count + generator.randf_range(-0.2, 0.2)
		var radius := generator.randf_range(RING_MIN, RING_MAX)
		if sin(angle) > FRONT_SINE:
			radius = RING_MAX + 0.04
		slots.append(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	return slots


static func _placed(position: Vector3, scale: Vector3, yaw := 0.0, tilt := Vector3.ZERO) -> Transform3D:
	var basis := Basis.from_euler(Vector3(tilt.x, yaw, tilt.z)) * Basis.from_scale(scale)
	return Transform3D(basis, position)


static func _add_clay(result: ClayBuilder, generator: RandomNumberGenerator) -> void:
	var mound := ClayPalette.mute(Palette.resource_pattern_color(SiResource.CLAY))
	var brick := ClayPalette.mute(ClayPalette.BRICK_LIGHT)
	var slots := _slots(generator, 4)
	for index in 2:
		var size := generator.randf_range(0.15, 0.19)
		var lump := slots[index] + Vector3(0.0, -0.03, 0.0)
		result.add_sphere(_placed(lump, Vector3(size, size * 0.8, size), generator.randf() * TAU), mound, 0.62, 6)
		var small := slots[index] - slots[index].normalized() * size * 0.55
		result.add_sphere(_placed(small + Vector3(0.0, 0.01, 0.0), Vector3(size, size, size) * 0.5), mound, 0.7, 5)
	_add_brick_stack(result, slots[2], brick, generator)
	_add_brick_stack(result, slots[3], ClayPalette.shade(brick, 0.92), generator)


## Two bricks and one on top.
static func _add_brick_stack(result: ClayBuilder, centre: Vector3, color: Color, generator: RandomNumberGenerator) -> void:
	var yaw := generator.randf() * TAU
	var half := Vector3(0.085, 0.04, 0.05)
	for side in [-1.0, 1.0]:
		var offset := Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, side * 0.065)
		result.add_box(Transform3D(Basis(Vector3.UP, yaw), centre + offset + Vector3(0.0, half.y, 0.0)), half, color, 0.6)
	var top := Transform3D(Basis(Vector3.UP, yaw + 0.1), centre + Vector3(0.0, half.y * 3.0, 0.0))
	result.add_box(top, half, ClayPalette.shade(color, 1.06), 0.7)


## Trees are two stacked cones on a short trunk.
static func _add_wood(result: ClayBuilder, generator: RandomNumberGenerator) -> void:
	var crown := ClayPalette.mute(Palette.resource_pattern_color(SiResource.WOOD))
	var crown_light := ClayPalette.mute(Palette.PINE_LIGHT)
	var trunk := ClayPalette.mute(ClayPalette.WOOD_BROWN)
	var trunk_profile := PackedVector2Array([Vector2(0.034, 0.0), Vector2(0.026, 0.12)])
	var lower_cone := PackedVector2Array([Vector2(0.125, 0.07), Vector2(0.0, 0.3)])
	var upper_cone := PackedVector2Array([Vector2(0.09, 0.2), Vector2(0.0, 0.4)])
	for slot in _slots(generator, 6):
		var transform := _placed(slot, Vector3.ONE * generator.randf_range(0.8, 1.0), generator.randf() * TAU)
		result.add_lathe(trunk_profile, transform, trunk, 0.5, 5)
		result.add_lathe(lower_cone, transform, crown, 0.55, 6)
		result.add_lathe(upper_cone, transform, crown_light, 0.75, 6)


static func _add_sheep(result: ClayBuilder, generator: RandomNumberGenerator) -> void:
	var tuft := ClayPalette.mute(Palette.resource_pattern_color(SiResource.SHEEP))
	for slot in _slots(generator, 3):
		_add_sheep_at(result, slot, generator.randf() * TAU)
	for slot in _slots(generator, 4):
		var size := generator.randf_range(0.035, 0.055)
		result.add_sphere(_placed(slot * 1.1, Vector3(size, size * 0.8, size)), tuft, 0.6, 5)


## A fleece blob, a dark head and a dark block under the body for the legs.
static func _add_sheep_at(result: ClayBuilder, position: Vector3, yaw: float) -> void:
	var fleece := ClayPalette.mute(Palette.FLEECE)
	var face := ClayPalette.mute(ClayPalette.SHEEP_FACE)
	var heading := Basis(Vector3.UP, yaw)
	result.add_sphere(Transform3D(heading * Basis.from_scale(Vector3(0.12, 0.085, 0.085)), position + heading * Vector3(0.0, 0.1, 0.0)), fleece, 0.55, 6)
	result.add_sphere(Transform3D(heading * Basis.from_scale(Vector3(0.04, 0.036, 0.034)), position + heading * Vector3(0.125, 0.105, 0.0)), face, 0.7, 5)
	result.add_box(Transform3D(heading, position + heading * Vector3(0.0, 0.03, 0.0)), Vector3(0.07, 0.03, 0.04), face, 0.5)


static func _add_wheat(result: ClayBuilder, generator: RandomNumberGenerator) -> void:
	var stalk := ClayPalette.mute(Palette.resource_pattern_color(SiResource.WHEAT))
	var ear := ClayPalette.mute(ClayPalette.EAR_GOLD)
	var stem := PackedVector2Array([Vector2(0.017, 0.0), Vector2(0.011, 0.16)])
	var head := PackedVector2Array([Vector2(0.032, 0.0), Vector2(0.03, 0.05), Vector2(0.0, 0.12)])
	for slot in _slots(generator, 5):
		for strand in 3:
			var angle := TAU * strand / 3.0 + generator.randf_range(-0.3, 0.3)
			var spread := generator.randf_range(0.02, 0.06)
			var base := slot + Vector3(cos(angle), 0.0, sin(angle)) * spread
			var lean := Vector3(sin(angle) * 0.18, 0.0, -cos(angle) * 0.18)
			var transform := _placed(base, Vector3.ONE * generator.randf_range(0.9, 1.25), 0.0, lean)
			result.add_lathe(stem, transform, stalk, 0.55, 4)
			result.add_lathe(head, transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.15, 0.0)), ear, 0.8, 5)


## Rocks are low faceted blobs; the first has a snow cap.
static func _add_ore(result: ClayBuilder, generator: RandomNumberGenerator) -> void:
	var rock := ClayPalette.mute(Palette.resource_pattern_color(SiResource.ORE))
	var rock_light := ClayPalette.mute(Palette.RESOURCE_COLORS[SiResource.ORE]).lightened(0.12)
	var snow := ClayPalette.mute(Palette.PEAK_SNOW)
	var slots := _slots(generator, 4)
	for index in slots.size():
		var width := generator.randf_range(0.1, 0.16)
		var height := width * generator.randf_range(0.75, 1.2)
		var yaw := generator.randf() * TAU
		var centre := slots[index] + Vector3(0.0, height * 0.55, 0.0)
		var color := rock if index % 2 == 0 else rock_light
		result.add_sphere(_placed(centre, Vector3(width, height, width * 0.85), yaw, Vector3(0.0, 0.0, 0.2)), color, 0.55, 6)
		if index == 0:
			var cap := centre + Vector3(0.0, height * 0.62, 0.0)
			result.add_sphere(_placed(cap, Vector3(width * 0.5, height * 0.3, width * 0.45), yaw), snow, 0.85, 5)


static func _add_desert(result: ClayBuilder, generator: RandomNumberGenerator) -> void:
	var ripple := ClayPalette.mute(Palette.DESERT_PATTERN)
	var rock := ClayPalette.mute(Palette.DESERT_ROCK)
	var yaw := generator.randf() * PI
	var along := Basis(Vector3.UP, yaw)
	for index in 3:
		var offset := along * Vector3(0.0, 0.0, (index - 1.0) * 0.36)
		var length := 0.62 - absf(index - 1.0) * 0.14
		result.add_sphere(_placed(offset, Vector3(length, 0.034, 0.075), yaw), ripple, 0.7, 6)
	for slot in _slots(generator, 2):
		var size := generator.randf_range(0.05, 0.08)
		result.add_sphere(_placed(slot + Vector3(0.0, size * 0.4, 0.0), Vector3(size, size * 0.7, size * 0.9), generator.randf() * TAU), rock, 0.6, 5)
