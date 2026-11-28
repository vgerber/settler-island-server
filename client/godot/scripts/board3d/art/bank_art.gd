class_name BankArt
extends RefCounted
## Table fixtures around the bank and the menus: the bank rack with six card bays, the trade token, the trade mat
## and its wood buttons, the settings board with its sliders, the history ledger and the game-over sign. Style
## and budgets: doc/design/table-ui-style.md. Every mesh rests on y = 0, faces +z and is built from `ClayBuilder`
## primitives only; the `*_point` helpers give the spots where cards, knobs and `Label3D` texts go.

enum ButtonKind { WOOD, TEAL, EMBER }

const WALNUT := Color("#5A3E2A")
const WALNUT_TOP := Color("#7B5634")
const WALNUT_DARK := Color("#3F2B1A")
const LIGHT_WOOD := Color("#B58A5A")
const BRASS := Color("#C9A46A")
const BRASS_LIGHT := Color("#E8C77C")
const BRASS_DARK := Color("#8E6A28")
const FELT := Color("#2F5D52")
const DEV_PLUM := Color("#5B4378")
const TEAL := Color("#1E6B63")
const EMBER := Color("#A3332A")

## Bank rack: three columns by two rows of bays (clay, wood, sheep, wheat, ore, development deck).
const RACK_COLUMNS := 3
const BAY_COUNT := 6
const BAY_HALF_X := 0.22
const BAY_HALF_Z := 0.29
const WALL_HALF_X := 0.04
const WALL_HALF_Z := 0.05
const RACK_PITCH_X := 2.0 * (BAY_HALF_X + WALL_HALF_X)
const RACK_PITCH_Z := 2.0 * (BAY_HALF_Z + WALL_HALF_Z)
const RACK_HALF_WIDTH := RACK_PITCH_X * 1.5 + WALL_HALF_X
const RACK_HALF_DEPTH := RACK_PITCH_Z + WALL_HALF_Z
const RACK_BASE_HEIGHT := 0.03
const BAY_INLAY := 0.006
## Where the lowest card of a pile rests.
const BAY_FLOOR := RACK_BASE_HEIGHT + BAY_INLAY
const RACK_WALL_HEIGHT := 0.1
const MARKER_RADIUS := 0.13

## Trade token: a clay disc.
const TOKEN_RADIUS := 0.06
const TOKEN_HEIGHT := 0.03

## Trade mat: the felt top is at `MAT_FELT`, the border rises to `MAT_BORDER`.
const MAT_HALF_WIDTH := 1.0
const MAT_HALF_DEPTH := 0.62
const MAT_FELT := 0.03
const MAT_BORDER := 0.05
const MAT_BORDER_WIDTH := 0.06
const MAT_HALF_X := 0.52
const MAT_CARD_Z := -0.12
const MAT_LABEL_Z := -0.48
const MAT_BUTTON_Z := 0.38
const MAT_BUTTON_X := 0.5

## Wood button: walnut foot and a tinted cap; labels lie on `BUTTON_TOP`.
const BUTTON_HALF_WIDTH := 0.33
const BUTTON_HALF_DEPTH := 0.13
const BUTTON_FOOT := 0.05
const BUTTON_TOP := 0.11

## Settings board lying on the table: a title row, three slider rows, two toggle rows (front to back by z).
const BOARD_HALF_WIDTH := 1.0
const BOARD_HALF_DEPTH := 0.74
const BOARD_TOP := 0.06
const BOARD_TITLE_Z := -0.55
const BOARD_ROW_Z: Array[float] = [-0.3, -0.08, 0.14, 0.38, 0.58]
const BOARD_LABEL_X := -0.9
const TRACK_CENTRE_X := 0.42
const TRACK_HALF_LENGTH := 0.4
const TRACK_TOP := BOARD_TOP + 0.008
const KNOB_MIN_X := 0.08
const KNOB_MAX_X := 0.76
const TOGGLE_OFF_X := 0.1
const TOGGLE_ON_X := 0.3

## Ledger: each page leans `LEDGER_TILT` toward its outer edge, so text reads at the table pitch.
const PAGE_HALF_WIDTH := 0.3
const PAGE_HALF_DEPTH := 0.4
const LEDGER_TILT := 0.07
const LEDGER_PAGE_TOP := 0.07
const CLOSED_COVER_TOP := 0.108

