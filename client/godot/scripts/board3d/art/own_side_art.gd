class_name OwnSideArt
extends RefCounted
## The fixtures at the own seat of the 3D table UI (doc/design/table-ui-style.md): the supply rack, the hand
## tray, the end-turn bell with its cover, and the prompt sign. All are walnut and brass vertex colours for
## `ClayMaterials.terrain()`, except `prompt_sign_tab` (white clay for `ClayMaterials.piece(seat)`) and
## `placeholder_card` (`ClayMaterials.stock()`). Origin at the base centre, resting on y = 0, front toward +z.

const WALNUT := Color("#5A3E2A")
const WALNUT_TOP := Color("#7B5634")
const WALNUT_GROOVE := Color("#3F2B1A")
const LIGHT_WOOD := Color("#B58A5A")
const BRASS := Color("#C9A46A")
const BRASS_LIGHT := Color("#E8C77C")
const BRASS_DARK := Color("#8E6A28")
const DEV_PLUM := Color("#5B4378")
const TAB_CLAY := Color(0.92, 0.92, 0.92)
const BEVEL := 0.012

const CARD_HALF := Vector3(0.18, 0.007, 0.25)

## Supply rack: three stepped tiers, roads in front (low), settlements, cities at the back (tall pieces). Per row:
## the tier's front and back z, its top height, the socket pitch and half size. Roads lie along z in their sockets.
const RACK_HALF_WIDTH := 1.45
const RACK_LEDGE_DEPTH := 0.18
const RACK_PAD_HALF_HEIGHT := 0.003
const RACK_ROWS := {
	"road": {"count": 15, "pitch": 0.16, "front": 0.98, "back": 0.11, "height": 0.08, "pad": Vector2(0.07, 0.34), "yaw": PI * 0.5},
	"settlement": {"count": 5, "pitch": 0.34, "front": 0.11, "back": -0.47, "height": 0.19, "pad": Vector2(0.15, 0.13), "yaw": 0.0},
	"city": {"count": 4, "pitch": 0.66, "front": -0.47, "back": -1.12, "height": 0.30, "pad": Vector2(0.31, 0.18), "yaw": 0.0},
}

## Hand tray: a sloped board between cheeks; five resource slots, a divider, then the dev section.
const HAND_HALF_WIDTH := 1.72
const HAND_TILT := deg_to_rad(34.0)
const HAND_SLOPE_LENGTH := 0.66
const HAND_FRONT_TOP := Vector3(0.0, 0.10, 0.33)
const HAND_SLOT_PITCH := 0.46
const HAND_FIRST_SLOT := -1.40
const HAND_DEV_SLOT := 1.2
const HAND_FRONT_Z := 0.38
const HAND_BACK_Z := -0.30

const BELL_BASE_HEIGHT := 0.09

## Prompt sign: the board leans back by `SIGN_TILT`; the text field is right of the seat tab.
const SIGN_HALF_WIDTH := 1.3
const SIGN_HALF_HEIGHT := 0.25
const SIGN_BOARD_BOTTOM := 0.38
const SIGN_TILT := deg_to_rad(36.0)
const SIGN_HALF_THICKNESS := 0.03
const SIGN_TAB_X := -1.02
const SIGN_TEXT_X := 0.24
const SIGN_TEXT_WIDTH := 2.0
const SIGN_TEXT_HEIGHT := 0.34

static var _cache: Dictionary = {}


static func supply_rack() -> ArrayMesh:
	return _mesh("rack", _build_rack)


static func hand_tray() -> ArrayMesh:
	return _mesh("hand_tray", _build_hand_tray)


static func bell() -> ArrayMesh:
	return _mesh("bell", _build_bell)


## Place at y = `BELL_BASE_HEIGHT` over the bell's base.
static func bell_cover() -> ArrayMesh:
	return _mesh("bell_cover", _build_bell_cover)


static func prompt_sign() -> ArrayMesh:
	return _mesh("sign", _build_sign)


## White clay; tint it with `ClayMaterials.piece(seat)`. Same origin as the sign.
static func prompt_sign_tab() -> ArrayMesh:
	return _mesh("sign_tab", _build_sign_tab)


static func placeholder_card() -> ArrayMesh:
	return _mesh("card", _build_card)


## Where the piece of `kind` ("road", "settlement", "city") number `index` rests, in rack-local space.
static func supply_slot(kind: String, index: int) -> Vector3:
	var row: Dictionary = RACK_ROWS[kind]
	var x: float = (index - (int(row["count"]) - 1) * 0.5) * float(row["pitch"])
	return Vector3(x, float(row["height"]) + RACK_PAD_HALF_HEIGHT * 2.0, _socket_z(row))


