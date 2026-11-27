class_name HudHourglass
extends Control
## A small hourglass badge for a seat the game waits for; drawn, so it needs no font glyph or texture.

const BADGE_SIZE := Vector2(16.0, 20.0)


func _init() -> void:
	custom_minimum_size = BADGE_SIZE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func _draw() -> void:
	var top := PackedVector2Array([Vector2(2.0, 2.0), Vector2(14.0, 2.0), Vector2(8.0, 10.0)])
	var bottom := PackedVector2Array([Vector2(8.0, 10.0), Vector2(14.0, 18.0), Vector2(2.0, 18.0)])
	draw_colored_polygon(top, Palette.INK_MUTED)
	draw_colored_polygon(bottom, Palette.INK)
	draw_line(Vector2(1.0, 2.0), Vector2(15.0, 2.0), Palette.INK, 2.0)
	draw_line(Vector2(1.0, 18.0), Vector2(15.0, 18.0), Palette.INK, 2.0)
