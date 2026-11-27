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
	result.add_lathe(_disc_profile(RIM_RADIUS, RIM_HEIGHT), Transform3D.IDENTITY, rim, 0.6, 32)
	result.add_lathe(_disc_profile(RADIUS, HEIGHT), Transform3D.IDENTITY, face, 0.85, 32)
	var ink := Palette.HOT_NUMBER if number == 6 or number == 8 else Palette.INK
	var top := HEIGHT + INLAY_LIFT
	StrokeFont.add_text(result, str(number), Transform3D(Basis.IDENTITY, Vector3(0.0, top, -0.035)), TEXT_HEIGHT, STROKE_WIDTH, ink)
	for index in dot_count(number):
		var x := (index - (dot_count(number) - 1) * 0.5) * 0.046
		StrokeFont.add_disc(result, Transform3D(Basis.IDENTITY, Vector3(x, top, 0.145)), 0.014, ink, 8)
	return result


## Chances in 36 of rolling `number`, the dots under it.
static func dot_count(number: int) -> int:
	return 6 - absi(7 - number)


## A rounded puck: flat top, soft edge, `radius` and `height`.
static func _disc_profile(radius: float, height: float) -> PackedVector2Array:
	var profile := PackedVector2Array([Vector2(0.0, 0.0), Vector2(radius * 0.97, 0.0)])
	var rounding := height * 0.45
	for step in 5:
		var angle := PI * 0.5 * step / 4.0
		profile.append(Vector2(radius - rounding + cos(angle) * rounding, height - rounding + sin(angle) * rounding))
	profile.append(Vector2(radius * 0.5, height))
	profile.append(Vector2(0.0, height))
	return profile
