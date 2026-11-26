class_name Palette
extends RefCounted
## The colours of doc/design/visual-style.md section 1, shared by the board, the HUD and the theme.

## Terrain fills by `SiResource` value.
const RESOURCE_COLORS := {
	SiResource.CLAY: Color("#B5653D"),
	SiResource.WOOD: Color("#33603D"),
	SiResource.SHEEP: Color("#A2C46A"),
	SiResource.WHEAT: Color("#EDC24F"),
	SiResource.ORE: Color("#7A8492"),
}
## Motif colours drawn on top of each terrain, same keys.
const RESOURCE_PATTERN_COLORS := {
	SiResource.CLAY: Color("#8E4A2A"),
	SiResource.WOOD: Color("#244A2D"),
	SiResource.SHEEP: Color("#86A852"),
	SiResource.WHEAT: Color("#C99A2E"),
	SiResource.ORE: Color("#5A636F"),
}
const DESERT := Color("#EADDB6")
const DESERT_PATTERN := Color("#D3C291")
const FLEECE := Color("#F6F1E4")

## Ember, Cobalt, Ivory, Charcoal.
const SEAT_COLORS: Array[Color] = [Color("#C8372D"), Color("#2E62C9"), Color("#F4EFE3"), Color("#2F2B2C")]
const SEAT_NAMES: Array[String] = ["Ember", "Cobalt", "Ivory", "Charcoal"]
const OUTLINE := Color("#231C17")
const KEYLINE := Color("#F4EFE3")
const IVORY_SEAT := 2
const CHARCOAL_SEAT := 3

const TABLE := Color("#2A1F19")
const PARCHMENT := Color("#F2E8D2")
const PARCHMENT_DEEP := Color("#E6D8BA")
const CARD_STOCK := Color("#FBF5E6")
const INK := Color("#2E241C")
const INK_MUTED := Color("#6B5A45")
const CREAM := Color("#F3EADB")
const CREAM_MUTED := Color("#BFAE95")
const BORDER := Color("#8A6A44")
const ACCENT := Color("#1E6B63")
const DANGER := Color("#A3332A")
const FOCUS_ON_DARK := Color("#E8A93A")
const FOCUS_ON_LIGHT := Color("#8C5A0E")
const HOT_NUMBER := Color("#B5281F")

## Theme-only shades: buttons, disabled states, rules, overlays.
const BUTTON := Color("#E2D3B2")
const BUTTON_HOVER := Color("#EADDBE")
const BUTTON_PRESSED := Color("#D3C29C")
const BUTTON_HOVER_BORDER := Color("#6E5233")
const DISABLED_FILL := Color("#D9CDB5")
const DISABLED_BORDER := Color("#C2B597")
const DISABLED_TEXT := Color("#7A6E5E")
const RULE := Color("#C9B48E")
const RULE_FAINT := Color("#C9B48E66")
const ACCENT_HOVER := Color("#26807A")
const ACCENT_PRESSED := Color("#15524C")
const ACCENT_SELECTION := Color("#1E6B6366")
const DANGER_HOVER := Color("#B8443A")
const DANGER_PRESSED := Color("#86271F")
const GHOST_HOVER := Color("#FFFFFF1A")
const GHOST_PRESSED := Color("#FFFFFF26")
const CREAM_DISABLED := Color("#BFAE9599")
const TABLE_PANEL := Color("#3A2C23")
const TABLE_PANEL_BORDER := Color("#4E3B2E")
const LOG_CUT := Color("#C9A46A")
## Board-only colours: sea, props, targets.
const SEA := Color("#2A6672")
const WAVE := Color("#357A86")
const SHOAL := Color("#3E8790")
const SAND := Color("#D9C48F")
const CHIP_RIM := Color("#7A5E3A")
const PIER := Color("#7B5634")
const PIER_TIE := Color("#5C3F26")
const TARGET := Color("#F3C54A")
const TARGET_HALO := Color("#231C17", 0.45)
const ROBBER := Color("#3A3036")
const SHADOW := Color(0.0, 0.0, 0.0, 0.28)
const SHADOW_SOFT := Color(0.0, 0.0, 0.0, 0.3)
const PINE_LIGHT := Color("#4F8457")
const DESERT_ROCK := Color("#B9A777")
const PEAK_SNOW := Color("#DCE0E5")
const CLEAR := Color(0, 0, 0, 0)


static func seat_color(seat: int) -> Color:
	return SEAT_COLORS[seat % SEAT_COLORS.size()]


## The dark line around a piece; Charcoal inverts it so its dark fill still separates.
static func seat_outline(seat: int) -> Color:
	return KEYLINE if seat % SEAT_COLORS.size() == CHARCOAL_SEAT else OUTLINE


## The outer halo around the outline; transparent for Ivory, whose fill is already the light line.
static func seat_keyline(seat: int) -> Color:
	var wrapped := seat % SEAT_COLORS.size()
	if wrapped == CHARCOAL_SEAT:
		return OUTLINE
	if wrapped == IVORY_SEAT:
		return Color(KEYLINE, 0.0)
	return KEYLINE


static func resource_color(resource: String) -> Color:
	if not RESOURCE_COLORS.has(resource):
		push_error("Palette: unknown resource '%s'" % resource)
		return Color.MAGENTA
	return RESOURCE_COLORS[resource]


static func resource_pattern_color(resource: String) -> Color:
	if not RESOURCE_PATTERN_COLORS.has(resource):
		push_error("Palette: unknown resource '%s'" % resource)
		return Color.MAGENTA
	return RESOURCE_PATTERN_COLORS[resource]
