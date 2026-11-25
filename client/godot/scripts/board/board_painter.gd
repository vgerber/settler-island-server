class_name BoardPainter
extends RefCounted
## Draws one frame of the board onto its `Board` control; all sizes are in hex units scaled by
## `Board.hex_size`, so the drawing follows the fitted rect.

const SEA := Color("#1f5a85")
const COAST := Color("#2f74a5")
const OUTLINE := Color("#1d1a16")
const TILE_EDGE := Color("#f1e6c8")
const DESERT := Color("#dcc79a")
const TERRAIN := {
	"Clay": Color("#c4623a"),
	"Wood": Color("#2e7a3c"),
	"Sheep": Color("#9bc957"),
	"Wheat": Color("#e7c143"),
	"Ore": Color("#8c929c"),
}
const SEAT_COLORS: Array[Color] = [Color("#d8413a"), Color("#3a72d8"), Color("#f29a26"), Color("#f4f1ea")]
const CHIP := Color("#f6ecd2")
const CHIP_TEXT := Color("#2a2420")
const HOT_NUMBER := Color("#c62a1f")
const PIER := Color("#8a6236")
const HIGHLIGHT := Color(1.0, 1.0, 1.0, 0.85)

var _board_control: Board
var _board: SiBoard
var _geometry: BoardGeometry
var _font: Font


func _init(board_control: Board, board: SiBoard, geometry: BoardGeometry) -> void:
	_board_control = board_control
	_board = board
	_geometry = geometry
	_font = board_control.get_theme_default_font()


static func seat_color(seat: int) -> Color:
	return SEAT_COLORS[seat % SEAT_COLORS.size()]


func draw_sea() -> void:
	_board_control.draw_rect(Rect2(Vector2.ZERO, _board_control.size), SEA)
	# A wider hexagon behind each tile gives the island a shallow-water rim.
	for tile in _board.tiles:
		_board_control.draw_colored_polygon(_hexagon(tile.coordinates, 1.18), COAST)


func draw_tiles() -> void:
	for tile_index in _board.tiles.size():
		_draw_tile(tile_index)


func draw_ports() -> void:
	for port in _geometry.ports:
		_draw_port(port)


func draw_roads() -> void:
	for edge_index in _board.roads.size():
		var seat: Variant = _board.roads[edge_index]
		if seat == null:
			continue
		var corners := _board.edges[edge_index].corners
		_draw_road(_geometry.corner_points[corners[0]], _geometry.corner_points[corners[1]], seat_color(seat), 1.0)


func draw_buildings() -> void:
	for corner in _board.buildings.size():
		var building := _board.buildings[corner]
		if building == null:
			continue
		var center := _geometry.corner_points[corner]
		var color := seat_color(building.seat)
		if building.kind == SiBuildingKind.CITY:
			_draw_city(center, color)
		else:
			_draw_settlement(center, color)


func draw_robber() -> void:
	var tile := _board.tiles[_board.robber]
	var center := _geometry.tile_centers[_board.robber]
	# Beside the number chip, so the chip stays readable.
	var spot := center if tile.number == null else center + Vector2(-0.5, 0.05)
	var body := PackedVector2Array([
		spot + Vector2(-0.16, 0.26), spot + Vector2(-0.12, 0.0), spot + Vector2(-0.07, -0.1),
		spot + Vector2(0.07, -0.1), spot + Vector2(0.12, 0.0), spot + Vector2(0.16, 0.26),
	])
	_polygon(body, Color("#2b2b30"), Color("#d9d9de"))
	_circle(spot + Vector2(0.0, -0.17), 0.1, Color("#2b2b30"))
	_ring(spot + Vector2(0.0, -0.17), 0.1, Color("#d9d9de"), 0.025)


## Highlights every target; the hovered one previews the piece in the own seat colour.
func draw_targets(targets: Array[Dictionary], hovered: Dictionary, seat: int) -> void:
	for target in targets:
		_draw_target(target, target == hovered, seat_color(seat))


func _draw_tile(tile_index: int) -> void:
	var tile := _board.tiles[tile_index]
	var fill: Color = TERRAIN.get(tile.resource, DESERT) if tile.resource != null else DESERT
	var corners := _hexagon(tile.coordinates, 0.96)
	_board_control.draw_colored_polygon(corners, fill)
	corners.append(corners[0])
	_board_control.draw_polyline(corners, TILE_EDGE.darkened(0.15), _pixels(0.035), true)
	_draw_resource_label(tile)
	if tile.number != null:
		_draw_chip(_geometry.tile_centers[tile_index], int(tile.number))


## The resource name in small print near the top of the tile, for players who do not read colours.
func _draw_resource_label(tile: SiTile) -> void:
	var name_text := "Desert" if tile.resource == null else str(tile.resource)
	var spot := BoardGeometry.tile_center(tile.coordinates) + Vector2(0.0, -0.56)
	_text(spot, name_text, 0.17, Color(0.1, 0.08, 0.05, 0.75))


func _draw_chip(center: Vector2, number: int) -> void:
	var hot := number == 6 or number == 8
	_circle(center, 0.3, CHIP)
	_ring(center, 0.3, Color("#6d5a3c"), 0.03)
	var color := HOT_NUMBER if hot else CHIP_TEXT
	_text(center + Vector2(0.0, -0.04), str(number), 0.3 if hot else 0.26, color)
	var pips := 6 - absi(7 - number)
	var spacing := 0.065
	var start := center + Vector2(-spacing * (pips - 1) / 2.0, 0.17)
	for pip in pips:
		_circle(start + Vector2(spacing * pip, 0.0), 0.022, color)