## Game-over sign: a board on two posts, tipped back by `SIGN_TILT` so it faces the camera.
const SIGN_HALF_WIDTH := 0.85
const SIGN_HALF_HEIGHT := 0.28
const SIGN_HALF_THICKNESS := 0.035
const SIGN_CENTRE_HEIGHT := 0.8
const SIGN_TILT := 0.22

static var _meshes: Dictionary = {}


## Walnut rack of six bays; light-wood floors carry a resource-coloured diamond (visible when the bay is empty)
## and a tab of the same colour on the wall behind the bay.
static func bank_rack() -> ArrayMesh:
	return _mesh("rack", _build_rack)


## Bay `index` in `bay_resource` order: row-major, three per row.
static func bay_centre(index: int) -> Vector3:
	var column := index % RACK_COLUMNS
	var row := index / RACK_COLUMNS
	return Vector3((column - 1) * RACK_PITCH_X, 0.0, (row - 0.5) * RACK_PITCH_Z)


## Where the lowest card of the pile in bay `index` rests, relative to the rack origin.
static func pile_point(index: int) -> Vector3:
	return bay_centre(index) + Vector3(0.0, BAY_FLOOR, 0.0)


## The resource of bay `index`, or "" for the development deck.
static func bay_resource(index: int) -> String:
	return SiResource.VALUES[index] if index < SiResource.VALUES.size() else ""


static func bay_color(index: int) -> Color:
	if bay_resource(index).is_empty():
		return DEV_PLUM
	return ClayPalette.mute(Palette.resource_color(bay_resource(index)))


## A brass and light-wood disc with a raised balance scale; it opens trading.
static func trade_token() -> ArrayMesh:
	return _mesh("token", _build_token)


## Felt mat with a light-wood border, a frame per half (`gives` left, `you give` right) and a brass arrow.
static func trade_mat() -> ArrayMesh:
	return _mesh("mat", _build_mat)


## Card spot of a mat half: -1 is the left (`gives`) half, +1 the right (`you give`) half.
static func mat_card_point(side: int) -> Vector3:
	return Vector3(side * MAT_HALF_X, MAT_FELT, MAT_CARD_Z)


static func mat_button_point(side: int) -> Vector3:
	return Vector3(side * MAT_BUTTON_X, MAT_BORDER, MAT_BUTTON_Z)


## A chunky push button (Accept, Decline, Confirm, Play again); the cap is tinted by `kind`.
static func wood_button(kind := ButtonKind.WOOD) -> ArrayMesh:
	if not _meshes.has("button%d" % kind):
		var result := ClayBuilder.new()
		_build_button(result, kind)
		_meshes["button%d" % kind] = result.to_mesh()
	return _meshes["button%d" % kind]


## Walnut board with three slider tracks and two toggle slots; the knobs are separate meshes.
static func settings_board() -> ArrayMesh:
	return _mesh("settings", _build_settings)


## The movable knob of a slider (origin at its base centre); put it at `slider_point`.
static func slider_knob() -> ArrayMesh:
	return _mesh("knob", _build_knob)


## The movable lever of a toggle; put it at `toggle_point`.
static func toggle_knob() -> ArrayMesh:
	return _mesh("toggle_knob", _build_toggle_knob)


## Knob position of slider `index` (0 to 2) at `value` in 0..1, relative to the board origin.
static func slider_point(index: int, value: float) -> Vector3:
	return Vector3(lerpf(KNOB_MIN_X, KNOB_MAX_X, clampf(value, 0.0, 1.0)), TRACK_TOP, BOARD_ROW_Z[index])


## Lever position of toggle `index` (0 or 1).
static func toggle_point(index: int, enabled: bool) -> Vector3:
	return Vector3(TOGGLE_ON_X if enabled else TOGGLE_OFF_X, TRACK_TOP, BOARD_ROW_Z[3 + index])


## A history book lying on the table, closed (title on the cover) or open (a page of lines on each side).
static func ledger(open := false) -> ArrayMesh:
	return _mesh("ledger_open" if open else "ledger_closed", _build_open_ledger if open else _build_closed_ledger)


