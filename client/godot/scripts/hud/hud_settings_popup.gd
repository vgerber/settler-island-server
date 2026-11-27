class_name HudSettingsPopup
extends PopupPanel
## The small settings panel behind the gear button: animation speed, skipping while unfocused, sound on or off
## and three volumes. Writes through the `Settings` autoload, which saves and applies them.

const VOLUMES := {"sfx_volume": "Effects", "ambience_volume": "Ambience", "music_volume": "Music"}
const GAP_BELOW_ANCHOR := 6


func _init() -> void:
	var column := HudUi.vbox(12)
	column.custom_minimum_size = Vector2(400.0, 0.0)
	column.add_child(HudUi.label("Settings", &"SubheadingLabel"))
	column.add_child(_speed_row())
	column.add_child(_toggle_row("Skip animations when unfocused", "skip_when_unfocused"))
	column.add_child(_toggle_row("Sound", "sound_enabled"))
	for key: String in VOLUMES:
		column.add_child(_volume_row(key, VOLUMES[key]))
	add_child(column)


## Opens right-aligned under `anchor`, a rect in the coordinates of the control that asked (the gear button).
func open_below(anchor: Rect2) -> void:
	var real := get_viewport().get_final_transform() * anchor
	var width := get_contents_minimum_size().x
	popup(Rect2i(Vector2i(int(real.end.x - width), int(real.end.y) + GAP_BELOW_ANCHOR), Vector2i.ZERO))


func _speed_row() -> HBoxContainer:
	var row := HudUi.hbox(12)
	var title := HudUi.label("Animation speed")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var choice := OptionButton.new()
	for name: String in Settings.SPEED_NAMES:
		choice.add_item(name)
	choice.select(Settings.animation_speed)
	choice.custom_minimum_size = Vector2(130.0, 40.0)
	choice.item_selected.connect(func(index: int) -> void: Settings.update("animation_speed", index))
	row.add_child(choice)
	return row


## A label and an On/Off button that reads as armed while on.
func _toggle_row(text: String, key: String) -> HBoxContainer:
	var row := HudUi.hbox(12)
	var title := HudUi.label(text)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var toggle := Button.new()
	toggle.theme_type_variation = &"BuildButton"
	toggle.toggle_mode = true
	toggle.custom_minimum_size = Vector2(80.0, 40.0)
	toggle.set_pressed_no_signal(Settings.get(key))
	toggle.text = "On" if toggle.button_pressed else "Off"
	toggle.toggled.connect(func(pressed: bool) -> void:
		toggle.text = "On" if pressed else "Off"
		Settings.update(key, pressed))
	row.add_child(toggle)
	return row


func _volume_row(key: String, text: String) -> HBoxContainer:
	var row := HudUi.hbox(12)
	var title := HudUi.label(text)
	title.custom_minimum_size = Vector2(110.0, 0.0)
	row.add_child(title)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Settings.get(key)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(120.0, 32.0)
	row.add_child(slider)
	var percent := HudUi.label(_percent(slider.value), &"CountLabel")
	percent.custom_minimum_size = Vector2(56.0, 0.0)
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(percent)
	slider.value_changed.connect(func(value: float) -> void:
		percent.text = _percent(value)
		Settings.update(key, value))
	return row


static func _percent(value: float) -> String:
	return "%d%%" % roundi(value * 100.0)
