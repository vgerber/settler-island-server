class_name SeatStationArt
extends RefCounted
## The fixtures of an opponent's seat station (`doc/design/table-ui-style.md`): name plate, chips, card holder,
## knight shield, mini supply rack, answer tokens and the award board. Walnut, brass and clay in the ClayBuilder
## style; parts that carry the seat colour are light grey and meant for `ClayMaterials.piece(seat)`.
## A station is laid out in its own frame: origin at the centre of the seat stand's top, +z toward the island, +x
## along the stand. The `*_OFFSET` constants and the `*_slot` functions give every part's place in that frame, so
## the board only rotates the frame to the seat. Each mesh rests on y = 0 of its own origin.

const WALNUT := Color("#5A3E2A")
const WALNUT_TOP := Color("#7B5634")
const WALNUT_GROOVE := Color("#3F2B1A")
const LIGHT_WOOD := Color("#B58A5A")
const BRASS := Color("#C9A46A")
const BRASS_LIGHT := Color("#E8C77C")
const BRASS_DARK := Color("#8E6A28")
const POINTS_GOLD := Color("#F3C54A")
const DEV_PLUM := Color("#5B4378")
const CREAM := Color("#F3EADB")
const INK := Color("#231C17")
## Light grey the seat tint multiplies.
const SEAT_GREY := Color(0.94, 0.94, 0.94)

const BEVEL := 0.012

## Token kinds.
const WAITING := "waiting"
const ACCEPTED := "accepted"
const DECLINED := "declined"
const OFFERING := "offering"
const DISCARD := "discard"
## Piece kinds of the mini supply.
const ROAD := "road"
const SETTLEMENT := "settlement"
const CITY := "city"
## Award kinds.
const LONGEST_ROAD := "longest_road"
const LARGEST_ARMY := "largest_army"

## The seat stand top (`TableArt`: the moulding reaches 0.137); parts that stand on it start here.
const STAND_TOP := 0.137

## Name plate: a slanted desk whose face looks at a camera pitched at 55 degrees.
const PLATE_HALF_WIDTH := 0.6
const PLATE_HALF_DEPTH := 0.12
const PLATE_TILT := deg_to_rad(35.0)
const PLATE_RISE := 0.1
const PLATE_SURFACE := 0.05
const PLATE_OFFSET := Vector3(0.0, 0.0, 0.42)
## Plate-local x of the name label, the points chip and the answer token.
const PLATE_LABEL_X := -0.13
const PLATE_CHIP_X := 0.31
const PLATE_TOKEN_X := 0.49
const PLATE_STRIPE_X := -0.52

## Chips: a hexagon of this circumradius; the digit label floats `CHIP_TOP` above the chip base.
const CHIP_RADIUS := 0.09
const CHIP_TOP := 0.042

## Card holder and cards (`CardArt` backs, scaled to `CARD_SCALE` on the holder).
const HOLDER_OFFSET := Vector3(0.0, STAND_TOP, -0.1)
const HOLDER_HALF_WIDTH := 0.86
const HOLDER_FLOOR := 0.05
const CARD_SCALE := 0.62
const CARD_LEAN := deg_to_rad(62.0)
const CARD_PITCH := 0.105
const CARD_FAN := deg_to_rad(4.0)
const CARD_LAYER_LIFT := 0.01
const HAND_CENTRE_X := -0.3
const DEV_CENTRE_X := 0.56
const DEV_PITCH := 0.1

## Chips on the stand: the hand count at the left end of the ledge, the dev count at the right.
const COUNT_CHIP_OFFSET := Vector3(-0.78, STAND_TOP, 0.2)
const DEV_CHIP_OFFSET := Vector3(0.56, STAND_TOP, 0.2)
const SHIELD_ROW_OFFSET := Vector3(-0.28, STAND_TOP, 0.2)
const SHIELD_PITCH := 0.15