## Page top of an open ledger: origin at the page centre, local +y along the page normal. Turn a `Label3D`
## flat with `Basis(Vector3.RIGHT, -PI / 2)` inside it. `side` is -1 (left) or +1 (right).
static func ledger_page_transform(side: int) -> Transform3D:
	var top := Vector3(side * (PAGE_HALF_WIDTH + 0.02), LEDGER_PAGE_TOP + 0.002, 0.0)
	return _page_lean(side) * Transform3D(Basis.IDENTITY, top)


## Standing sign with a walnut board and brass rim; texts go on `sign_face`.
static func title_sign() -> ArrayMesh:
	return _mesh("sign", _build_sign)


## Centre of the board face, local +z pointing out of it.
static func sign_face() -> Transform3D:
	var face := Vector3(0.0, 0.0, SIGN_HALF_THICKNESS + 0.002)
	return _sign_lean() * Transform3D(Basis.IDENTITY, face)


static func _mesh(key: String, build: Callable) -> ArrayMesh:
	if not _meshes.has(key):
		var result := ClayBuilder.new()
		build.call(result)
		_meshes[key] = result.to_mesh()
	return _meshes[key]


static func _box(result: ClayBuilder, centre: Vector3, half: Vector3, color: Color, ao_floor := 0.7) -> void:
	result.add_box(Transform3D(Basis.IDENTITY, centre), half, color, ao_floor)


static func _bevelled(
	result: ClayBuilder, centre: Vector3, half: Vector3, bevel: float, color: Color, ao_floor := 0.7
) -> void:
	result.add_bevelled_box(Transform3D(Basis.IDENTITY, centre), half, bevel, color, ao_floor)


static func _diamond(radius: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(0.0, -radius), Vector2(radius, 0.0), Vector2(0.0, radius), Vector2(-radius, 0.0)])


static func _build_rack(result: ClayBuilder) -> void:
	var half_height := RACK_BASE_HEIGHT * 0.5
	_bevelled(result, Vector3(0.0, half_height, 0.0), Vector3(RACK_HALF_WIDTH, half_height, RACK_HALF_DEPTH), 0.012, WALNUT_DARK, 0.6)
	for index in BAY_COUNT:
		_add_bay(result, index)
	for row in 3:
		var wall_centre := Vector3(0.0, RACK_WALL_HEIGHT * 0.48, (row - 1) * RACK_PITCH_Z)
		var wall_half := Vector3(RACK_HALF_WIDTH, RACK_WALL_HEIGHT * 0.48, WALL_HALF_Z)
		_bevelled(result, wall_centre, wall_half, 0.012, WALNUT, 0.6)
	for column in 4:
		var wall_centre := Vector3((column - 1.5) * RACK_PITCH_X, RACK_WALL_HEIGHT * 0.5, 0.0)
		var wall_half := Vector3(WALL_HALF_X, RACK_WALL_HEIGHT * 0.5, RACK_HALF_DEPTH)
		_bevelled(result, wall_centre, wall_half, 0.012, WALNUT_TOP, 0.6)


## Floor, resource diamond with a dark inlay line, and the tab on the wall behind the bay.
static func _add_bay(result: ClayBuilder, index: int) -> void:
	var centre := bay_centre(index)
	var floor_centre := centre + Vector3(0.0, RACK_BASE_HEIGHT + BAY_INLAY * 0.5, 0.0)
	_box(result, floor_centre, Vector3(BAY_HALF_X, BAY_INLAY * 0.5, BAY_HALF_Z), LIGHT_WOOD, 0.85)
	var inlay := Transform3D(Basis.IDENTITY, centre + Vector3(0.0, BAY_FLOOR, 0.0))
	result.add_prism(inlay, _diamond(MARKER_RADIUS + 0.025), 0.003, WALNUT_DARK, 1.0)
	var marker := Transform3D(Basis.IDENTITY, centre + Vector3(0.0, BAY_FLOOR + 0.003, 0.0))
	result.add_prism(marker, _diamond(MARKER_RADIUS), 0.004, bay_color(index), 1.0)
	var tab_centre := centre + Vector3(0.0, RACK_WALL_HEIGHT * 0.96 + 0.004, -(BAY_HALF_Z + WALL_HALF_Z))
	_box(result, tab_centre, Vector3(0.08, 0.004, 0.026), bay_color(index), 1.0)


