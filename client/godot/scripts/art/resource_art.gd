class_name ResourceArt
extends RefCounted
## Resource icons (doc/design/visual-style.md section 4) drawn with primitives onto any CanvasItem:
## filled in the resource's pattern colour with an ink outline, so they read on parchment and on terrain.
## Shapes are laid out in a unit box (-0.5..0.5) and scaled to `size` pixels around `center`.


static func draw_icon(canvas: CanvasItem, resource: String, center: Vector2, size: float) -> void:
	var icon := ResourceArt.new(canvas, center, size)
	match resource:
		"Wood":
			icon._draw_log()
		"Sheep":
			icon._draw_fleece()
		"Wheat":
			icon._draw_sheaf()
		"Clay":
			icon._draw_bricks()
		"Ore":
			icon._draw_stone()


var _canvas: CanvasItem
var _center: Vector2
var _size: float
var _outline_width: float


func _init(canvas: CanvasItem, center: Vector2, size: float) -> void:
	_canvas = canvas
	_center = center
	_size = size
	# 1.5 px at the 20-44 px HUD sizes, thinner on tiny board badges.
	_outline_width = clampf(size * 0.06, 0.8, 1.5)


func _draw_log() -> void:
	var bark := Palette.resource_pattern_color("Wood")
	_shape(_rect_points(Vector2(-0.4, -0.18), Vector2(0.62, 0.36)), bark)
	_disc(Vector2(0.24, 0.0), 0.2, Color("#C9A46A"))
	_ring(Vector2(0.24, 0.0), 0.09, bark)


func _draw_fleece() -> void:
	var spots: Array[Vector2] = [Vector2(-0.2, 0.06), Vector2(0.0, -0.12), Vector2(0.2, 0.06), Vector2(0.0, 0.14)]
	# All outlines first, then all fills, so the cloud has one outer outline and no inner seams.
	for spot in spots:
		_canvas.draw_circle(_point(spot), 0.2 * _size + _outline_width, Palette.INK, true, -1.0, true)
	for spot in spots:
		_canvas.draw_circle(_point(spot), 0.2 * _size, Palette.FLEECE, true, -1.0, true)
	_disc(Vector2(0.36, -0.1), 0.09, Palette.INK)


func _draw_sheaf() -> void:
	var straw := Palette.resource_pattern_color("Wheat")
	for offset: float in [-0.16, 0.0, 0.16]:
		_shape(_rect_points(Vector2(offset - 0.035, -0.2), Vector2(0.07, 0.62)), straw)
		_shape(PackedVector2Array([
			_point(Vector2(offset, -0.46)), _point(Vector2(offset + 0.08, -0.26)), _point(Vector2(offset, -0.18)),
			_point(Vector2(offset - 0.08, -0.26)),
		]), straw)
	_shape(_rect_points(Vector2(-0.24, 0.06), Vector2(0.48, 0.08)), Palette.resource_pattern_color("Clay"))


func _draw_bricks() -> void:
	var brick := Palette.resource_pattern_color("Clay")
	_shape(_rect_points(Vector2(-0.42, 0.02), Vector2(0.84, 0.28)), brick)
	_shape(_rect_points(Vector2(-0.26, -0.3), Vector2(0.84, 0.28)), brick)


func _draw_stone() -> void:
	var slate := Palette.resource_pattern_color("Ore")
	_shape(PackedVector2Array([
		_point(Vector2(-0.4, 0.3)), _point(Vector2(-0.32, -0.12)), _point(Vector2(0.0, -0.38)),
		_point(Vector2(0.34, -0.14)), _point(Vector2(0.4, 0.3)),
	]), slate)
	_line(Vector2(0.0, -0.38), Vector2(0.06, 0.3), slate.lightened(0.45))
	_line(Vector2(-0.32, -0.12), Vector2(0.06, 0.04), slate.darkened(0.4))


func _rect_points(position: Vector2, extent: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		_point(position), _point(position + Vector2(extent.x, 0.0)), _point(position + extent),
		_point(position + Vector2(0.0, extent.y)),
	])


func _shape(points: PackedVector2Array, fill: Color) -> void:
	_canvas.draw_colored_polygon(points, fill)
	var closed := points.duplicate()
	closed.append(points[0])
	_canvas.draw_polyline(closed, Palette.INK, _outline_width, true)


func _disc(spot: Vector2, radius: float, fill: Color) -> void:
	_canvas.draw_circle(_point(spot), radius * _size, fill, true, -1.0, true)
	_canvas.draw_arc(_point(spot), radius * _size, 0.0, TAU, 24, Palette.INK, _outline_width, true)


func _ring(spot: Vector2, radius: float, color: Color) -> void:
	_canvas.draw_arc(_point(spot), radius * _size, 0.0, TAU, 24, color, _outline_width, true)


func _line(from: Vector2, to: Vector2, color: Color) -> void:
	_canvas.draw_line(_point(from), _point(to), color, _outline_width, true)


func _point(unit: Vector2) -> Vector2:
	return _center + unit * _size
