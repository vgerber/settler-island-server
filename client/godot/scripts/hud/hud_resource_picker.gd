class_name HudResourcePicker
extends HudDialog
## Picks one resource per row (monopoly: one row; year of plenty and bank trade: two) among the
## choices the legal actions allow, then sends the legal action that matches the picks.

signal chosen(action: SiAction)

var _row_titles: Array[String] = []
## (row: int, picks: Array[String]) -> Array[String]: the resources a row offers given the earlier picks.
var _options: Callable
## (picks: Array[String]) -> SiAction or null.
var _resolve: Callable
## (action: SiAction) -> String, a summary of what the action does.
var _describe: Callable
var _picks: Array[String] = []
var _rows_box: VBoxContainer = HudUi.vbox(8)
var _summary_label: Label = HudUi.label("", 16, HudUi.MUTED_COLOR)
var _send_button: Button = null


func _init() -> void:
	super()
	body.add_child(_rows_box)
	body.add_child(_summary_label)
	_send_button = HudUi.button("Confirm", _send)
	buttons.add_child(HudUi.button("Cancel", hide))
	buttons.add_child(_send_button)


func open(title: String, row_titles: Array[String], options: Callable, resolve: Callable, describe: Callable, script: Script) -> void:
	set_title(title)
	_row_titles = row_titles
	_options = options
	_resolve = resolve
	_describe = describe
	depends_on = script
	_picks = []
	_picks.resize(row_titles.size())
	_rebuild()
	show()


func pick(row: int, resource: String) -> void:
	_picks[row] = resource
	# A later row may no longer offer its pick once an earlier one changed.
	for later in range(row + 1, _picks.size()):
		if not (_options.call(later, _picks) as Array).has(_picks[later]):
			_picks[later] = ""
	# The pressed button is one of the rows being rebuilt.
	_rebuild.call_deferred()


func _send() -> void:
	var action: SiAction = _resolve.call(_picks)
	if action == null:
		return
	hide()
	chosen.emit(action)


func _rebuild() -> void:
	HudUi.clear(_rows_box)
	for row in _row_titles.size():
		_rows_box.add_child(HudUi.label(_row_titles[row], 15, HudUi.MUTED_COLOR))
		_rows_box.add_child(_row_buttons(row))
	var action: SiAction = _resolve.call(_picks)
	_summary_label.text = "" if action == null else str(_describe.call(action))
	_send_button.disabled = action == null


func _row_buttons(row: int) -> HBoxContainer:
	var line := HudUi.hbox(6)
	var allowed: Array = _options.call(row, _picks)
	for resource in SiResource.VALUES:
		var choice := HudUi.button(resource, pick.bind(row, resource))
		choice.toggle_mode = true
		choice.button_pressed = _picks[row] == resource
		choice.disabled = not allowed.has(resource)
		choice.custom_minimum_size = Vector2(76, 40)
		choice.add_theme_color_override("font_color", HudText.resource_color(resource).lightened(0.3))
		line.add_child(choice)
	return line