## Mini supply rack, on the table in front of the stand.
const RACK_OFFSET := Vector3(0.0, 0.0, 0.98)
const RACK_HALF := Vector3(0.98, 0.0, 0.3)
const RACK_FLOOR := 0.05
const SUPPLY_SCALE := 0.6
const ROAD_COLUMN_X := [-0.7, -0.3]
const ROAD_ROW_Z := [-0.15, -0.05, 0.05, 0.15]
const ROADS_PER_LAYER := 8
const ROAD_LAYER_LIFT := 0.054
const CITY_COLUMN_X := [0.2, 0.7]
const CITY_ROW_Z := [-0.18, 0.0]
const SETTLEMENT_X := [0.1, 0.28, 0.46, 0.64, 0.82]
const SETTLEMENT_Z := 0.2

## Tokens: round clay discs.
const TOKEN_RADIUS := 0.06
const TOKEN_HEIGHT := 0.03
const SYMBOL_LIFT := 0.006

## Award board.
const BOARD_HALF := Vector3(0.78, 0.03, 0.4)
const SOCKET_X := 0.37
const SOCKET_Z := -0.06
const SOCKET_INNER := AwardArt.RADIUS + 0.02
const SOCKET_OUTER := SOCKET_INNER + 0.05
const LABEL_STRIP_Z := 0.32

static var _cache: Dictionary = {}


## The plate stands on its own legs and tilts toward the camera; the seat stripe is `name_plate_stripe`.
static func name_plate() -> ArrayMesh:
	return _mesh("name_plate", _build_name_plate)


## Light grey stripe on the plate's left, tint with `ClayMaterials.piece(seat)`.
static func name_plate_stripe() -> ArrayMesh:
	return _mesh("name_plate_stripe", _build_plate_stripe)


## The plate's frame at its tilted surface: the origin sits on the plate at plate-local `x`, y is the plate normal.
static func plate_surface(plate_local_x: float) -> Transform3D:
	var tilt := Basis(Vector3.RIGHT, PLATE_TILT)
	var local := Vector3(plate_local_x, PLATE_SURFACE, 0.0)
	return Transform3D(tilt, PLATE_OFFSET + Vector3(0.0, PLATE_RISE, 0.0) + tilt * local)


## A Label3D laid on a frame whose y axis is the surface normal (`plate_surface`, a chip's frame).
static func label_basis() -> Basis:
	return Basis(Vector3.RIGHT, -PI * 0.5)


static func points_chip() -> ArrayMesh:
	return _mesh("points_chip", _build_chip.bind(POINTS_GOLD))


static func count_chip() -> ArrayMesh:
	return _mesh("count_chip", _build_chip.bind(Palette.CHIP_RIM))


static func dev_count_chip() -> ArrayMesh:
	return _mesh("dev_count_chip", _build_chip.bind(DEV_PLUM))


## Walnut ledge with a back lip, a brass divider between the hand and the development cards.
static func card_holder() -> ArrayMesh:
	return _mesh("card_holder", _build_card_holder)


## The card back of `CardArt`, lying flat with its back up.
static func card_back() -> ArrayMesh:
	return CardArt.card_back()


## The development card back of `CardArt`, plum.
static func dev_card_back() -> ArrayMesh:
	return CardArt.dev_back()


## Place of hand card `index` (0 to 7) relative to the holder: leaning against the back lip, fanned, later cards on top.
static func card_slot(index: int) -> Transform3D:
	return _card_transform(HAND_CENTRE_X + (index - 3.5) * CARD_PITCH, index, (index - 3.5) * CARD_FAN)


## Place of development card `index` (0 to 2) relative to the holder.
static func dev_slot(index: int) -> Transform3D:
	return _card_transform(DEV_CENTRE_X + (index - 1.0) * DEV_PITCH, index, (index - 1.0) * CARD_FAN * 2.0)


## Light grey clay shield lying flat, pointing to +z; tint with `ClayMaterials.piece(seat)`.
static func knight_shield() -> ArrayMesh:
	return _mesh("knight_shield", _build_shield)


## Station-frame place of shield `index`, tilted like the plate.
static func shield_slot(index: int) -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, PLATE_TILT), SHIELD_ROW_OFFSET + Vector3(index * SHIELD_PITCH, 0.0, 0.0))


