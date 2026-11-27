class_name HudSeatChip
extends Control
## A seat's identity: its colour plus a shape (circle, square, triangle, diamond), so it never depends on
## colour alone and stays readable on parchment, including Ivory and Charcoal.

const SHAPES := 4

var seat := 0:
	set(value):
		seat = value
		queue_redraw()


func _init(chip_seat: int = 0, chip_size: float = 24.0) -> void:
	seat = chip_seat
	custom_minimum_size = Vector2(chip_size, chip_size)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var radius := minf(size.x, size.y) / 2.0 - 2.0
	var points := outline_points(seat, size / 2.0, radius)
	draw_colored_polygon(points, Palette.seat_color(seat))
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, Palette.seat_outline(seat), 2.0, true)


## The polygon of the seat's shape around `center`.
static func outline_points(chip_seat: int, center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	match chip_seat % SHAPES:
		0:
			for step in 24:
				points.append(center + Vector2.from_angle(TAU * step / 24.0) * radius)
		1:
			var half := radius * 0.88
			points = [center + Vector2(-half, -half), center + Vector2(half, -half), center + Vector2(half, half), center + Vector2(-half, half)]
		2:
			points = [center + Vector2(0.0, -radius), center + Vector2(radius, radius * 0.8), center + Vector2(-radius, radius * 0.8)]
		3:
			points = [center + Vector2(0.0, -radius), center + Vector2(radius, 0.0), center + Vector2(0.0, radius), center + Vector2(-radius, 0.0)]
	return points


static var _textures: Dictionary[int, ImageTexture] = {}


## The chip as a small image, for places that only take textures (the rich text of the log).
static func texture(chip_seat: int, pixels: int = 20) -> ImageTexture:
	var key := chip_seat % SHAPES
	if _textures.has(key):
		return _textures[key]
	var center := Vector2.ONE * pixels / 2.0
	var outer := outline_points(chip_seat, center, pixels / 2.0 - 1.0)
	var inner := outline_points(chip_seat, center, pixels / 2.0 - 3.0)
	var image := Image.create_empty(pixels, pixels, false, Image.FORMAT_RGBA8)
	for y in pixels:
		for x in pixels:
			var spot := Vector2(x + 0.5, y + 0.5)
			if Geometry2D.is_point_in_polygon(spot, inner):
				image.set_pixel(x, y, Palette.seat_color(chip_seat))
			elif Geometry2D.is_point_in_polygon(spot, outer):
				image.set_pixel(x, y, Palette.seat_outline(chip_seat))
	var created := ImageTexture.create_from_image(image)
	_textures[key] = created
	return created