## Yaw of the piece in its socket (roads lie along z).
static func supply_yaw(kind: String) -> float:
	return RACK_ROWS[kind]["yaw"]


## The centre of the ledge in front of a row, on its top: the spot for the mini cost cards.
static func supply_ledge(kind: String) -> Vector3:
	var row: Dictionary = RACK_ROWS[kind]
	return Vector3(0.0, float(row["height"]), float(row["front"]) - RACK_LEDGE_DEPTH * 0.5)


## Where the card stack of slot `slot` (0 to 4 the resources, 5 the dev section) lies, in tray-local space.
static func hand_slot(slot: int) -> Transform3D:
	var slot_x := HAND_DEV_SLOT if slot > 4 else HAND_FIRST_SLOT + HAND_SLOT_PITCH * slot
	var basis := Basis(Vector3.RIGHT, HAND_TILT)
	var origin := HAND_FRONT_TOP + basis * Vector3(0.0, CARD_HALF.y, -(CARD_HALF.z + 0.04))
	return Transform3D(basis, Vector3(slot_x, origin.y, origin.z))


## The text line of the sign in sign-local space: centre of the text field, facing out of the board.
static func sign_text() -> Transform3D:
	var lean := _sign_lean()
	var field := Vector3(SIGN_TEXT_X, SIGN_BOARD_BOTTOM + SIGN_HALF_HEIGHT, SIGN_HALF_THICKNESS + 0.009)
	return Transform3D(lean, lean * field)


static func _sign_lean() -> Basis:
	return Basis(Vector3.RIGHT, -SIGN_TILT)


static func _socket_z(row: Dictionary) -> float:
	var pad: Vector2 = row["pad"]
	return float(row["front"]) - RACK_LEDGE_DEPTH - 0.02 - pad.y


static func _mesh(key: String, build: Callable) -> ArrayMesh:
	if not _cache.has(key):
		var result := ClayBuilder.new()
		build.call(result)
		_cache[key] = result.to_mesh()
	return _cache[key]


## A box with a small bevel (or sharp when `bevel` is 0), turned by `basis`.
static func _bar(result: ClayBuilder, centre: Vector3, half: Vector3, color: Color, bevel := BEVEL, basis := Basis.IDENTITY) -> void:
	var transform := Transform3D(basis, centre)
	if bevel <= 0.0:
		result.add_box(transform, half, color, 0.8)
		return
	var limit := minf(half.x, minf(half.y, half.z)) * 0.9
	result.add_bevelled_box(transform, half, minf(bevel, limit), color, 0.6)


static func _build_card(result: ClayBuilder) -> void:
	result.add_bevelled_box(Transform3D(Basis.IDENTITY, Vector3(0.0, CARD_HALF.y, 0.0)), CARD_HALF, 0.004, ClayPalette.shade(ClayPalette.mute(ClayPalette.CHIP_FACE), 0.8), 0.85)


static func _build_rack(result: ClayBuilder) -> void:
	_bar(result, Vector3(0.0, 0.015, -0.07), Vector3(RACK_HALF_WIDTH + 0.08, 0.015, 1.12), WALNUT_GROOVE, 0.0)
	for kind: String in RACK_ROWS:
		_add_tier(result, kind, RACK_ROWS[kind])
	_bar(result, Vector3(0.0, 0.2, -1.09), Vector3(RACK_HALF_WIDTH, 0.2, 0.03), WALNUT)


## One stepped block: a light ledge with a front lip, a groove, then dark socket pads.
static func _add_tier(result: ClayBuilder, kind: String, row: Dictionary) -> void:
	var height: float = row["height"]
	var front: float = row["front"]
	var back: float = row["back"]
	var half_width := RACK_HALF_WIDTH - 0.03
	_bar(result, Vector3(0.0, height * 0.5, (front + back) * 0.5), Vector3(RACK_HALF_WIDTH, height * 0.5, (front - back) * 0.5 - 0.005), WALNUT)
	_bar(result, Vector3(0.0, height + 0.001, (front + back) * 0.5), Vector3(half_width, 0.001, (front - back) * 0.5 - 0.03), WALNUT_TOP, 0.0)
	var ledge_middle := front - RACK_LEDGE_DEPTH * 0.5
	_bar(result, Vector3(0.0, height + 0.003, ledge_middle), Vector3(half_width, 0.002, RACK_LEDGE_DEPTH * 0.5 - 0.03), ClayPalette.shade(WALNUT_TOP, 1.2), 0.0)
	_bar(result, Vector3(0.0, height + 0.012, front - 0.03), Vector3(half_width, 0.014, 0.014), WALNUT_TOP, 0.007)
	_bar(result, Vector3(0.0, height + 0.002, front - RACK_LEDGE_DEPTH - 0.01), Vector3(half_width, 0.002, 0.006), WALNUT_GROOVE, 0.0)
	var pad: Vector2 = row["pad"]
	for index in int(row["count"]):
		var slot := supply_slot(kind, index)
		_bar(result, Vector3(slot.x, height + RACK_PAD_HALF_HEIGHT, slot.z), Vector3(pad.x, RACK_PAD_HALF_HEIGHT, pad.y), WALNUT_GROOVE, 0.0)


