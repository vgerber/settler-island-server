class_name PortArt
extends RefCounted
## A port: a plank pier and, separately, a flag with the ratio. The pier is built along local +x starting
## at the coast edge midpoint (origin), `PIER_LENGTH` out over the sea; turn it with
## `Basis(Vector3.UP, atan2(-outward.y, outward.x))` for a 2D outward direction. The flag stands on the pier tip
## and is never rotated, so its text always reads for the fixed camera. Pier planks sit on y = `DECK_HEIGHT`
## above the table (the sea surface is at `TableArt.SEA_LEVEL`).

const PIER_LENGTH := 0.82
const DECK_HEIGHT := 0.11
const FLAG_TILT := 0.5
const FLAG_HEIGHT := 0.3

static var _piers: Dictionary = {}
static var _flags: Dictionary = {}


## `resource` is a `SiResource` value for a 2:1 port (its sacks and crate lids show the resource) or "" for 3:1.
static func pier(resource := "") -> ArrayMesh:
	if not _piers.has(resource):
		_piers[resource] = pier_builder(resource).to_mesh()
	return _piers[resource]


static func pier_builder(resource := "") -> ClayBuilder:
	var wood := ClayPalette.mute(Palette.PIER)
	var dark := ClayPalette.mute(Palette.PIER_TIE)
	var goods := ClayPalette.mute(Palette.CARD_STOCK if resource.is_empty() else Palette.resource_color(resource))
	var result := ClayBuilder.new()
	_add_deck(result, wood, dark)
	_add_posts_and_rope(result, wood, dark)
	_add_cargo(result, wood, dark, goods, resource.is_empty())
	_add_boat(result, wood, dark)
	return result


static func _add_deck(result: ClayBuilder, wood: Color, dark: Color) -> void:
	for side in [-1.0, 1.0]:
		var stringer := Transform3D(Basis.IDENTITY, Vector3(PIER_LENGTH * 0.5, DECK_HEIGHT - 0.035, side * 0.1))
		result.add_box(stringer, Vector3(PIER_LENGTH * 0.5, 0.016, 0.014), dark, 0.55)
	var planks := 8
	var pitch := PIER_LENGTH / planks
	for index in planks:
		var along := pitch * (index + 0.5)
		var half := Vector3(pitch * 0.5 - 0.007, 0.016, 0.145 + 0.006 * (index % 3 - 1))
		var shade: float = [1.0, 0.9, 0.96, 0.84][index % 4]
		var turned := Basis(Vector3.UP, 0.012 * ((index % 3) - 1))
		var lift := 0.003 * (index % 2)
		result.add_box(Transform3D(turned, Vector3(along, DECK_HEIGHT - 0.01 + lift, 0.0)), half, ClayPalette.shade(wood, shade), 0.75)
		for side in [-1.0, 1.0]:
			var nail := Transform3D(Basis.IDENTITY, Vector3(along, DECK_HEIGHT + 0.008 + lift, side * 0.1))
			result.add_box(nail, Vector3(0.006, 0.002, 0.006), dark, 1.0)


static func _add_posts_and_rope(result: ClayBuilder, wood: Color, dark: Color) -> void:
	var stations := [0.07, 0.4, 0.76]
	for side in [-1.0, 1.0]:
		for index in stations.size():
			var height := 0.2 if index == 0 else 0.17
			var post := Transform3D(Basis.IDENTITY, Vector3(stations[index], height * 0.5, side * 0.17))
			result.add_box(post, Vector3(0.022, height * 0.5, 0.022), dark, 0.5)
			var cap := Transform3D(Basis.IDENTITY, Vector3(stations[index], height + 0.008, side * 0.17))
			result.add_box(cap, Vector3(0.028, 0.008, 0.028), ClayPalette.shade(wood, 1.15), 0.9)
		var rope_colour := ClayPalette.mute(Palette.CREAM_MUTED)
		for index in stations.size() - 1:
			var from := Vector3(stations[index], 0.15, side * 0.17)
			var to := Vector3(stations[index + 1], 0.15, side * 0.17)
			var sag := Vector3(0.0, -0.025, 0.0)
			_add_rope(result, from, (from + to) * 0.5 + sag, rope_colour)
			_add_rope(result, (from + to) * 0.5 + sag, to, rope_colour)


static func _add_rope(result: ClayBuilder, from: Vector3, to: Vector3, color: Color) -> void:
	var direction := to - from
	var tilt := Basis(Vector3.BACK, atan2(direction.y, direction.x))
	result.add_box(Transform3D(tilt, (from + to) * 0.5), Vector3(direction.length() * 0.5, 0.005, 0.005), color, 1.0)