static func _build_token(result: ClayBuilder) -> void:
	var profile := PackedVector2Array(
		[Vector2(0.0, 0.0), Vector2(TOKEN_RADIUS, 0.0), Vector2(TOKEN_RADIUS, 0.022), Vector2(TOKEN_RADIUS - 0.008, TOKEN_HEIGHT), Vector2(0.0, TOKEN_HEIGHT)]
	)
	result.add_lathe(profile, Transform3D.IDENTITY, LIGHT_WOOD, 0.75, 8)
	_box(result, Vector3(0.0, TOKEN_HEIGHT + 0.012, 0.0), Vector3(0.005, 0.012, 0.005), BRASS_DARK, 0.9)
	_box(result, Vector3(0.0, TOKEN_HEIGHT + 0.026, 0.0), Vector3(0.04, 0.004, 0.005), BRASS_LIGHT, 1.0)
	for side in [-1.0, 1.0]:
		_box(result, Vector3(side * 0.036, TOKEN_HEIGHT + 0.0485, 0.0), Vector3(0.0025, 0.0075, 0.0025), BRASS_DARK, 0.9)
		_box(result, Vector3(side * 0.036, TOKEN_HEIGHT + 0.008, 0.0), Vector3(0.017, 0.003, 0.014), BRASS, 0.9)


static func _build_mat(result: ClayBuilder) -> void:
	_box(result, Vector3(0.0, MAT_FELT * 0.5, 0.0), Vector3(MAT_HALF_WIDTH, MAT_FELT * 0.5, MAT_HALF_DEPTH), FELT, 0.8)
	_add_mat_border(result)
	for side in [-1, 1]:
		_add_half_frame(result, side)
	_add_mat_arrow(result)


static func _add_mat_border(result: ClayBuilder) -> void:
	var half_height := MAT_BORDER * 0.5
	var border := MAT_BORDER_WIDTH * 0.5
	for side in [-1.0, 1.0]:
		var long_half := Vector3(MAT_HALF_WIDTH, half_height, border)
		_bevelled(result, Vector3(0.0, half_height, side * (MAT_HALF_DEPTH - border)), long_half, 0.012, LIGHT_WOOD, 0.7)
		var short_half := Vector3(border, half_height, MAT_HALF_DEPTH - MAT_BORDER_WIDTH)
		_bevelled(result, Vector3(side * (MAT_HALF_WIDTH - border), half_height, 0.0), short_half, 0.012, ClayPalette.shade(LIGHT_WOOD, 0.92), 0.7)


## A thin darker line rectangle that marks where the cards of one half go.
static func _add_half_frame(result: ClayBuilder, side: int) -> void:
	var line_color := ClayPalette.shade(FELT, 0.7)
	var half_width := 0.38
	var half_depth := 0.28
	var line := 0.007
	var centre := Vector3(side * MAT_HALF_X, MAT_FELT + 0.0015, MAT_CARD_Z)
	for edge in [-1.0, 1.0]:
		_box(result, centre + Vector3(0.0, 0.0, edge * half_depth), Vector3(half_width, 0.0015, line), line_color, 1.0)
		_box(result, centre + Vector3(edge * half_width, 0.0, 0.0), Vector3(line, 0.0015, half_depth), line_color, 1.0)


static func _add_mat_arrow(result: ClayBuilder) -> void:
	var height := MAT_FELT + 0.002
	_box(result, Vector3(-0.05, height + 0.003, MAT_CARD_Z), Vector3(0.07, 0.003, 0.014), BRASS, 1.0)
	var outline := PackedVector2Array([Vector2(0.0, -0.07), Vector2(0.12, 0.0), Vector2(0.0, 0.07)])
	var head := Transform3D(Basis.IDENTITY, Vector3(0.0, height, MAT_CARD_Z))
	result.add_prism(head, outline, 0.006, BRASS, 1.0)


static func _build_button(result: ClayBuilder, kind: ButtonKind) -> void:
	var cap_color := LIGHT_WOOD
	if kind == ButtonKind.TEAL:
		cap_color = TEAL
	if kind == ButtonKind.EMBER:
		cap_color = EMBER
	var foot_half := Vector3(BUTTON_HALF_WIDTH, BUTTON_FOOT * 0.5, BUTTON_HALF_DEPTH)
	_bevelled(result, Vector3(0.0, BUTTON_FOOT * 0.5, 0.0), foot_half, 0.012, WALNUT, 0.6)
	var cap_height := BUTTON_TOP - BUTTON_FOOT
	var cap_half := Vector3(BUTTON_HALF_WIDTH - 0.04, cap_height * 0.5, BUTTON_HALF_DEPTH - 0.035)
	_bevelled(result, Vector3(0.0, BUTTON_FOOT + cap_height * 0.5, 0.0), cap_half, 0.018, cap_color, 0.75)


