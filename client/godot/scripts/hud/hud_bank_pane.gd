class_name HudBankPane
extends VBoxContainer
## The Bank tab of the trade dialog: pick what to give and what to get among the legal `BankTrade`s, the
## rate comes from the server's `bank_rates`. A trade leaves the pane open for chained trades.

signal chosen(action: SiAction)

var _legal: HudLegal
var _give := ""
var _get := ""
var _give_buttons: Dictionary[String, Button] = {}
var _get_buttons: Dictionary[String, Button] = {}
var _summary_label := HudUi.label("", &"MutedLabel")
var _trade_button := HudUi.button("Trade", _send)


func _init() -> void:
	add_theme_constant_override("separation", 8)
	add_child(HudUi.label("Give", &"SmallLabel"))
	add_child(_row(_give_buttons, _pick_give))
	add_child(HudUi.label("Get", &"SmallLabel"))
	add_child(_row(_get_buttons, _pick_get))
	add_child(_summary_label)
	_trade_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	add_child(_trade_button)


## Takes the current legal actions; picks that are no longer possible are dropped.
func show_legal(legal: HudLegal) -> void:
	_legal = legal
	var gives := legal.distinct(SiActionBankTrade, "give", {})
	if not gives.has(_give):
		_give = ""
	var gets: Array[String] = []
	if not _give.is_empty():
		gets = legal.distinct(SiActionBankTrade, "receive", {"give": _give})
	if not gets.has(_get):
		_get = ""
	for resource in SiResource.VALUES:
		_give_buttons[resource].disabled = not gives.has(resource)
		_give_buttons[resource].set_pressed_no_signal(resource == _give)
		_get_buttons[resource].disabled = not gets.has(resource)
		_get_buttons[resource].set_pressed_no_signal(resource == _get)
	var action := _selected()
	_trade_button.disabled = action == null
	_summary_label.text = "Pick what to give and what to get" if action == null else _describe(action as SiActionBankTrade)


func _selected() -> SiAction:
	if _give.is_empty() or _get.is_empty():
		return null
	return _legal.find(SiActionBankTrade, {"give": _give, "receive": _get})


func _describe(trade: SiActionBankTrade) -> String:
	var rate := _legal.bank_rate(trade.give)
	return "Give %d %s, get 1 %s (%d:1)" % [rate, trade.give, trade.receive, rate]


func _pick_give(resource: String) -> void:
	_give = resource
	show_legal(_legal)


func _pick_get(resource: String) -> void:
	_get = resource
	show_legal(_legal)


func _send() -> void:
	var action := _selected()
	if action == null:
		return
	_get = ""
	chosen.emit(action)


func _row(into: Dictionary[String, Button], on_pick: Callable) -> HBoxContainer:
	var line := HudUi.hbox(6)
	for resource in SiResource.VALUES:
		var choice := HudUi.button(resource, on_pick.bind(resource))
		choice.toggle_mode = true
		choice.custom_minimum_size = Vector2(76, 40)
		into[resource] = choice
		line.add_child(choice)
	return line
