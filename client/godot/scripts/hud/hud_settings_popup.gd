class_name HudSettingsPopup
extends PopupPanel
## The small settings panel behind the gear button: animation speed, skipping while unfocused, sound on or off
## and three volumes. Writes through the `Settings` autoload, which saves and applies them.

const VOLUMES := {"sfx_volume": "Effects", "ambience_volume": "Ambience", "music_volume": "Music"}


func _init() -> void:
	var column := HudUi.vbox(8)
	column.custom_minimum_size = Vector2(320.0, 0.0)
	column.add_child(HudUi.label("Settings", &"SubheadingLabel"))
	column.add_child(_speed_row())
	column.add_child(_toggle("Skip animations when unfocused", "skip_when_unfocused"))
	column.add_child(_toggle("Sound", "sound_enabled"))
	for key: String in VOLUMES:
		column.add_child(_volume_row(key, VOLUMES[key]))
	add_child(column)


func _speed_row() -> HBoxContainer:
	var row := HudUi.hbox(8)
	var title := HudUi.label("Animation speed")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var choice := OptionButton.new()
	for name: String in Settings.SPEED_NAMES:
		choice.add_item(name)
	choice.select(Settings.animation_speed)
	choice.item_selected.connect(func(index: int) -> void: Settings.update("animation_speed", index))
	row.add_child(choice)
	return row


func _toggle(text: String, key: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = text
	toggle.button_pressed = Settings.get(key)
	toggle.toggled.connect(func(pressed: bool) -> void: Settings.update(key, pressed))
	return toggle


func _volume_row(key: String, text: String) -> HBoxContainer:
	var row := HudUi.hbox(8)
	var title := HudUi.label(text)
	title.custom_minimum_size = Vector2(90.0, 0.0)
	row.add_child(title)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Settings.get(key)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(160.0, 24.0)
	slider.value_changed.connect(func(value: float) -> void: Settings.update(key, value))
	row.add_child(slider)
	return row
