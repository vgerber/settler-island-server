class_name Palette
extends RefCounted
## The colours of doc/design/visual-style.md section 1, shared by the board, the HUD and the theme.

## Terrain fills, in `SiResource.VALUES` order: Clay, Wood, Sheep, Wheat, Ore.
const RESOURCE_COLORS: Array[Color] = [
	Color("#B5653D"),
	Color("#33603D"),
	Color("#A2C46A"),
	Color("#EDC24F"),
	Color("#7A8492"),
]
## Motif colours drawn on top of each terrain, same order.
const RESOURCE_PATTERN_COLORS: Array[Color] = [
	Color("#8E4A2A"),
	Color("#244A2D"),
	Color("#86A852"),
	Color("#C99A2E"),
	Color("#5A636F"),
]
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
	return RESOURCE_COLORS[maxi(SiResource.VALUES.find(resource), 0)]


static func resource_pattern_color(resource: String) -> Color:
	return RESOURCE_PATTERN_COLORS[maxi(SiResource.VALUES.find(resource), 0)]