## Walnut rack with a groove for every piece; fill it with `PieceArt` meshes at `supply_slot`.
static func mini_supply() -> ArrayMesh:
	return _mesh("mini_supply", _build_mini_supply)


## Place of supply piece `index` of `kind` relative to the rack, at `SUPPLY_SCALE`. Roads fill two layers.
static func supply_slot(kind: String, index: int) -> Transform3D:
	var scaled := Basis.IDENTITY.scaled(Vector3.ONE * SUPPLY_SCALE)
	return Transform3D(scaled, _supply_position(kind, index))


## Round clay disc of `kind` (`WAITING`, `ACCEPTED`, `DECLINED`, `OFFERING`, `DISCARD`) with a raised symbol.
static func token(kind: String) -> ArrayMesh:
	return _mesh("token_" + kind, _build_token.bind(kind))


## Walnut board with two brass sockets (road left, army right) and a light strip under each for its label.
static func award_board() -> ArrayMesh:
	return _mesh("award_board", _build_award_board)


## The plaque is the award medal (`AwardArt`), so the board and the plate show the same object.
static func award_plaque(kind: String) -> ArrayMesh:
	return AwardArt.road() if kind == LONGEST_ROAD else AwardArt.army()


## Board-local place of the award `kind` resting in its socket.
static func award_socket(kind: String) -> Transform3D:
	var side := -1.0 if kind == LONGEST_ROAD else 1.0
	return Transform3D(Basis.IDENTITY, Vector3(side * SOCKET_X, BOARD_HALF.y * 2.0 + 0.002, SOCKET_Z))


## Board-local place of the label strip under the award `kind`; text lies flat on it.
static func award_label(kind: String) -> Transform3D:
	var side := -1.0 if kind == LONGEST_ROAD else 1.0
	return Transform3D(Basis.IDENTITY, Vector3(side * SOCKET_X, BOARD_HALF.y * 2.0 + 0.0045, LABEL_STRIP_Z))


static func _mesh(key: String, build: Callable) -> ArrayMesh:
	if not _cache.has(key):
		var result := ClayBuilder.new()
		build.call(result)
		_cache[key] = result.to_mesh()
	return _cache[key]


static func _at(position: Vector3, basis := Basis.IDENTITY) -> Transform3D:
	return Transform3D(basis, position)


## A flat bar of `width` from `start` to `end` in the xz plane at height `y`, `thickness` tall.
static func _bar(result: ClayBuilder, start: Vector2, end: Vector2, width: float, y: float, color: Color) -> void:
	var middle := (start + end) * 0.5
	var turn := Basis(Vector3.UP, atan2(-(end.y - start.y), end.x - start.x))
	var half := Vector3(start.distance_to(end) * 0.5 + width * 0.5, SYMBOL_LIFT * 0.5, width * 0.5)
	result.add_box(_at(Vector3(middle.x, y, middle.y), turn), half, color, 1.0)


static func _build_name_plate(result: ClayBuilder) -> void:
	var tilt := _at(Vector3(0.0, PLATE_RISE, 0.0), Basis(Vector3.RIGHT, PLATE_TILT))
	var half := Vector3(PLATE_HALF_WIDTH, PLATE_SURFACE * 0.5, PLATE_HALF_DEPTH)
	result.add_bevelled_box(tilt * _at(Vector3(0.0, half.y, 0.0)), half, BEVEL, WALNUT, 0.7)
	var rim := 0.008
	var bar_y := PLATE_SURFACE + 0.004
	for side in [-1.0, 1.0]:
		var along := tilt * _at(Vector3(0.0, bar_y, side * (PLATE_HALF_DEPTH - rim)))
		result.add_box(along, Vector3(PLATE_HALF_WIDTH - 0.004, 0.004, rim), BRASS, 0.9)
		var across := tilt * _at(Vector3(side * (PLATE_HALF_WIDTH - rim), bar_y, 0.0))
		result.add_box(across, Vector3(rim, 0.004, PLATE_HALF_DEPTH - 2.0 * rim), BRASS_LIGHT, 0.9)
	var back_leg := Vector3(PLATE_HALF_WIDTH - 0.1, 0.085, 0.025)
	result.add_box(_at(Vector3(0.0, back_leg.y, -0.085)), back_leg, WALNUT_GROOVE, 0.6)
	var front_leg := Vector3(PLATE_HALF_WIDTH - 0.1, 0.03, 0.025)
	result.add_box(_at(Vector3(0.0, front_leg.y, 0.075)), front_leg, WALNUT_GROOVE, 0.6)


