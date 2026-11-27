class_name HudDevRow
extends HBoxContainer
## The own development cards, one button per kind with its count. A card is enabled when its play action is
## legal; cards bought this turn are tagged "new". In compact mode the cards collapse into one stacked button
## that opens them in a popover over the bottom bar.

signal play_requested(card: String)

## The action variant that plays each card; victory points are never played.
static var play_actions := {
	SiDevelopmentCard.KNIGHT: SiActionPlayKnight,
	SiDevelopmentCard.ROAD_BUILDING: SiActionPlayRoadBuilding,
	SiDevelopmentCard.YEAR_OF_PLENTY: SiActionPlayYearOfPlenty,
	SiDevelopmentCard.MONOPOLY: SiActionPlayMonopoly,
}

var _buttons: Dictionary[String, Button] = {}
var _cards_box := HudUi.hbox(6)
var _popover := HudUi.panel(&"DialogPanel")
var _popover_box := HudUi.hbox(6)
var _stack_button := HudUi.button("Dev 0", _toggle_popover)
var _empty_label := HudUi.label("No development cards", &"CreamMutedLabel")
var _compact := false
var _holding := 0


func _init() -> void:
	add_theme_constant_override("separation", 6)
	for card in SiDevelopmentCard.VALUES:
		var button := HudUi.button("", _request.bind(card))
		button.custom_minimum_size = Vector2(76.0, 100.0)
		button.focus_mode = Control.FOCUS_NONE
		_buttons[card] = button
		_cards_box.add_child(button)
	_popover.top_level = true
	_popover.hide()
	_popover.add_child(_popover_box)
	_stack_button.custom_minimum_size = Vector2(76.0, 100.0)
	_stack_button.focus_mode = Control.FOCUS_NONE
	_stack_button.hide()
	_empty_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_cards_box)
	add_child(_stack_button)
	add_child(_empty_label)
	add_child(_popover)


func set_compact(compact: bool) -> void:
	_compact = compact
	var holder := _popover_box if compact else _cards_box
	for button in _buttons.values():
		button.reparent(holder, false)
	_popover.hide()
	_apply_visibility()


func show_cards(own: SiOwnView, state: EventPlayer) -> void:
	_holding = 0
	for card in SiDevelopmentCard.VALUES:
		var fresh := 0 if own == null else own.new_development_cards.count(card)
		var held := 0 if own == null else own.development_cards.count(card) + fresh
		_holding += held
		var button := _buttons[card]
		button.visible = held > 0
		button.text = "%s\nx%d%s" % [HudText.card_name(card), held, "  new" if fresh > 0 else ""]
		button.disabled = not play_actions.has(card) or state.legal_of(play_actions[card]).is_empty()
		button.tooltip_text = "Cannot be played" if card == SiDevelopmentCard.VICTORY_POINT else ""
	_stack_button.text = "Dev %d" % _holding
	_apply_visibility()


func _apply_visibility() -> void:
	_cards_box.visible = not _compact
	_stack_button.visible = _compact and _holding > 0
	_empty_label.visible = _holding == 0
	if _holding == 0:
		_popover.hide()


func _toggle_popover() -> void:
	_popover.visible = not _popover.visible
	if _popover.visible:
		_popover.reset_size()
		_popover.global_position = _stack_button.global_position - Vector2(0.0, _popover.size.y + 8.0)


func _request(card: String) -> void:
	_popover.hide()
	play_requested.emit(card)
