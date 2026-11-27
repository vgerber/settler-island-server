class_name HudToasts
extends VBoxContainer
## Short messages at the top right of the game: at most three, newest on top, errors a second longer. They
## never cover the board centre or the action bar and ignore the mouse. Kinds: `error`, `info`, `alert`.

const MAX_VISIBLE := 3
const SECONDS := 3.0
const ERROR_SECONDS := 4.0
const SLIDE_SECONDS := 0.15
const FADE_SECONDS := 0.25
const EDGE_COLORS := {&"error": Color("#C8372D"), &"info": Color("#6B5A45"), &"alert": Color("#E0A32E")}

## Off skips the slide and the fade.
var animated := true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN


func push(text: String, kind: StringName = &"info") -> void:
	var toast := _build(text, kind)
	add_child(toast)
	move_child(toast, 0)
	while get_child_count() > MAX_VISIBLE:
		_remove(get_child(get_child_count() - 1))
	var seconds := ERROR_SECONDS if kind == &"error" else SECONDS
	if animated:
		toast.modulate.a = 0.0
		toast.create_tween().tween_property(toast, "modulate:a", 1.0, SLIDE_SECONDS)
	get_tree().create_timer(seconds).timeout.connect(_remove.bind(toast))


## The toasts that are not on their way out.
func visible_count() -> int:
	var count := 0
	for toast in get_children():
		if not toast.is_queued_for_deletion():
			count += 1
	return count


func _build(text: String, kind: StringName) -> PanelContainer:
	var toast := HudUi.panel(&"SeatPanel")
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.custom_minimum_size = Vector2(240.0, 0.0)
	var edged := toast.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if edged != null:
		edged.border_width_left = 6
		edged.border_color = EDGE_COLORS.get(kind, EDGE_COLORS[&"info"])
		toast.add_theme_stylebox_override("panel", edged)
	var label := HudUi.label(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(220.0, 0.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(label)
	return toast


func _remove(toast: Control) -> void:
	if not is_instance_valid(toast) or toast.is_queued_for_deletion():
		return
	if not animated:
		toast.queue_free()
		return
	var fade := toast.create_tween()
	fade.tween_property(toast, "modulate:a", 0.0, FADE_SECONDS)
	fade.tween_callback(toast.queue_free)
