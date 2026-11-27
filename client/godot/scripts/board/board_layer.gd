class_name BoardLayer
extends Control
## A full-rect child of the 2D board that draws through `draw_callback`, so parts of the board redraw on their own.

var _draw_callback: Callable


func _init(draw_callback: Callable) -> void:
	_draw_callback = draw_callback
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	_draw_callback.call(self)
