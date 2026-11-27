class_name HudGearButton
extends Button
## A button with a drawn gear, so it needs no icon font.

const TEETH := 8


func _init() -> void:
	custom_minimum_size = Vector2(40.0, 40.0)
	tooltip_text = "Settings"
	theme_type_variation = &"GhostButton"


func _draw() -> void:
	var center := size / 2.0
	var radius := minf(size.x, size.y) * 0.3
	var color := Palette.CREAM
	var points := PackedVector2Array()
	for step in TEETH * 2:
		var reach := radius * (1.3 if step % 2 == 0 else 1.0)
		points.append(center + Vector2.from_angle(TAU * (step - 0.5) / (TEETH * 2.0)) * reach)
	draw_colored_polygon(points, color)
	draw_circle(center, radius * 0.45, Palette.INK)
