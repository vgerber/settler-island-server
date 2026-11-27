class_name HudActionBar
extends VBoxContainer
## The turn buttons. Every button is always shown and enabled only when a matching legal action exists.
## The primary slot is Roll or End turn (one place, so it never moves); Road, Settlement and City arm
## build mode; Card buys a development card and Trade opens the trade dialog.

signal act_requested(script: Script)
signal build_requested(script: Script)
signal trade_requested

var _primary := HudUi.button("End turn", _on_primary, &"AccentButton")
var _build: Dictionary[Script, Button] = {}
var _card := HudUi.button("Card", _on_card)
var _trade := HudUi.button("Trade", trade_requested.emit)
var _primary_script: Script = SiActionEndTurn


func _init() -> void:
	add_theme_constant_override("separation", 6)
	_primary.focus_mode = Control.FOCUS_NONE
	add_child(_primary)
	var builds := HudUi.hbox(6)
	for kind: Array in [["Road", SiActionBuildRoad], ["Settlement", SiActionBuildSettlement], ["City", SiActionBuildCity]]:
		var cost_key: String = kind[0]
		var button := HudUi.button(cost_key, build_requested.emit.bind(kind[1]), &"BuildButton")
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "%s costs %s" % [cost_key, HudText.counts(SiLimits.COSTS[cost_key])]
		_build[kind[1]] = button
		builds.add_child(button)
	add_child(builds)
	var others := HudUi.hbox(6)
	for button: Button in [_card, _trade]:
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		others.add_child(button)
	_card.tooltip_text = "Development card costs %s" % HudText.counts(SiLimits.COSTS["DevelopmentCard"])
	add_child(others)


func show_actions(legal: HudLegal, armed: Script) -> void:
	_primary_script = SiActionRollDice if legal.has(SiActionRollDice) else SiActionEndTurn
	_primary.text = "Roll dice" if _primary_script == SiActionRollDice else "End turn"
	_primary.disabled = not legal.has(_primary_script)
	for script in _build:
		_build[script].disabled = not legal.has(script)
		_build[script].set_pressed_no_signal(script == armed)
	_card.disabled = not legal.has(SiActionBuyDevelopmentCard)
	_trade.disabled = not (legal.has(SiActionBankTrade) or legal.can_offer_trade())


func _on_primary() -> void:
	act_requested.emit(_primary_script)


func _on_card() -> void:
	act_requested.emit(SiActionBuyDevelopmentCard)


## One scale bounce of Roll or End turn when it becomes the thing to press.
func bounce_primary() -> void:
	_primary.pivot_offset = _primary.size / 2.0
	var tween := _primary.create_tween()
	tween.tween_property(_primary, "scale", Vector2.ONE * 1.12, 0.1)
	tween.tween_property(_primary, "scale", Vector2.ONE, 0.12)