func _draw_port(port: Dictionary) -> void:
	var marker: Vector2 = port["marker"]
	var corners: Array[int] = port["corners"]
	for corner in corners:
		var from := _geometry.corner_points[corner]
		_board_control.draw_line(_to_pixels(from), _to_pixels(marker), PIER, _pixels(0.09), true)
	var specific := port["port"] as SiPortSpecific
	var fill := Color("#f4f1ea") if specific == null else TERRAIN[specific.value] as Color
	_circle(marker, BoardGeometry.PORT_RADIUS, fill)
	_ring(marker, BoardGeometry.PORT_RADIUS, OUTLINE, 0.03)
	var text_color := CHIP_TEXT if specific == null or specific.value != "Wood" else Color.WHITE
	if specific == null:
		_text(marker, "3:1", 0.22, text_color)
		return
	_text(marker + Vector2(0.0, -0.08), "2:1", 0.18, text_color)
	_text(marker + Vector2(0.0, 0.1), specific.value, 0.13, text_color)


func _draw_road(from: Vector2, to: Vector2, color: Color, alpha: float) -> void:
	var start := from.lerp(to, 0.16)
	var end := to.lerp(from, 0.16)
	_board_control.draw_line(_to_pixels(start), _to_pixels(end), Color(OUTLINE, alpha), _pixels(0.19), true)
	_board_control.draw_line(_to_pixels(start), _to_pixels(end), Color(color, alpha), _pixels(0.12), true)


func _draw_settlement(center: Vector2, color: Color) -> void:
	var house := PackedVector2Array([
		center + Vector2(-0.15, 0.13), center + Vector2(-0.15, -0.04), center + Vector2(0.0, -0.18),
		center + Vector2(0.15, -0.04), center + Vector2(0.15, 0.13),
	])
	_polygon(house, color, OUTLINE)


## Twice the footprint of a settlement, with a tower, so the two read apart at a glance.
func _draw_city(center: Vector2, color: Color) -> void:
	var city := PackedVector2Array([
		center + Vector2(-0.27, 0.17), center + Vector2(-0.27, -0.12), center + Vector2(-0.135, -0.27),
		center + Vector2(0.0, -0.12), center + Vector2(0.0, -0.02), center + Vector2(0.27, -0.02),
		center + Vector2(0.27, 0.17),
	])
	_polygon(city, color, OUTLINE)
	_circle(center + Vector2(-0.135, -0.07), 0.04, Color(OUTLINE, color.a))


func _draw_target(target: Dictionary, hovered: bool, color: Color) -> void:
	var point: Vector2 = target["point"]
	match target["kind"]:
		Board.TargetKind.CORNER:
			_draw_corner_target(target["action"], point, hovered, color)
		Board.TargetKind.EDGE:
			_draw_edge_target(target["action"], hovered, color)
		Board.TargetKind.TILE:
			_draw_tile_target(point, hovered)


func _draw_corner_target(action: SiAction, point: Vector2, hovered: bool, color: Color) -> void:
	if not hovered:
		_circle(point, 0.13, Color(1.0, 1.0, 1.0, 0.45))
		_ring(point, 0.13, HIGHLIGHT, 0.04)
		return
	if action is SiActionBuildCity:
		_draw_city(point, Color(color, 0.85))
	else:
		_draw_settlement(point, Color(color, 0.85))
	_ring(point, 0.27, Color.WHITE, 0.05)


func _draw_edge_target(action: SiAction, hovered: bool, color: Color) -> void:
	var corners := _board.edges[action.get("edge")].corners
	var from := _geometry.corner_points[corners[0]]
	var to := _geometry.corner_points[corners[1]]
	if hovered:
		_draw_road(from, to, color, 1.0)
		return
	var start := _to_pixels(from.lerp(to, 0.22))
	var end := _to_pixels(to.lerp(from, 0.22))
	_board_control.draw_line(start, end, Color(1.0, 1.0, 1.0, 0.6), _pixels(0.1), true)


func _draw_tile_target(point: Vector2, hovered: bool) -> void:
	# Around the chip, clear of the resource label.
	_ring(point, 0.42, HIGHLIGHT, 0.09 if hovered else 0.04)


func _hexagon(coordinates: SiCubeCoordinates, scale: float) -> PackedVector2Array:
	var center := BoardGeometry.tile_center(coordinates)
	var points := PackedVector2Array()
	for index in 6:
		var corner := BoardGeometry.tile_corner(coordinates, index)
		points.append(_to_pixels(center.lerp(corner, scale)))
	return points


func _polygon(points: PackedVector2Array, fill: Color, outline: Color) -> void:
	var pixels := PackedVector2Array()
	for point in points:
		pixels.append(_to_pixels(point))
	_board_control.draw_colored_polygon(pixels, fill)
	pixels.append(pixels[0])
	_board_control.draw_polyline(pixels, Color(outline, fill.a), _pixels(0.03), true)


func _circle(center: Vector2, radius: float, color: Color) -> void:
	_board_control.draw_circle(_to_pixels(center), _pixels(radius), color, true, -1.0, true)


func _ring(center: Vector2, radius: float, color: Color, width: float) -> void:
	_board_control.draw_arc(_to_pixels(center), _pixels(radius), 0.0, TAU, 48, color, _pixels(width), true)


## Draws `text` centred on `center`, with a height of `height` hex units.
func _text(center: Vector2, text: String, height: float, color: Color) -> void:
	var font_size := maxi(8, int(_pixels(height)))
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := _to_pixels(center) + Vector2(-width / 2.0, (_font.get_ascent(font_size) - _font.get_descent(font_size)) / 2.0)
	_board_control.draw_string(_font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _to_pixels(point: Vector2) -> Vector2:
	return _board_control.to_pixels(point)


func _pixels(length: float) -> float:
	return length * _board_control.hex_size
