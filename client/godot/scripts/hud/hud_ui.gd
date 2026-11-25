class_name HudUi
extends RefCounted
## Small widget factories so the HUD parts share one look.

const PANEL_COLOR := Color(0.09, 0.12, 0.16, 0.94)
const DIALOG_COLOR := Color(0.13, 0.17, 0.22, 0.98)
const MUTED_COLOR := Color(0.7, 0.74, 0.8)


static func flat_style(color: Color, radius: int = 6, padding: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(padding)
	return style


static func panel(color: Color = PANEL_COLOR, radius: int = 0, padding: int = 12) -> PanelContainer:
	var container := PanelContainer.new()
	container.add_theme_stylebox_override("panel", flat_style(color, radius, padding))
	return container


static func label(text: String, font_size: int = 16, color: Color = Color.WHITE) -> Label:
	var created := Label.new()
	created.text = text
	created.add_theme_font_size_override("font_size", font_size)
	created.add_theme_color_override("font_color", color)
	return created


static func button(text: String, on_pressed: Callable) -> Button:
	var created := Button.new()
	created.text = text
	created.custom_minimum_size = Vector2(0, 36)
	created.pressed.connect(on_pressed)
	return created


## A square button for counters such as "-" and "+".
static func small_button(text: String, on_pressed: Callable) -> Button:
	var created := button(text, on_pressed)
	created.custom_minimum_size = Vector2(40, 36)
	created.add_theme_font_size_override("font_size", 20)
	return created


static func vbox(separation: int = 8) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func hbox(separation: int = 8) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


## A coloured tile with a resource name and a count, as on a card in hand.
static func resource_tile(resource: String, count: int, size: Vector2 = Vector2(64, 84)) -> PanelContainer:
	var tile := panel(HudText.resource_color(resource), 6, 4)
	tile.custom_minimum_size = size
	var column := vbox(0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_label := label(resource, 13, Color(0.08, 0.08, 0.08))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var count_label := label(str(count), 28, Color(0.05, 0.05, 0.05))
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)
	column.add_child(count_label)
	tile.add_child(column)
	if count == 0:
		tile.modulate = Color(1, 1, 1, 0.4)
	return tile


static func clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
