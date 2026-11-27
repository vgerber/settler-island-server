class_name ClayPalette
extends RefCounted
## `Palette` colours as clay: the same hues with the saturation lowered (matte clay is less vivid than paint).
## All kit meshes bake these, so the 3D look stays tied to the 2D HUD colours.

const SATURATION := 0.9
const WOOD_BROWN := Color("#6B4A2E")
const BRICK_LIGHT := Color("#C97A4E")
const DARK_CLAY := Color("#3A3036")
const SHEEP_FACE := Color("#4A3E43")
const EAR_GOLD := Color("#F2D26A")
## The number chip face and the ink of the unhot numbers.
const CHIP_FACE := Color("#FBF5E6")


static func mute(color: Color) -> Color:
	return Color.from_hsv(color.h, color.s * SATURATION, color.v, color.a)


static func shade(color: Color, factor: float) -> Color:
	return Color(color.r * factor, color.g * factor, color.b * factor, color.a)


## The muted colour of a seat; also the tint of its pieces.
static func seat(seat_index: int) -> Color:
	return mute(Palette.seat_color(seat_index))