static func _build_plate_stripe(result: ClayBuilder) -> void:
	var tilt := _at(Vector3(0.0, PLATE_RISE, 0.0), Basis(Vector3.RIGHT, PLATE_TILT))
	var half := Vector3(0.05, 0.004, PLATE_HALF_DEPTH - 0.03)
	result.add_box(tilt * _at(Vector3(PLATE_STRIPE_X, PLATE_SURFACE + 0.004, 0.0)), half, SEAT_GREY, 0.9)


## A hexagonal tile chip: coloured rim, card-stock face.
static func _build_chip(result: ClayBuilder, rim: Color) -> void:
	var outer := PackedVector2Array([Vector2(CHIP_RADIUS, 0.0), Vector2(CHIP_RADIUS, 0.03), Vector2(CHIP_RADIUS - 0.014, CHIP_TOP)])
	result.add_lathe(outer, Transform3D.IDENTITY, ClayPalette.mute(rim), 0.7, 6)
	var face := PackedVector2Array([Vector2(CHIP_RADIUS - 0.014, 0.034), Vector2(CHIP_RADIUS - 0.024, CHIP_TOP + 0.002), Vector2(0.0, CHIP_TOP + 0.002)])
	result.add_lathe(face, Transform3D.IDENTITY, ClayPalette.mute(ClayPalette.CHIP_FACE), 0.95, 6)


static func _build_card_holder(result: ClayBuilder) -> void:
	var half := Vector3(HOLDER_HALF_WIDTH, HOLDER_FLOOR * 0.5, 0.1)
	result.add_bevelled_box(_at(Vector3(0.0, half.y, 0.0)), half, BEVEL, WALNUT, 0.7)
	result.add_box(_at(Vector3(0.0, HOLDER_FLOOR + 0.0015, 0.005)), Vector3(HOLDER_HALF_WIDTH - 0.04, 0.0015, 0.07), LIGHT_WOOD, 1.0)
	var lip_half := Vector3(HOLDER_HALF_WIDTH, 0.03, 0.014)
	result.add_bevelled_box(_at(Vector3(0.0, HOLDER_FLOOR + lip_half.y - 0.01, -0.086)), lip_half, 0.008, WALNUT_TOP, 0.7)
	var front_half := Vector3(HOLDER_HALF_WIDTH - 0.01, 0.012, 0.01)
	result.add_box(_at(Vector3(0.0, HOLDER_FLOOR + front_half.y, 0.088)), front_half, WALNUT_TOP, 0.8)
	var divider := Vector3(0.008, 0.02, 0.085)
	result.add_box(_at(Vector3(0.3, HOLDER_FLOOR + divider.y, -0.005)), divider, BRASS, 0.8)


## A card leaning back against the lip at x, fanned by `roll` around its own normal, layered by `layer`.
static func _card_transform(x: float, layer: int, roll: float) -> Transform3D:
	var basis := Basis(Vector3.RIGHT, CARD_LEAN) * Basis(Vector3.UP, -roll)
	var scaled := basis.scaled_local(Vector3.ONE * CARD_SCALE)
	var foot := Vector3(x, HOLDER_FLOOR + 0.004, 0.035)
	var bottom_edge := scaled * Vector3(0.0, 0.0, CardArt.HALF.y)
	return Transform3D(scaled, foot - bottom_edge + basis * Vector3(0.0, layer * CARD_LAYER_LIFT, 0.0))


