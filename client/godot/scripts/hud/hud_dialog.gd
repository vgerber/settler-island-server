class_name HudDialog
extends PanelContainer
## A titled dialog card over the board: a body for its controls and a row of buttons. Hidden until used.

var body: VBoxContainer = HudUi.vbox(10)
var buttons: HBoxContainer = HudUi.hbox(10)
## The action variant this dialog works on; the HUD closes it once no such action is legal.
var depends_on: Script = null

var _title_label := HudUi.label("", &"HeadingLabel")


func _init() -> void:
	theme_type_variation = &"DialogPanel"
	custom_minimum_size = Vector2(440, 0)
	var column := HudUi.vbox(14)
	column.add_child(_title_label)
	column.add_child(body)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(buttons)
	add_child(column)
	hide()


func set_title(text: String) -> void:
	_title_label.text = text