## A point on the slope `across` from the front edge (up the slope), lifted by `lift` along the slope normal.
static func _on_slope(across: float, lift: float) -> Vector3:
	return HAND_FRONT_TOP + Basis(Vector3.RIGHT, HAND_TILT) * Vector3(0.0, lift, -across)


static func _build_hand_tray(result: ClayBuilder) -> void:
	var slope := Basis(Vector3.RIGHT, HAND_TILT)
	var length := HAND_SLOPE_LENGTH
	var inner := HAND_HALF_WIDTH - 0.08
	_bar(result, Vector3(0.0, 0.015, 0.04), Vector3(HAND_HALF_WIDTH + 0.04, 0.015, 0.38), WALNUT_GROOVE, 0.0)
	_bar(result, _on_slope(length * 0.5, -0.025), Vector3(inner, 0.025, length * 0.5), WALNUT, BEVEL, slope)
	_bar(result, Vector3(0.0, 0.05, HAND_FRONT_Z - 0.05), Vector3(inner, 0.05, 0.05), WALNUT)
	_bar(result, _on_slope(0.02, 0.016), Vector3(inner, 0.016, 0.014), WALNUT_TOP, 0.007, slope)
	_add_cheeks(result)
	_add_hand_floors(result, slope)
	_add_dividers(result, slope)


## Two side walls whose top edge follows the slope.
static func _add_cheeks(result: ClayBuilder) -> void:
	var rise := tan(HAND_TILT)
	var top_front := HAND_FRONT_TOP.y - (HAND_FRONT_Z - HAND_FRONT_TOP.z) * rise + 0.03
	var top_back := HAND_FRONT_TOP.y + (HAND_FRONT_TOP.z - HAND_BACK_Z) * rise + 0.03
	var outline := PackedVector2Array([Vector2(HAND_FRONT_Z, 0.0), Vector2(HAND_BACK_Z, 0.0), Vector2(HAND_BACK_Z, top_back), Vector2(HAND_FRONT_Z, top_front)])
	var thickness := 0.08
	var turn := Basis(Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0))
	for side in [-1.0, 1.0]:
		var inner_x := HAND_HALF_WIDTH - thickness if side > 0.0 else -HAND_HALF_WIDTH
		result.add_prism(Transform3D(turn, Vector3(inner_x, 0.0, 0.0)), outline, thickness, WALNUT_TOP, 0.6)


static func _add_hand_floors(result: ClayBuilder, slope: Basis) -> void:
	var card_middle := CARD_HALF.z + 0.04
	for slot in 5:
		var slot_x := HAND_FIRST_SLOT + HAND_SLOT_PITCH * slot
		var centre := _on_slope(card_middle, 0.0015)
		_bar(result, Vector3(slot_x, centre.y, centre.z), Vector3(0.2, 0.0015, CARD_HALF.z + 0.02), LIGHT_WOOD, 0.0, slope)
	var dev := _on_slope(card_middle, 0.0015)
	_bar(result, Vector3(HAND_DEV_SLOT, dev.y, dev.z), Vector3(0.4, 0.0015, CARD_HALF.z + 0.02), ClayPalette.shade(LIGHT_WOOD, 0.85), 0.0, slope)
	var rail := _on_slope(CARD_HALF.z + 0.04, 0.0035)
	_bar(result, Vector3(HAND_DEV_SLOT, rail.y, rail.z), Vector3(0.4, 0.0015, 0.012), DEV_PLUM, 0.0, slope)


## Thin posts between the resource slots and a plum-topped one before the dev section.
static func _add_dividers(result: ClayBuilder, slope: Basis) -> void:
	var half_length := HAND_SLOPE_LENGTH * 0.5 - 0.06
	for gap in 5:
		var slot_x := HAND_FIRST_SLOT + HAND_SLOT_PITCH * (gap + 0.5)
		var centre := _on_slope(HAND_SLOPE_LENGTH * 0.5, 0.02)
		var last: bool = gap == 4
		var half := Vector3(0.016 if last else 0.011, 0.022, half_length)
		_bar(result, Vector3(slot_x, centre.y, centre.z), half, DEV_PLUM if last else WALNUT_TOP, 0.008, slope)


