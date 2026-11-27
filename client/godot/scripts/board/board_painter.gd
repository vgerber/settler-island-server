class_name BoardPainter
extends RefCounted
## Draws one frame of the board onto its `Board` control; all sizes are in hex units scaled by
## `Board.hex_size`, so the drawing follows the fitted rect. Look: doc/design/visual-style.md section 3.

const SHADOW_OFFSET := Vector2(0.015, 0.025)
## Wave marks sit on a fixed grid in hex units, so every frame and screenshot draws the same sea.
const WAVE_SPACING := 0.9
const WAVE_CLEARANCE := 1.25
const BOARD_FONT := preload("res://theme/fonts/Bitter-Bold.res")
## Upper and lower motif bands of a tile, clear of the chip and the corner pieces.
## The smallest port label in real pixels (doc/design/visual-style.md).
const PORT_TEXT_FLOOR := 16.0
const MOTIF_BANDS: Array[Vector2] = [Vector2(0.0, -0.55), Vector2(0.0, 0.55)]

var _board_control: Board
var _board: SiBoard
var _geometry: BoardGeometry


func _init(board_control: Board, board: SiBoard, geometry: BoardGeometry) -> void:
	_board_control = board_control
	_board = board
	_geometry = geometry


func draw_sea() -> void:
	_board_control.draw_rect(Rect2(Vector2.ZERO, _board_control.size), Palette.SEA)
	_draw_wave_marks()
	# Shoal then sand behind the tiles: a shallow rim, a beach, and thin grout between tiles.
	for tile in _board.tiles:
		_board_control.draw_colored_polygon(_hexagon(tile.coordinates, 1.18), Palette.SHOAL)
	for tile in _board.tiles:
		_board_control.draw_colored_polygon(_hexagon(tile.coordinates, 1.05), Palette.SAND)


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
		_draw_road(_geometry.corner_points[corners[0]], _geometry.corner_points[corners[1]], seat, 1.0)


func draw_buildings() -> void:
	for corner in _board.buildings.size():
		var building := _board.buildings[corner]
		if building == null:
			continue
		var center := _geometry.corner_points[corner]
		if building.kind == SiBuildingKind.CITY:
			_draw_city(center, building.seat, 1.0)
		else:
			_draw_settlement(center, building.seat, 1.0)


func draw_robber() -> void:
	var tile := _board.tiles[_board.robber]
	var center := _geometry.tile_centers[_board.robber]
	# Beside the number chip, so the chip stays readable.
	var spot := center if tile.number == null else center + Vector2(-0.5, 0.05)
	_ellipse(spot + Vector2(0.0, 0.22), Vector2(0.2, 0.06), Palette.SHADOW_SOFT)
	var cloak := _offset(spot, [
		Vector2(-0.17, 0.22), Vector2(-0.15, 0.12), Vector2(-0.12, 0.02), Vector2(-0.11, -0.04),
		Vector2(-0.07, -0.07), Vector2(0.07, -0.07), Vector2(0.11, -0.04), Vector2(0.12, 0.02),
		Vector2(0.15, 0.12), Vector2(0.17, 0.22),
	])
	var hood_center := spot + Vector2(0.0, -0.12)
	var hood := _hood(hood_center)
	_fill(_grown(cloak, 0.035), Palette.KEYLINE)
	_fill(_grown(hood, 0.035), Palette.KEYLINE)
	_fill(cloak, Palette.ROBBER)
	_fill(hood, Palette.ROBBER)
	_line(spot + Vector2(0.0, -0.03), spot + Vector2(0.03, 0.2), 0.015, Palette.ROBBER.lightened(0.18))
	_ellipse(hood_center + Vector2(0.015, 0.015), Vector2(0.05, 0.055), Palette.ROBBER.darkened(0.5))
	_circle(hood_center + Vector2(0.03, 0.025), 0.025, Palette.FOCUS_ON_DARK)