static func _build_shield(result: ClayBuilder) -> void:
	var outline := PackedVector2Array([Vector2(-0.055, -0.05), Vector2(0.055, -0.05), Vector2(0.055, 0.005), Vector2(0.0, 0.07), Vector2(-0.055, 0.005)])
	var body := ClayPalette.shade(SEAT_GREY, 0.85)
	result.add_prism(Transform3D.IDENTITY, outline, 0.026, body, 0.75)
	var inner := PackedVector2Array()
	for corner in outline:
		inner.append(corner * 0.7)
	result.add_prism(_at(Vector3(0.0, 0.026, 0.0)), inner, 0.006, SEAT_GREY, 1.0)
	var cross := ClayPalette.shade(SEAT_GREY, 0.5)
	result.add_box(_at(Vector3(0.0, 0.035, -0.004)), Vector3(0.007, 0.003, 0.034), cross, 1.0)
	result.add_box(_at(Vector3(0.0, 0.035, -0.012)), Vector3(0.026, 0.003, 0.007), cross, 1.0)


static func _supply_position(kind: String, index: int) -> Vector3:
	var floor_top := RACK_FLOOR + 0.002
	match kind:
		ROAD:
			var layer := index / ROADS_PER_LAYER
			var rest := index % ROADS_PER_LAYER
			var x: float = ROAD_COLUMN_X[rest / ROAD_ROW_Z.size()]
			return Vector3(x, floor_top + layer * ROAD_LAYER_LIFT, ROAD_ROW_Z[rest % ROAD_ROW_Z.size()])
		CITY:
			return Vector3(CITY_COLUMN_X[index % 2], floor_top, CITY_ROW_Z[index / 2])
		_:
			return Vector3(SETTLEMENT_X[index], floor_top, SETTLEMENT_Z)


static func _build_mini_supply(result: ClayBuilder) -> void:
	var floor_half := Vector3(RACK_HALF.x, RACK_FLOOR * 0.5, RACK_HALF.z)
	result.add_bevelled_box(_at(Vector3(0.0, floor_half.y, 0.0)), floor_half, BEVEL, WALNUT, 0.7)
	var rim_height := 0.03
	var long_half := Vector3(RACK_HALF.x, rim_height * 0.5, 0.012)
	var short_half := Vector3(0.012, rim_height * 0.5, RACK_HALF.z - 0.024)
	for side in [-1.0, 1.0]:
		result.add_box(_at(Vector3(0.0, RACK_FLOOR + rim_height * 0.5, side * (RACK_HALF.z - 0.012))), long_half, WALNUT_TOP, 0.75)
		result.add_box(_at(Vector3(side * (RACK_HALF.x - 0.012), RACK_FLOOR + rim_height * 0.5, 0.0)), short_half, WALNUT_TOP, 0.75)
	result.add_box(_at(Vector3(-0.06, RACK_FLOOR + rim_height * 0.5, 0.0)), Vector3(0.01, rim_height * 0.5, RACK_HALF.z - 0.024), BRASS, 0.8)
	_add_grooves(result)


## A dark groove under every supply piece; roads and cities are wider, settlements narrower.
static func _add_grooves(result: ClayBuilder) -> void:
	var groove := ClayPalette.shade(WALNUT_GROOVE, 0.9)
	var grooves := [[ROAD, 8, Vector3(0.2, 0.0015, 0.04)], [CITY, 4, Vector3(0.18, 0.0015, 0.09)], [SETTLEMENT, 5, Vector3(0.075, 0.0015, 0.065)]]
	for entry: Array in grooves:
		for index in entry[1]:
			var position := _supply_position(entry[0], index)
			position.y = RACK_FLOOR + 0.0015
			result.add_box(_at(position), entry[2], groove, 1.0)