static func _octagon(radius: float) -> PackedVector2Array:
	var outline := PackedVector2Array()
	for corner in 8:
		var angle := PI / 8.0 + TAU * corner / 8.0
		outline.append(Vector2(cos(angle), sin(angle)) * radius)
	return outline


static func _build_bell(result: ClayBuilder) -> void:
	result.add_prism(Transform3D.IDENTITY, _octagon(0.36), 0.06, WALNUT, 0.6)
	result.add_prism(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.06, 0.0)), _octagon(0.31), 0.03, WALNUT_TOP, 0.7)
	var lift := Transform3D(Basis.IDENTITY, Vector3(0.0, BELL_BASE_HEIGHT, 0.0))
	var dome := PackedVector2Array([Vector2(0.28, 0.0), Vector2(0.25, 0.045), Vector2(0.2, 0.11), Vector2(0.15, 0.2), Vector2(0.09, 0.27), Vector2(0.0, 0.3)])
	result.add_lathe(dome, lift, BRASS, 0.6, 8)
	var lip := PackedVector2Array([Vector2(0.295, 0.0), Vector2(0.295, 0.02), Vector2(0.27, 0.03)])
	result.add_lathe(lip, lift, BRASS_DARK, 0.6, 8)
	var knob := Transform3D(Basis.IDENTITY.scaled(Vector3(0.05, 0.04, 0.05)), Vector3(0.0, BELL_BASE_HEIGHT + 0.325, 0.0))
	result.add_sphere(knob, BRASS_LIGHT, 0.9, 6)


static func _build_bell_cover(result: ClayBuilder) -> void:
	_bar(result, Vector3(0.0, 0.2, 0.0), Vector3(0.33, 0.2, 0.33), WALNUT)
	_bar(result, Vector3(0.0, 0.24, 0.0), Vector3(0.337, 0.012, 0.337), WALNUT_GROOVE, 0.0)
	result.add_pyramid(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.4, 0.0)), 0.33, 0.33, 0.1, WALNUT_TOP, 0.9)
	_bar(result, Vector3(0.0, 0.53, 0.0), Vector3(0.04, 0.03, 0.04), BRASS, 0.01)


## Walnut board on two leaning posts with feet; a brass line frames the dark text field.
static func _build_sign(result: ClayBuilder) -> void:
	var lean := _sign_lean()
	var middle := SIGN_BOARD_BOTTOM + SIGN_HALF_HEIGHT
	for side in [-1.0, 1.0]:
		var post_x: float = side * (SIGN_HALF_WIDTH - 0.25)
		_bar(result, lean * Vector3(post_x, 0.5, -0.075), Vector3(0.045, 0.5, 0.04), WALNUT_TOP, 0.012, lean)
		_bar(result, Vector3(post_x, 0.025, -0.03), Vector3(0.1, 0.025, 0.2), WALNUT, 0.012)
	_bar(result, lean * Vector3(0.0, middle, 0.0), Vector3(SIGN_HALF_WIDTH, SIGN_HALF_HEIGHT, SIGN_HALF_THICKNESS), WALNUT, 0.012, lean)
	var face := SIGN_HALF_THICKNESS + 0.002
	_bar(result, lean * Vector3(SIGN_TEXT_X, middle, face), Vector3(SIGN_TEXT_WIDTH * 0.5, SIGN_TEXT_HEIGHT * 0.5, 0.003), WALNUT_GROOVE, 0.0, lean)
	for side in [-1.0, 1.0]:
		var line_y: float = middle + side * (SIGN_HALF_HEIGHT - 0.035)
		_bar(result, lean * Vector3(0.0, line_y, face), Vector3(SIGN_HALF_WIDTH - 0.04, 0.007, 0.004), BRASS, 0.0, lean)


static func _build_sign_tab(result: ClayBuilder) -> void:
	var lean := _sign_lean()
	var middle := SIGN_BOARD_BOTTOM + SIGN_HALF_HEIGHT
	var half := Vector3(0.2, SIGN_TEXT_HEIGHT * 0.5, 0.012)
	_bar(result, lean * Vector3(SIGN_TAB_X, middle, SIGN_HALF_THICKNESS + 0.012), half, TAB_CLAY, 0.01, lean)