static func _build_settings(result: ClayBuilder) -> void:
	var half_height := BOARD_TOP * 0.5
	var board_half := Vector3(BOARD_HALF_WIDTH, half_height, BOARD_HALF_DEPTH)
	_bevelled(result, Vector3(0.0, half_height, 0.0), board_half, 0.015, WALNUT_TOP, 0.65)
	_add_board_rim(result)
	_box(result, Vector3(0.0, BOARD_TOP + 0.002, BOARD_TITLE_Z), Vector3(0.88, 0.002, 0.09), WALNUT_DARK, 1.0)
	for index in 3:
		_add_track(result, BOARD_ROW_Z[index])
	for index in 2:
		_add_toggle_slot(result, BOARD_ROW_Z[3 + index])


static func _add_board_rim(result: ClayBuilder) -> void:
	var inset := 0.045
	var line := 0.006
	for edge in [-1.0, 1.0]:
		var depth_centre := Vector3(0.0, BOARD_TOP + 0.002, edge * (BOARD_HALF_DEPTH - inset))
		_box(result, depth_centre, Vector3(BOARD_HALF_WIDTH - inset, 0.002, line), BRASS, 1.0)
		var width_centre := Vector3(edge * (BOARD_HALF_WIDTH - inset), BOARD_TOP + 0.002, 0.0)
		_box(result, width_centre, Vector3(line, 0.002, BOARD_HALF_DEPTH - inset), BRASS, 1.0)


static func _add_track(result: ClayBuilder, row_z: float) -> void:
	_box(result, Vector3(TRACK_CENTRE_X, BOARD_TOP + 0.004, row_z), Vector3(TRACK_HALF_LENGTH, 0.004, 0.02), WALNUT_DARK, 0.9)
	for edge in [-1.0, 1.0]:
		var stop := Vector3(TRACK_CENTRE_X + edge * (TRACK_HALF_LENGTH + 0.012), BOARD_TOP + 0.01, row_z)
		_box(result, stop, Vector3(0.012, 0.01, 0.04), BRASS_DARK, 0.9)


static func _add_toggle_slot(result: ClayBuilder, row_z: float) -> void:
	var slot_centre := (TOGGLE_OFF_X + TOGGLE_ON_X) * 0.5
	_box(result, Vector3(slot_centre, BOARD_TOP + 0.004, row_z), Vector3(0.17, 0.004, 0.04), WALNUT_DARK, 0.9)
	var lit_centre := Vector3(slot_centre + 0.085, BOARD_TOP + 0.009, row_z)
	_box(result, lit_centre, Vector3(0.085, 0.001, 0.028), TEAL, 1.0)


static func _build_knob(result: ClayBuilder) -> void:
	var clay := ClayPalette.BRICK_LIGHT
	_bevelled(result, Vector3(0.0, 0.035, 0.0), Vector3(0.04, 0.035, 0.055), 0.014, clay, 0.7)
	_box(result, Vector3(0.0, 0.07, 0.0), Vector3(0.005, 0.0015, 0.04), ClayPalette.shade(clay, 0.7), 1.0)


static func _build_toggle_knob(result: ClayBuilder) -> void:
	var profile := PackedVector2Array(
		[Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.04, 0.03), Vector2(0.03, 0.04), Vector2(0.0, 0.04)]
	)
	result.add_lathe(profile, Transform3D.IDENTITY, BRASS_LIGHT, 0.7, 7)


static func _page_lean(side: int) -> Transform3D:
	return Transform3D(Basis(Vector3.BACK, side * LEDGER_TILT), Vector3(0.0, 0.02, 0.0))