static func _build_token(result: ClayBuilder, kind: String) -> void:
	var disc := PackedVector2Array([
		Vector2(TOKEN_RADIUS, 0.0), Vector2(TOKEN_RADIUS, TOKEN_HEIGHT * 0.85), Vector2(TOKEN_RADIUS - 0.01, TOKEN_HEIGHT), Vector2(0.0, TOKEN_HEIGHT)
	])
	var palette := _token_colors(kind)
	result.add_lathe(disc, Transform3D.IDENTITY, palette[0], 0.75, 8)
	var y := TOKEN_HEIGHT + SYMBOL_LIFT * 0.5
	var ink: Color = palette[1]
	match kind:
		WAITING:
			for x in [-0.03, 0.0, 0.03]:
				result.add_box(_at(Vector3(x, y, 0.0)), Vector3(0.011, SYMBOL_LIFT * 0.5, 0.011), ink, 1.0)
		ACCEPTED:
			_bar(result, Vector2(-0.032, 0.0), Vector2(-0.008, 0.022), 0.017, y, ink)
			_bar(result, Vector2(-0.008, 0.022), Vector2(0.032, -0.026), 0.017, y, ink)
		DECLINED:
			_bar(result, Vector2(-0.026, -0.026), Vector2(0.026, 0.026), 0.017, y, ink)
			_bar(result, Vector2(-0.026, 0.026), Vector2(0.026, -0.026), 0.017, y, ink)
		OFFERING:
			_add_scale(result, y, ink)
		DISCARD:
			_bar(result, Vector2(-0.016, -0.012), Vector2(-0.016, 0.014), 0.026, y, ink)
			_bar(result, Vector2(0.018, -0.002), Vector2(0.018, 0.024), 0.026, y, ClayPalette.shade(ink, 0.8))


static func _add_scale(result: ClayBuilder, y: float, ink: Color) -> void:
	_bar(result, Vector2(0.0, -0.032), Vector2(0.0, 0.034), 0.012, y, ink)
	_bar(result, Vector2(-0.038, -0.02), Vector2(0.038, -0.02), 0.011, y, ink)
	_bar(result, Vector2(-0.044, 0.014), Vector2(-0.026, 0.014), 0.014, y, ink)
	_bar(result, Vector2(0.026, 0.014), Vector2(0.044, 0.014), 0.014, y, ink)
	_bar(result, Vector2(-0.016, 0.034), Vector2(0.016, 0.034), 0.01, y, ink)


## [disc colour, symbol colour] of a token kind.
static func _token_colors(kind: String) -> Array[Color]:
	match kind:
		WAITING:
			return [LIGHT_WOOD, INK]
		ACCEPTED:
			return [ClayPalette.BUSH_GREEN, CREAM]
		DECLINED:
			return [Palette.DANGER, CREAM]
		OFFERING:
			return [BRASS, INK]
		_:
			return [ClayPalette.STONE_GREY, CREAM]


static func _build_award_board(result: ClayBuilder) -> void:
	result.add_bevelled_box(_at(Vector3(0.0, BOARD_HALF.y, 0.0)), BOARD_HALF, 0.016, WALNUT, 0.7)
	var top := BOARD_HALF.y * 2.0
	var ring := PackedVector2Array([
		Vector2(SOCKET_OUTER, 0.0), Vector2(SOCKET_OUTER, 0.026), Vector2(SOCKET_OUTER - 0.016, 0.032),
		Vector2(SOCKET_INNER + 0.01, 0.032), Vector2(SOCKET_INNER, 0.02), Vector2(SOCKET_INNER, 0.0),
	])
	var floor_profile := PackedVector2Array([Vector2(SOCKET_INNER, 0.001), Vector2(0.0, 0.001)])
	for side in [-1.0, 1.0]:
		var centre := Vector3(side * SOCKET_X, top, SOCKET_Z)
		result.add_lathe(ring, _at(centre), BRASS, 0.75, 8)
		result.add_lathe(floor_profile, _at(centre), WALNUT_GROOVE, 0.9, 8)
		var strip := Vector3(0.3, 0.0015, 0.05)
		result.add_box(_at(Vector3(side * SOCKET_X, top + strip.y, LABEL_STRIP_Z)), strip, WALNUT_TOP, 0.95)
