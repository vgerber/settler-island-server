class_name HudUi
extends RefCounted
## Small widget factories so the HUD parts share the look of `theme/main_theme.tres`: every size and colour
## comes from a theme type variation (built by tools/build_theme.gd), none from overrides.

## The smallest click target in base units (layout.md "Scaling").
const MIN_BUTTON := Vector2(40.0, 40.0)
const SMALL := &"SmallLabel"
const BODY := &""
const COUNT := &"CountLabel"
const SUBHEADING := &"SubheadingLabel"
const HEADING := &"HeadingLabel"
const MUTED := &"MutedLabel"


static func label(text: String, variation: StringName = BODY) -> Label:
	var created := Label.new()
	created.text = text
	created.theme_type_variation = variation
	return created


static func button(text: String, on_pressed: Callable, variation: StringName = &"") -> Button:
	var created := Button.new()
	created.text = text
	created.theme_type_variation = variation
	created.custom_minimum_size = MIN_BUTTON
	created.pressed.connect(on_pressed)
	return created


## A square button for counters such as "-" and "+".
static func small_button(text: String, on_pressed: Callable) -> Button:
	return button(text, on_pressed)


static func vbox(separation: int = 8) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func hbox(separation: int = 8) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func panel(variation: StringName = &"") -> PanelContainer:
	var container := PanelContainer.new()
	container.theme_type_variation = variation
	return container


## Removes and frees every child; for lists whose length really changes, not for per-update refreshes.
static func clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
