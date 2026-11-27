class_name HudResourceIcon
extends Control
## The board's resource icon at HUD size, so hand, bank and dialogs match the tiles.

var resource := "":
	set(value):
		resource = value
		queue_redraw()


func _init(icon_resource: String = "", icon_size: float = 28.0) -> void:
	resource = icon_resource
	custom_minimum_size = Vector2(icon_size, icon_size)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if not resource.is_empty():
		ResourceArt.draw_icon(self, resource, size / 2.0, minf(size.x, size.y))
