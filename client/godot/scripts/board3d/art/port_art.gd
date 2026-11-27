class_name PortArt
extends RefCounted
## A port: a rolled-plank pier and, separately, a flag with the ratio. The pier is built along local +x starting
## at the coast edge midpoint (origin), `PIER_LENGTH` out over the sea; turn it with
## `Basis(Vector3.UP, atan2(-outward.y, outward.x))` for a 2D outward direction. The flag stands on the pier tip
## and is never rotated, so its text always reads for the fixed camera. Pier planks sit on y = `DECK_HEIGHT`
## above the table (the sea surface is at `TableArt.SEA_LEVEL`).

const PIER_LENGTH := 0.82
const DECK_HEIGHT := 0.11
const FLAG_TILT := 0.5
const FLAG_HEIGHT := 0.3

static var _pier: ArrayMesh = null
static var _flags: Dictionary = {}


static func pier() -> ArrayMesh:
	if _pier == null:
		_pier = pier_builder().to_mesh()
	return _pier


static func pier_builder() -> ClayBuilder:
	var plank := ClayPalette.mute(Palette.PIER)
	var tie := ClayPalette.mute(Palette.PIER_TIE)
	var result := ClayBuilder.new()
	var planks := 5
	for index in planks:
		var along := PIER_LENGTH * (index + 0.5) / planks
		var half := Vector3(PIER_LENGTH / planks * 0.5 - 0.008, 0.018, 0.15)
		var shade := 1.0 - 0.06 * (index % 2)
		result.add_round_box(Transform3D(Basis.IDENTITY, Vector3(along, DECK_HEIGHT, 0.0)), half, 0.014, ClayPalette.shade(plank, shade), 0.75)
	for rail in [-1.0, 1.0]:
		var beam := Transform3D(Basis.IDENTITY, Vector3(PIER_LENGTH * 0.5, DECK_HEIGHT - 0.03, rail * 0.13))
		result.add_round_box(beam, Vector3(PIER_LENGTH * 0.5, 0.014, 0.018), 0.01, tie, 0.6)
	var post_profile := ClayBuilder.capsule_profile(0.033, 0.07, 4)
	for along in [0.08, PIER_LENGTH - 0.06]:
		for side in [-1.0, 1.0]:
			var post := Transform3D(Basis.IDENTITY, Vector3(along, 0.07, side * 0.17))
			result.add_lathe(post_profile, post, tie, 0.55, 10)
	return result


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
	var pole := ClayBuilder.capsule_profile(0.016, FLAG_HEIGHT * 0.5 - 0.016, 4)
	result.add_lathe(pole, Transform3D(Basis.IDENTITY, Vector3(0.0, FLAG_HEIGHT * 0.5, 0.0)), ClayPalette.mute(Palette.PIER_TIE), 0.6, 8)
	var plate_basis := Basis(Vector3.RIGHT, FLAG_TILT)
	var plate_centre := Vector3(0.0, FLAG_HEIGHT + 0.03, 0.0)
	result.add_round_box(Transform3D(plate_basis, plate_centre), Vector3(0.17, 0.016, 0.115), 0.012, cloth, 0.8)
	var surface := plate_centre + plate_basis * Vector3(0.0, 0.016 + 0.003, 0.0)
	StrokeFont.add_text(result, "%d:1" % ratio, Transform3D(plate_basis, surface), 0.1, 0.02, ink)
	return result