static func _build_closed_ledger(result: ClayBuilder) -> void:
	var cover := Vector3(0.33, 0.012, 0.43)
	_bevelled(result, Vector3(0.0, 0.012, 0.0), cover, 0.01, WALNUT, 0.6)
	_box(result, Vector3(0.0, 0.054, 0.0), Vector3(PAGE_HALF_WIDTH, 0.03, PAGE_HALF_DEPTH), ClayPalette.CHIP_FACE, 0.75)
	_bevelled(result, Vector3(0.0, 0.096, 0.0), cover, 0.01, WALNUT_TOP, 0.8)
	_bevelled(result, Vector3(-0.315, 0.054, 0.0), Vector3(0.03, 0.054, 0.43), 0.012, WALNUT_DARK, 0.7)
	_box(result, Vector3(0.03, CLOSED_COVER_TOP + 0.003, 0.0), Vector3(0.17, 0.003, 0.09), BRASS, 1.0)
	_box(result, Vector3(0.2, CLOSED_COVER_TOP + 0.002, 0.28), Vector3(0.1, 0.002, 0.012), EMBER, 1.0)
	for end in [-1.0, 1.0]:
		var corner := Vector3(0.3, CLOSED_COVER_TOP + 0.002, end * 0.4)
		_box(result, corner, Vector3(0.028, 0.002, 0.028), BRASS_DARK, 1.0)


static func _build_open_ledger(result: ClayBuilder) -> void:
	_box(result, Vector3(0.0, 0.02, 0.0), Vector3(0.03, 0.02, 0.42), WALNUT_DARK, 0.7)
	for side in [-1, 1]:
		var lean := _page_lean(side)
		var cover := Transform3D(Basis.IDENTITY, Vector3(side * 0.34, 0.012, 0.0))
		result.add_bevelled_box(lean * cover, Vector3(0.33, 0.012, 0.43), 0.01, WALNUT, 0.6)
		var pages := Transform3D(Basis.IDENTITY, Vector3(side * 0.32, 0.046, 0.0))
		result.add_box(lean * pages, Vector3(PAGE_HALF_WIDTH, 0.022, PAGE_HALF_DEPTH), ClayPalette.shade(ClayPalette.CHIP_FACE, 0.9), 0.7)
		var sheet := Transform3D(Basis.IDENTITY, Vector3(side * 0.32, 0.066, 0.0))
		result.add_box(lean * sheet, Vector3(PAGE_HALF_WIDTH - 0.01, 0.002, PAGE_HALF_DEPTH - 0.012), ClayPalette.CHIP_FACE, 1.0)
	var ribbon := Transform3D(Basis.IDENTITY, Vector3(0.05, 0.072, 0.36))
	result.add_box(_page_lean(1) * ribbon, Vector3(0.01, 0.002, 0.1), EMBER, 1.0)


static func _sign_lean() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, -SIGN_TILT), Vector3(0.0, SIGN_CENTRE_HEIGHT, 0.0))


static func _build_sign(result: ClayBuilder) -> void:
	_bevelled(result, Vector3(0.0, 0.025, 0.0), Vector3(0.72, 0.025, 0.15), 0.012, WALNUT_DARK, 0.6)
	for side in [-1.0, 1.0]:
		_bevelled(result, Vector3(side * 0.6, 0.31, 0.03), Vector3(0.04, 0.28, 0.04), 0.012, WALNUT, 0.55)
	var lean := _sign_lean()
	var board := Vector3(SIGN_HALF_WIDTH, SIGN_HALF_HEIGHT, SIGN_HALF_THICKNESS)
	result.add_bevelled_box(lean, board, 0.02, WALNUT_TOP, 0.7)
	_add_sign_rim(result, lean)


static func _add_sign_rim(result: ClayBuilder, lean: Transform3D) -> void:
	var inset := 0.05
	var line := 0.006
	var lift := SIGN_HALF_THICKNESS + 0.0015
	for edge in [-1.0, 1.0]:
		var top_centre := Transform3D(Basis.IDENTITY, Vector3(0.0, edge * (SIGN_HALF_HEIGHT - inset), lift))
		result.add_box(lean * top_centre, Vector3(SIGN_HALF_WIDTH - inset, line, 0.0015), BRASS, 1.0)
		var side_centre := Transform3D(Basis.IDENTITY, Vector3(edge * (SIGN_HALF_WIDTH - inset), 0.0, lift))
		result.add_box(lean * side_centre, Vector3(line, SIGN_HALF_HEIGHT - inset, 0.0015), BRASS, 1.0)
		var stud := Transform3D(Basis.IDENTITY, Vector3(edge * (SIGN_HALF_WIDTH - 0.03), 0.0, lift))
		result.add_box(lean * stud, Vector3(0.012, 0.012, 0.004), BRASS_LIGHT, 1.0)
