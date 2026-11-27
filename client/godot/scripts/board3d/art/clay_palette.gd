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
const SHOAL_LIGHT := Color("#4A9C99")
const LEAF_BRIGHT := Color("#6FA25A")
const BUSH_GREEN := Color("#4C7F42")
const FLOWER_WHITE := Color("#F4EFE3")
const FLOWER_PINK := Color("#E58FA4")
const FLOWER_YELLOW := Color("#F2D26A")
const STRAW := Color("#D9AE4A")
const STRAW_DARK := Color("#B58A32")
const BARN_RED := Color("#A5432F")
const PLASTER := Color("#E8DFC8")
const STONE_GREY := Color("#8E9099")
const STONE_DARK := Color("#5C5F68")
const KILN_RED := Color("#9C4A2C")
const CACTUS_GREEN := Color("#6E9A57")
const BONE := Color("#F0E8D2")
## The number chip face and the ink of the unhot numbers.
const CHIP_FACE := Color("#FBF5E6")


static func mute(color: Color) -> Color:
	return Color.from_hsv(color.h, color.s * SATURATION, color.v, color.a)


static func shade(color: Color, factor: float) -> Color:
	return Color(color.r * factor, color.g * factor, color.b * factor, color.a)


## The muted colour of a seat; also the tint of its pieces.
static func seat(seat_index: int) -> Color:
	return mute(Palette.seat_color(seat_index))