## A round hood drawn up to a point at the back, so the figure reads as cloaked rather than as a pawn.
func _hood(center: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array([center + Vector2(-0.04, -0.17)])
	for step in 9:
		var angle := deg_to_rad(-50.0 + step * 32.5)
		points.append(center + Vector2(cos(angle), sin(angle)) * 0.095)
	return points


## Highlights every target; the hovered one previews the piece in the own seat colour. `pulse` is the
## alpha factor (0.6 to 1.0) of the lantern highlight; `Board` owns the clock.
func draw_targets(targets: Array[BoardTarget], hovered: BoardTarget, seat: int, pulse: float = 1.0) -> void:
	for target in targets:
		_draw_target(target, target == hovered, seat, pulse)


func _draw_wave_marks() -> void:
	var top_left := (Vector2.ZERO - _board_control.origin) / _board_control.hex_size
	var bottom_right := (_board_control.size - _board_control.origin) / _board_control.hex_size
	var first_row := floori(top_left.y / WAVE_SPACING)
	var last_row := ceili(bottom_right.y / WAVE_SPACING)
	for row in range(first_row, last_row + 1):
		var shift := WAVE_SPACING / 2.0 if row % 2 != 0 else 0.0
		var first_column := floori((top_left.x - shift) / WAVE_SPACING)
		var last_column := ceili((bottom_right.x - shift) / WAVE_SPACING)
		for column in range(first_column, last_column + 1):
			var spot := Vector2(column * WAVE_SPACING + shift, row * WAVE_SPACING)
			if not _near_tile(spot, WAVE_CLEARANCE):
				_draw_wave_mark(spot)


func _near_tile(spot: Vector2, distance: float) -> bool:
	for center in _geometry.tile_centers:
		if spot.distance_to(center) < distance:
			return true
	return false


## Two short arcs, one over and one under the line, read as a small wave.
func _draw_wave_mark(spot: Vector2) -> void:
	var radius := _pixels(0.12)
	var width := _pixels(0.02)
	_board_control.draw_arc(_to_pixels(spot + Vector2(-0.12, 0.0)), radius, PI + 0.5, TAU - 0.5, 10, Palette.WAVE, width, true)
	_board_control.draw_arc(_to_pixels(spot + Vector2(0.12, 0.0)), radius, 0.5, PI - 0.5, 10, Palette.WAVE, width, true)


func _draw_tile(tile_index: int) -> void:
	var tile := _board.tiles[tile_index]
	var fill := Palette.DESERT if tile.resource == null else Palette.resource_color(tile.resource)
	var corners := _hexagon(tile.coordinates, 0.955)
	_board_control.draw_colored_polygon(corners, fill)
	var bevel := _hexagon(tile.coordinates, 0.8)
	for index in bevel.size():
		bevel[index] += Vector2(-0.03, -0.04) * _board_control.hex_size
	_board_control.draw_colored_polygon(bevel, fill.lightened(0.06))
	corners.append(corners[0])
	_board_control.draw_polyline(corners, fill.darkened(0.25), _pixels(0.02), true)
	var center := _geometry.tile_centers[tile_index]
	_draw_motif(tile, center)
	if tile.number != null:
		_draw_chip(center, int(tile.number))


## Terrain motifs instead of a resource name, so tiles separate by shape as well as colour.
func _draw_motif(tile: SiTile, center: Vector2) -> void:
	var resource: String = "" if tile.resource == null else str(tile.resource)
	for band_index in MOTIF_BANDS.size():
		var band := center + MOTIF_BANDS[band_index]
		match resource:
			SiResource.WOOD:
				_draw_conifers(band)
			SiResource.SHEEP:
				_draw_pasture(band, band_index == 0)
			SiResource.WHEAT:
				_draw_sheaves(band)
			SiResource.CLAY:
				_draw_bricks(band)
			SiResource.ORE:
				_draw_peaks(band)
			_:
				_draw_dunes(band, band_index == 0)
	if resource.is_empty():
		_board_control.draw_arc(_to_pixels(center + Vector2(0.0, 0.1)), _pixels(0.2), PI + 0.6, TAU - 0.6, 12,
				Palette.DESERT_PATTERN, _pixels(0.03), true)


func _draw_conifers(band: Vector2) -> void:
	var dark := Palette.resource_pattern_color(SiResource.WOOD)
	for offset: float in [-0.22, 0.0, 0.22]:
		var base := band + Vector2(offset, 0.0)
		_fill(PackedVector2Array([base + Vector2(-0.015, 0.1), base + Vector2(0.015, 0.1),
				base + Vector2(0.015, 0.15), base + Vector2(-0.015, 0.15)]), dark.darkened(0.3))
		for tier: Vector2 in [Vector2(0.1, 0.09), Vector2(-0.01, 0.07)]:
			var left := base + Vector2(-tier.y, tier.x)
			var apex := base + Vector2(0.0, tier.x - 0.15)
			_fill(PackedVector2Array([left, apex, base + Vector2(tier.y, tier.x)]), dark)
			_line(left, apex, 0.03, Palette.PINE_LIGHT)


func _draw_pasture(band: Vector2, upper: bool) -> void:
	if upper:
		for offset: float in [-0.22, 0.0, 0.22]:
			var root := band + Vector2(offset, 0.08)
			for tip: Vector2 in [Vector2(-0.06, -0.12), Vector2(0.0, -0.16), Vector2(0.06, -0.12)]:
				_line(root, root + tip, 0.025, Palette.resource_pattern_color(SiResource.SHEEP))
		return
	for offset: float in [-0.15, 0.15]:
		var body := band + Vector2(offset, 0.0)
		for puff: Vector2 in [Vector2(-0.04, 0.0), Vector2(0.0, -0.025), Vector2(0.04, 0.0)]:
			_circle(body + puff, 0.05, Palette.FLEECE)
		_circle(body + Vector2(0.085, -0.015), 0.025, Palette.INK)


func _draw_sheaves(band: Vector2) -> void:
	var straw := Palette.resource_pattern_color(SiResource.WHEAT)
	for offset: float in [-0.22, 0.0, 0.22]:
		var stalk := band + Vector2(offset, 0.0)
		_line(stalk + Vector2(0.0, 0.14), stalk + Vector2(0.0, -0.13), 0.025, straw)
		for height: float in [-0.12, -0.05, 0.02]:
			var tip := stalk + Vector2(0.0, height)
			_polyline([tip + Vector2(-0.05, 0.04), tip, tip + Vector2(0.05, 0.04)], 0.025, straw)


func _draw_bricks(band: Vector2) -> void:
	var brick := Palette.resource_pattern_color(SiResource.CLAY)
	for offset: float in [-0.18, 0.0, 0.18]:
		_fill(_brick(band + Vector2(offset - 0.09, -0.045)), brick)
		_fill(_brick(band + Vector2(offset, 0.045)), brick)


## A 0.16 x 0.07 brick with clipped corners, centred on `center`.
func _brick(center: Vector2) -> PackedVector2Array:
	var half := Vector2(0.08, 0.035)
	var clip := 0.015
	return PackedVector2Array([
		center + Vector2(-half.x + clip, -half.y), center + Vector2(half.x - clip, -half.y),
		center + Vector2(half.x, -half.y + clip), center + Vector2(half.x, half.y - clip),
		center + Vector2(half.x - clip, half.y), center + Vector2(-half.x + clip, half.y),
		center + Vector2(-half.x, half.y - clip), center + Vector2(-half.x, -half.y + clip),
	])


func _draw_peaks(band: Vector2) -> void:
	var rock := Palette.resource_pattern_color(SiResource.ORE)
	for offset: float in [-0.15, 0.15]:
		var base := band + Vector2(offset, 0.13)
		var apex := base + Vector2(0.0, -0.28)
		var left := base + Vector2(-0.16, 0.0)
		var right := base + Vector2(0.16, 0.0)
		_fill(PackedVector2Array([left, apex, right]), rock)
		_fill(PackedVector2Array([apex.lerp(left, 0.34), apex, apex.lerp(right, 0.34)]), Palette.PEAK_SNOW)
		_line(apex, base + Vector2(0.03, 0.0), 0.02, rock.darkened(0.35))


func _draw_dunes(band: Vector2, upper: bool) -> void:
	for offset: float in [-0.15, 0.15]:
		_board_control.draw_arc(_to_pixels(band + Vector2(offset, 0.1)), _pixels(0.14), PI + 0.5, TAU - 0.5, 12,
				Palette.DESERT_PATTERN, _pixels(0.03), true)
	var rock_spot := band + (Vector2(0.3, 0.06) if upper else Vector2(-0.3, 0.02))
	_ellipse(rock_spot, Vector2(0.045, 0.028), Palette.DESERT_ROCK)


func _draw_chip(center: Vector2, number: int) -> void:
	var hot := number == 6 or number == 8
	var color := Palette.HOT_NUMBER if hot else Palette.INK
	_shadow_circle(center, 0.3)
	_circle(center, 0.3, Palette.CARD_STOCK)
	_ring(center, 0.3 - 0.0125, Palette.CHIP_RIM, 0.025)
	if hot:
		# A second rim, so "hot" is not carried by colour alone.
		_ring(center, 0.255, Palette.HOT_NUMBER, 0.018)
	else:
		_ring(center, 0.25, Color(Palette.CHIP_RIM, 0.35), 0.01)
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
		_draw_pier(_geometry.corner_points[corner], marker)
	_shadow_circle(marker, BoardGeometry.PORT_RADIUS)
	_circle(marker, BoardGeometry.PORT_RADIUS, Palette.CARD_STOCK)
	var specific := port["port"] as SiPortSpecific
	if specific == null:
		_ring(marker, BoardGeometry.PORT_RADIUS - 0.015, Palette.INK, 0.03)
		_text(marker, "3:1", 0.3, Palette.INK, PORT_TEXT_FLOOR)
		return
	_ring(marker, BoardGeometry.PORT_RADIUS - 0.03, Palette.resource_color(specific.value), 0.07)
	_text(marker + Vector2(0.0, -0.13), "2:1", 0.27, Palette.INK, PORT_TEXT_FLOOR)
	ResourceArt.draw_icon(_board_control, specific.value, _to_pixels(marker + Vector2(0.0, 0.17)), _pixels(0.27))


## Two planks on cross ties from a coast corner out to the port badge.
func _draw_pier(from: Vector2, to: Vector2) -> void:
	var direction := (to - from).normalized()
	var side := Vector2(-direction.y, direction.x)
	var length := from.distance_to(to)
	var tie := 0.05
	while tie < length:
		var spot := from + direction * tie
		_line(spot - side * 0.07, spot + side * 0.07, 0.03, Palette.PIER_TIE)
		tie += 0.1
	for plank: float in [-0.0425, 0.0425]:
		_line(from + side * plank, to + side * plank, 0.035, Palette.PIER)


## A capsule from 0.16 to 0.84 of the edge: keyline, outline, fill and a lit upper edge.
func _draw_road(from: Vector2, to: Vector2, seat: int, alpha: float) -> void:
	var start := from.lerp(to, 0.16)
	var end := to.lerp(from, 0.16)
	var fill := Palette.seat_color(seat)
	_capsule(start, end, 0.24, _faded(Palette.seat_keyline(seat), alpha))
	_capsule(start, end, 0.19, _faded(Palette.seat_outline(seat), alpha))
	_capsule(start, end, 0.12, _faded(fill, alpha))
	var direction := (end - start).normalized()
	var normal := Vector2(direction.y, -direction.x)
	# The normal that points up the screen (or left on vertical edges) is the lit side.
	if normal.y > 0.0 or (is_zero_approx(normal.y) and normal.x > 0.0):
		normal = -normal
	_line(start + normal * 0.03, end + normal * 0.03, 0.03, _faded(fill.lightened(0.25), alpha))


func _capsule(start: Vector2, end: Vector2, width: float, color: Color) -> void:
	_line(start, end, width, color)
	_circle(start, width / 2.0, color)
	_circle(end, width / 2.0, color)


func _draw_settlement(center: Vector2, seat: int, alpha: float) -> void:
	var house := _offset(center, [
		Vector2(-0.15, 0.13), Vector2(-0.15, -0.04), Vector2(0.0, -0.18), Vector2(0.15, -0.04), Vector2(0.15, 0.13),
	])
	var fill := Palette.seat_color(seat)
	_fill(_grown(house, 0.035), _faded(Palette.seat_keyline(seat), alpha))
	_fill(house, _faded(fill, alpha))
	_fill(_offset(center, [Vector2(-0.15, -0.04), Vector2(0.0, -0.18), Vector2(0.15, -0.04)]),
			_faded(fill.lightened(0.18), alpha))
	_fill(_offset(center, [Vector2(-0.025, 0.13), Vector2(-0.025, 0.05), Vector2(0.025, 0.05), Vector2(0.025, 0.13)]),
			_faded(fill.darkened(0.35), alpha))
	_outline(house, _faded(Palette.seat_outline(seat), alpha))


## Twice the footprint of a settlement, with a tower, so the two read apart at a glance.
func _draw_city(center: Vector2, seat: int, alpha: float) -> void:
	var city := _offset(center, [
		Vector2(-0.27, 0.17), Vector2(-0.27, -0.12), Vector2(-0.135, -0.27), Vector2(0.0, -0.12),
		Vector2(0.0, -0.02), Vector2(0.27, -0.02), Vector2(0.27, 0.17),
	])
	var fill := Palette.seat_color(seat)
	var shade := _faded(fill.darkened(0.35), alpha)
	_fill(_grown(city, 0.035), _faded(Palette.seat_keyline(seat), alpha))
	_fill(city, _faded(fill, alpha))
	_fill(_offset(center, [Vector2(-0.27, -0.12), Vector2(-0.135, -0.27), Vector2(0.0, -0.12)]),
			_faded(fill.lightened(0.18), alpha))
	_circle(center + Vector2(-0.135, -0.07), 0.04, shade)
	for window: Vector2 in [Vector2(0.085, 0.06), Vector2(0.185, 0.06)]:
		var spot := center + window
		_fill(_offset(spot, [Vector2(-0.02, -0.02), Vector2(0.02, -0.02), Vector2(0.02, 0.02), Vector2(-0.02, 0.02)]),
				shade)
	_outline(city, _faded(Palette.seat_outline(seat), alpha))


func _draw_target(target: BoardTarget, hovered: bool, seat: int, pulse: float) -> void:
	match target.kind:
		BoardTarget.Kind.CORNER:
			_draw_corner_target(target.action, target.point, hovered, seat, pulse)
		BoardTarget.Kind.EDGE:
			_draw_edge_target(target.action, hovered, seat, pulse)
		BoardTarget.Kind.TILE:
			_draw_tile_target(target.point, hovered, pulse)


func _draw_corner_target(action: SiAction, point: Vector2, hovered: bool, seat: int, pulse: float) -> void:
	if not hovered:
		_ring(point, 0.13, Palette.TARGET_HALO, 0.07)
		_circle(point, 0.13, Color(Palette.TARGET, 0.25 * pulse))
		_ring(point, 0.13, Color(Palette.TARGET, pulse), 0.04)
		return
	if action is SiActionBuildCity:
		_draw_city(point, seat, 0.85)
	else:
		_draw_settlement(point, seat, 0.85)
	_ring(point, 0.3, Palette.TARGET_HALO, 0.08)
	_ring(point, 0.3, Palette.TARGET, 0.045)


func _draw_edge_target(action: SiAction, hovered: bool, seat: int, pulse: float) -> void:
	var corners := _board.edges[action.get("edge")].corners
	var from := _geometry.corner_points[corners[0]]
	var to := _geometry.corner_points[corners[1]]
	if hovered:
		_draw_road(from, to, seat, 0.85)
		return
	_line(from.lerp(to, 0.22), to.lerp(from, 0.22), 0.12, Palette.TARGET_HALO)
	for dash in 3:
		var dash_start := 0.24 + dash * 0.2
		_line(from.lerp(to, dash_start), from.lerp(to, dash_start + 0.12), 0.06, Color(Palette.TARGET, pulse))


func _draw_tile_target(point: Vector2, hovered: bool, pulse: float) -> void:
	_ring(point, 0.42, Palette.TARGET_HALO, 0.12 if hovered else 0.08)
	_ring(point, 0.42, Palette.TARGET if hovered else Color(Palette.TARGET, pulse), 0.08 if hovered else 0.045)


func _hexagon(coordinates: SiCubeCoordinates, scale: float) -> PackedVector2Array:
	var center := BoardGeometry.tile_center(coordinates)
	var points := PackedVector2Array()
	for index in 6:
		var corner := BoardGeometry.tile_corner(coordinates, index)
		points.append(_to_pixels(center.lerp(corner, scale)))
	return points


func _offset(center: Vector2, points: Array[Vector2]) -> PackedVector2Array:
	var placed := PackedVector2Array()
	for point in points:
		placed.append(center + point)
	return placed


## The polygon pushed outward from its centroid by `distance` hex units, for keylines.
func _grown(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	var centroid := Vector2.ZERO
	for point in points:
		centroid += point
	centroid /= points.size()
	var grown := PackedVector2Array()
	for point in points:
		grown.append(point + (point - centroid).normalized() * distance)
	return grown


func _fill(points: PackedVector2Array, color: Color) -> void:
	var pixels := PackedVector2Array()
	for point in points:
		pixels.append(_to_pixels(point))
	_board_control.draw_colored_polygon(pixels, color)


func _outline(points: PackedVector2Array, color: Color) -> void:
	var pixels := PackedVector2Array()
	for point in points:
		pixels.append(_to_pixels(point))
	pixels.append(pixels[0])
	_board_control.draw_polyline(pixels, color, _pixels(0.03), true)


func _line(from: Vector2, to: Vector2, width: float, color: Color) -> void:
	_board_control.draw_line(_to_pixels(from), _to_pixels(to), color, _pixels(width), true)


func _polyline(points: Array[Vector2], width: float, color: Color) -> void:
	var pixels := PackedVector2Array()
	for point in points:
		pixels.append(_to_pixels(point))
	_board_control.draw_polyline(pixels, color, _pixels(width), true)


func _circle(center: Vector2, radius: float, color: Color) -> void:
	_board_control.draw_circle(_to_pixels(center), _pixels(radius), color, true, -1.0, true)


func _shadow_circle(center: Vector2, radius: float) -> void:
	_circle(center + SHADOW_OFFSET, radius, Palette.SHADOW)


func _ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 20:
		var angle := TAU * index / 20.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	_fill(points, color)


func _ring(center: Vector2, radius: float, color: Color, width: float) -> void:
	_board_control.draw_arc(_to_pixels(center), _pixels(radius), 0.0, TAU, 48, color, _pixels(width), true)


func _faded(color: Color, alpha: float) -> Color:
	return Color(color, color.a * alpha)


## Draws `text` centred on `center`, with a height of `height` hex units, but never under `floor_pixels`
## real screen pixels (0 for none): small windows shrink the board, not what players must read.
func _text(center: Vector2, text: String, height: float, color: Color, floor_pixels: float = 0.0) -> void:
	var scale := _board_control.get_viewport().get_final_transform().get_scale().x
	var font_size := maxi(8, int(maxf(_pixels(height), floor_pixels / scale)))
	var width := BOARD_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := _to_pixels(center) + Vector2(-width / 2.0,
			(BOARD_FONT.get_ascent(font_size) - BOARD_FONT.get_descent(font_size)) / 2.0)
	_board_control.draw_string(BOARD_FONT, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _to_pixels(point: Vector2) -> Vector2:
	return _board_control.to_pixels(point)


func _pixels(length: float) -> float:
	return length * _board_control.hex_size