## Two stacked crates and sacks of the resource (a barrel and a coil of rope at a 3:1 port).
static func _add_cargo(result: ClayBuilder, wood: Color, dark: Color, goods: Color, generic: bool) -> void:
	var crate := Vector3(0.24, DECK_HEIGHT + 0.006, -0.065)
	result.add_box(Transform3D(Basis(Vector3.UP, 0.15), crate + Vector3(0.0, 0.045, 0.0)), Vector3.ONE * 0.045, ClayPalette.shade(wood, 1.12), 0.7)
	result.add_box(Transform3D(Basis(Vector3.UP, 0.15), crate + Vector3(0.0, 0.092, 0.0)), Vector3(0.047, 0.003, 0.047), goods, 0.95)
	result.add_box(Transform3D(Basis(Vector3.UP, -0.3), crate + Vector3(0.015, 0.136, 0.004)), Vector3(0.032, 0.032, 0.032), ClayPalette.shade(wood, 0.95), 0.75)
	var sack_spot := Vector3(0.52, DECK_HEIGHT + 0.006, 0.075)
	if generic:
		_add_barrel(result, sack_spot + Vector3(0.0, 0.0, 0.0), wood, dark)
		_add_barrel(result, sack_spot + Vector3(-0.07, 0.0, -0.04), wood, dark)
		return
	for index in 3:
		var offset := Vector3([-0.045, 0.045, 0.0][index], 0.0, [0.0, 0.01, 0.045][index])
		var lift := 0.0 if index < 2 else 0.04
		var body := Transform3D(Basis.from_scale(Vector3(0.05, 0.042, 0.04)), sack_spot + offset + Vector3(0.0, 0.032 + lift, 0.0))
		result.add_sphere(body, goods, 0.7, 6)
		var tie := Transform3D(Basis.IDENTITY, sack_spot + offset + Vector3(0.0, 0.07 + lift, 0.0))
		result.add_box(tie, Vector3(0.014, 0.007, 0.014), ClayPalette.shade(goods, 0.7), 0.9)


static func _add_barrel(result: ClayBuilder, base: Vector3, wood: Color, dark: Color) -> void:
	var staves := PackedVector2Array([Vector2(0.036, 0.0), Vector2(0.046, 0.035), Vector2(0.036, 0.075), Vector2(0.0, 0.075)])
	result.add_lathe(staves, Transform3D(Basis.IDENTITY, base), ClayPalette.shade(wood, 1.1), 0.7, 7)
	var hoop := PackedVector2Array([Vector2(0.0455, 0.02), Vector2(0.0465, 0.03), Vector2(0.0455, 0.04)])
	result.add_lathe(hoop, Transform3D(Basis.IDENTITY, base), dark, 0.9, 7)


## A rowing boat tied at the pier side: pointed hull, darker inside, a seat, a mast with a small sail and a rope.
static func _add_boat(result: ClayBuilder, wood: Color, dark: Color) -> void:
	var origin := Vector3(0.5, 0.07, 0.36)
	var hull := PackedVector2Array([Vector2(-0.14, -0.05), Vector2(0.07, -0.056), Vector2(0.17, 0.0), Vector2(0.07, 0.056), Vector2(-0.14, 0.05)])
	var turn := Basis(Vector3.UP, 0.08)
	result.add_prism(Transform3D(turn, origin), hull, 0.06, ClayPalette.shade(wood, 1.2), 0.6)
	var inside := PackedVector2Array([Vector2(-0.125, -0.036), Vector2(0.06, -0.042), Vector2(0.135, 0.0), Vector2(0.06, 0.042), Vector2(-0.125, 0.036)])
	result.add_prism(Transform3D(turn, origin + Vector3(0.0, 0.052, 0.0)), inside, 0.012, ClayPalette.shade(dark, 0.7), 0.9)
	result.add_box(Transform3D(turn, origin + turn * Vector3(-0.03, 0.07, 0.0)), Vector3(0.012, 0.006, 0.05), ClayPalette.shade(wood, 1.3), 0.9)
	result.add_box(Transform3D(turn, origin + turn * Vector3(0.03, 0.17, 0.0)), Vector3(0.005, 0.11, 0.005), dark, 0.6)
	var sail := PackedVector2Array([Vector2(0.0, 0.0), Vector2(-0.085, 0.0), Vector2(0.0, 0.14)])
	var upright := turn * Basis(Vector3.RIGHT, -PI * 0.5)
	result.add_prism(Transform3D(upright, origin + turn * Vector3(0.036, 0.1, 0.002)), sail, 0.004, ClayPalette.mute(Palette.CARD_STOCK), 0.9)
	_add_rope(result, Vector3(0.4, 0.14, 0.17), origin + turn * Vector3(-0.1, 0.06, 0.0), ClayPalette.mute(Palette.CREAM_MUTED))


## Flag with the ratio; `resource` is a `SiResource` value for a 2:1 port or "" for a 3:1 port. The origin is
## the foot of the pole.
static func flag(ratio: int, resource: String) -> ArrayMesh:
	var key := "%d:%s" % [ratio, resource]
	if not _flags.has(key):
		_flags[key] = flag_builder(ratio, resource).to_mesh()
	return _flags[key]


static func flag_builder(ratio: int, resource: String) -> ClayBuilder:
	var cloth := ClayPalette.mute(Palette.CARD_STOCK if resource.is_empty() else Palette.resource_color(resource))
	var ink := Palette.INK if cloth.get_luminance() > 0.4 else Palette.CARD_STOCK
	var result := ClayBuilder.new()
	result.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, FLAG_HEIGHT * 0.5, 0.0)), Vector3(0.016, FLAG_HEIGHT * 0.5, 0.016), ClayPalette.mute(Palette.PIER_TIE), 0.6)
	var plate_basis := Basis(Vector3.RIGHT, FLAG_TILT)
	var plate_centre := Vector3(0.0, FLAG_HEIGHT + 0.03, 0.0)
	result.add_box(Transform3D(plate_basis, plate_centre), Vector3(0.17, 0.016, 0.115), cloth, 0.8)
	var surface := plate_centre + plate_basis * Vector3(0.0, 0.016 + 0.003, 0.0)
	StrokeFont.add_text(result, "%d:1" % ratio, Transform3D(plate_basis, surface), 0.1, 0.02, ink)
	return result
