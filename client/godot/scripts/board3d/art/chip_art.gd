class_name ChipArt
extends RefCounted
## The number chip: a flat clay disc with the number pressed in as dark ribbons and probability dots below it.
## 6 and 8 use `Palette.HOT_NUMBER`. Origin at the chip's base; text reads upright for a camera looking toward
## -z (glyph up is -z). The chip lies flat; the board tilts it toward the camera if it wants to.

const RADIUS := 0.27
const HEIGHT := 0.055
const RIM_RADIUS := 0.285
const RIM_HEIGHT := 0.04
const TEXT_HEIGHT := 0.17
const STROKE_WIDTH := 0.028
## Text and dots sit this far above the chip top so the depth buffer separates them.
const INLAY_LIFT := 0.004

static var _cache: Dictionary = {}


static func chip(number: int) -> ArrayMesh:
	if not _cache.has(number):
		_cache[number] = builder(number).to_mesh()
	return _cache[number]


static func builder(number: int) -> ClayBuilder:
	var result := ClayBuilder.new()
	var face := ClayPalette.mute(ClayPalette.CHIP_FACE)
	var rim := ClayPalette.mute(Palette.CHIP_RIM)
	result.add_lathe(_rim_profile(), Transform3D.IDENTITY, rim, 0.6)
	result.add_lathe(_face_profile(), Transform3D.IDENTITY, face, 0.85)
	var ink := Palette.HOT_NUMBER if number == 6 or number == 8 else Palette.INK
	var top := HEIGHT + INLAY_LIFT
	StrokeFont.add_text(result, str(number), Transform3D(Basis.IDENTITY, Vector3(0.0, top, -0.035)), TEXT_HEIGHT, STROKE_WIDTH, ink)
	for index in dot_count(number):
		var x := (index - (dot_count(number) - 1) * 0.5) * 0.046
		StrokeFont.add_disc(result, Transform3D(Basis.IDENTITY, Vector3(x, top, 0.145)), 0.016, ink, 5)
	return result


## Chances in 36 of rolling `number`, the dots under it.
static func dot_count(number: int) -> int:
	return 6 - absi(7 - number)


## The ring under the face: a chamfered outer wall and a flat top that dips toward the face.
static func _rim_profile() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(RIM_RADIUS, 0.0), Vector2(RIM_RADIUS, RIM_HEIGHT * 0.5), Vector2(RIM_RADIUS - 0.018, RIM_HEIGHT),
		Vector2(RADIUS - 0.01, RIM_HEIGHT), Vector2(RADIUS - 0.02, RIM_HEIGHT * 0.8),
	])


## The face: a puck set into the ring with a bevelled edge and a flat top.
static func _face_profile() -> PackedVector2Array:
	return PackedVector2Array([Vector2(RADIUS - 0.015, 0.0), Vector2(RADIUS - 0.015, HEIGHT * 0.5), Vector2(RADIUS - 0.04, HEIGHT), Vector2(0.0, HEIGHT)])
