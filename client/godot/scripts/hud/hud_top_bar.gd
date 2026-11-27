class_name HudTopBar
extends PanelContainer
## The strip over the board: whose turn in which phase, the prompt for the own seat, the bank's cards and
## the development deck. Built once; `show_state` only sets texts.

signal results_requested
signal settings_requested

var _chip := HudSeatChip.new(0, 24.0)
var _banner := HudUi.label("", &"CreamCountLabel")
var _prompt := HudUi.label("", &"CreamLabel")
var _bank_counts: Array[Label] = []
var _deck_count := HudUi.label("0", &"CreamCountLabel")
var _results_button := HudUi.button("Results", results_requested.emit, &"GhostButton")


func _init() -> void:
	theme_type_variation = &"TopBarPanel"
	var row := HudUi.hbox(16)
	var turn := HudUi.hbox(8)
	turn.add_child(_chip)
	turn.add_child(_banner)
	row.add_child(turn)
	_prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.clip_text = true
	row.add_child(_prompt)
	row.add_child(_bank_row())
	_results_button.hide()
	row.add_child(_results_button)
	var gear := HudGearButton.new()
	gear.pressed.connect(settings_requested.emit)
	row.add_child(gear)
	add_child(row)
	custom_minimum_size = Vector2(0.0, 48.0)


func show_state(state: EventPlayer, names: SeatNames, prompt: String, results_available: bool) -> void:
	var view := state.shown_view
	_chip.seat = view.current
	_chip.visible = not state.is_finished()
	if state.is_finished():
		_banner.text = "Game over"
	else:
		var who := "your turn" if state.is_my_turn() else names.name_of(view.current)
		_banner.text = "%s - %s" % [who, HudText.phase_name(view.phase)]
	_prompt.text = prompt
	for index in _bank_counts.size():
		_bank_counts[index].text = str(view.bank[index] if index < view.bank.size() else 0)
	_deck_count.text = str(view.development_cards_left)
	_results_button.visible = results_available


func _bank_row() -> HBoxContainer:
	var row := HudUi.hbox(10)
	row.tooltip_text = "The bank's cards and the development deck"
	for resource in SiResource.VALUES:
		var chip := HudUi.hbox(4)
		chip.add_child(HudResourceIcon.new(resource, 28.0))
		var count := HudUi.label("0", &"CreamCountLabel")
		chip.add_child(count)
		_bank_counts.append(count)
		row.add_child(chip)
	var deck := HudUi.hbox(4)
	deck.add_child(HudUi.label("Dev", &"CreamLabel"))
	deck.add_child(_deck_count)
	row.add_child(deck)
	return row
