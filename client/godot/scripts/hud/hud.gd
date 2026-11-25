class_name Hud
extends Control
## Hand, players, dice, bank, log and the turn buttons from the legal actions (step 3 of
## doc/plans/godot-client.md). Takes a column on the right and a bar at the bottom; the rest is the
## board's, so this node lets the mouse through. Reads only its `GameState`, never `Net`.

signal leave_requested

const COLUMN_WIDTH := 380.0
const BAR_HEIGHT := 200.0
const BANK_RATE := 4
const GENERIC_PORT_RATE := 3
const SPECIFIC_PORT_RATE := 2
const COSTS := "Road: Clay + Wood    Settlement: Clay + Wood + Sheep + Wheat    City: 2 Wheat + 3 Ore    Development card: Sheep + Wheat + Ore"

var state: GameState = null

var _turn_label: Label = HudUi.label("", 22)
var _phase_label: Label = HudUi.label("", 16, HudUi.MUTED_COLOR)
var _dice_row: HBoxContainer = HudUi.hbox(8)
var _bank_row: HBoxContainer = HudUi.hbox(4)
var _players := HudPlayers.new()
var _trade_panel := HudTradePanel.new()
var _log := HudEventLog.new()
var _hand := HudHand.new()
var _hint_label: Label = HudUi.label("", 17, Color(1, 0.9, 0.6))
var _action_flow := HFlowContainer.new()
var _discard_dialog := HudDiscardDialog.new()
var _picker := HudResourcePicker.new()
var _steal_list := HudActionList.new()
var _trade_builder := HudTradeBuilder.new()
var _game_over := HudGameOver.new()
## `[button: Button, is_available: Callable]` for every button of the action bar.
var _action_buttons: Array = []
var _last_dice: Array[int] = []
## The overlay opens once by itself at the end; afterwards a button brings it back.
var _result_shown := false
var _refresh_queued := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_build_column())
	add_child(_build_bar())
	add_child(_build_dialog_area())
	_game_over.leave_requested.connect(leave_requested.emit)
	# Closing the overlay brings back the "Show result" button.
	_game_over.visibility_changed.connect(_queue_refresh)
	add_child(_game_over)


func bind(game_state: GameState) -> void:
	state = game_state
	state.changed.connect(_on_changed)
	_log.add_events(state.events, state.seat)
	_refresh()


func _on_changed(events: Array[SiEvent]) -> void:
	_log.add_events(events, state.seat)
	_remember_dice(events)
	_queue_refresh()


## Deferred so a button press that acts never sees its own row rebuilt under it.
func _queue_refresh() -> void:
	if state == null or _refresh_queued:
		return
	_refresh_queued = true
	_refresh.call_deferred()


func _refresh() -> void:
	_refresh_queued = false
	var view := state.view
	_refresh_header(view)
	_refresh_bank(view)
	_players.show_players(view, state.seat)
	_trade_panel.show_trade(state)
	_hand.show_hand(view.own)
	_hint_label.text = _hint()
	for entry: Array in _action_buttons:
		(entry[0] as Button).visible = bool((entry[1] as Callable).call())
	_refresh_dialogs()
	if state.is_finished() and not _result_shown:
		_result_shown = true
		_game_over.show_result(view, state.seat)


func _build_column() -> PanelContainer:
	var column_panel := HudUi.panel(HudUi.PANEL_COLOR, 0, 14)
	column_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	column_panel.offset_left = -COLUMN_WIDTH
	var column := HudUi.vbox(10)
	column.add_child(_turn_label)
	_phase_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_phase_label)
	column.add_child(_dice_row)
	column.add_child(HudUi.label("Bank", 14, HudUi.MUTED_COLOR))
	column.add_child(_bank_row)
	column.add_child(HSeparator.new())
	column.add_child(_players)
	column.add_child(_trade_panel)
	_trade_panel.chosen.connect(_act)
	column.add_child(HSeparator.new())
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_log)
	column_panel.add_child(column)
	return column_panel


func _build_bar() -> PanelContainer:
	var bar_panel := HudUi.panel(HudUi.PANEL_COLOR, 0, 12)
	bar_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar_panel.offset_top = -BAR_HEIGHT
	bar_panel.offset_right = -COLUMN_WIDTH
	var row := HudUi.hbox(16)
	row.add_child(_hand)
	row.add_child(VSeparator.new())
	var actions := HudUi.vbox(8)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	actions.add_child(_hint_label)
	_action_flow.add_theme_constant_override("h_separation", 8)
	_action_flow.add_theme_constant_override("v_separation", 8)
	_action_flow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	actions.add_child(_action_flow)
	var costs := HudUi.label(COSTS, 12, HudUi.MUTED_COLOR)
	costs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	actions.add_child(costs)
	row.add_child(actions)
	bar_panel.add_child(row)
	_build_action_buttons()
	return bar_panel


func _build_action_buttons() -> void:
	_add_action_button("Roll dice", _has_legal.bind(SiActionRollDice), _act_first.bind(SiActionRollDice), true)
	_add_action_button("Play knight", _has_legal.bind(SiActionPlayKnight), _act_first.bind(SiActionPlayKnight))
	_add_action_button("Play road building", _has_legal.bind(SiActionPlayRoadBuilding), _act_first.bind(SiActionPlayRoadBuilding))
	_add_action_button("Year of plenty...", _has_legal.bind(SiActionPlayYearOfPlenty), _open_year_of_plenty)
	_add_action_button("Monopoly...", _has_legal.bind(SiActionPlayMonopoly), _open_monopoly)
	_add_action_button("Buy development card", _has_legal.bind(SiActionBuyDevelopmentCard), _act_first.bind(SiActionBuyDevelopmentCard))
	_add_action_button("Bank trade...", _has_legal.bind(SiActionBankTrade), _open_bank_trade)
	_add_action_button("Offer trade...", _can_offer_trade, _open_trade_builder)
	_add_action_button("End turn", _has_legal.bind(SiActionEndTurn), _act_first.bind(SiActionEndTurn), true)
	_add_action_button("Show result", _can_show_result, _game_over.show)
	_add_action_button("Back to lobbies", _is_finished, leave_requested.emit, true)


func _add_action_button(text: String, is_available: Callable, on_pressed: Callable, prominent: bool = false) -> void:
	var created := HudUi.button(text, on_pressed)
	created.custom_minimum_size = Vector2(0, 40)
	if prominent:
		created.add_theme_color_override("font_color", Color(1, 0.88, 0.45))
		created.add_theme_font_size_override("font_size", 18)
	created.hide()
	_action_flow.add_child(created)
	_action_buttons.append([created, is_available])


func _build_dialog_area() -> Control:
	var area := Control.new()
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	area.offset_right = -COLUMN_WIDTH
	area.offset_bottom = -BAR_HEIGHT
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for dialog: HudDialog in [_discard_dialog, _picker, _steal_list, _trade_builder]:
		center.add_child(dialog)
	_discard_dialog.chosen.connect(_act)
	_picker.chosen.connect(_act)
	_steal_list.chosen.connect(_act)
	_trade_builder.offered.connect(_send_offer)
	area.add_child(center)
	return area


func _refresh_header(view: SiPlayerView) -> void:
	if state.is_finished():
		_turn_label.text = "Game over"
		_turn_label.add_theme_color_override("font_color", Color.WHITE)
	elif state.is_my_turn():
		_turn_label.text = "Turn %d: your turn" % view.turn_number
		_turn_label.add_theme_color_override("font_color", HudText.seat_color(state.seat))
	else:
		_turn_label.text = "Turn %d: %s plays" % [view.turn_number, HudText.seat_name(view.current, state.seat)]
		_turn_label.add_theme_color_override("font_color", HudText.seat_color(view.current))
	_phase_label.text = HudText.phase_text(view.phase, state.seat)


func _remember_dice(events: Array[SiEvent]) -> void:
	for event in events:
		if event is SiEventDiceRolled:
			var dice := event as SiEventDiceRolled
			_last_dice = [dice.first, dice.second]


func _refresh_bank(view: SiPlayerView) -> void:
	HudUi.clear(_bank_row)
	for index in SiResource.VALUES.size():
		var count: int = view.bank[index] if index < view.bank.size() else 0
		_bank_row.add_child(HudUi.resource_tile(SiResource.VALUES[index], count, Vector2(52, 58)))
	var cards := HudUi.label("%d\ndev" % view.development_cards_left, 15, HudUi.MUTED_COLOR)
	cards.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cards.custom_minimum_size = Vector2(52, 0)
	_bank_row.add_child(cards)
	_refresh_dice()


func _refresh_dice() -> void:
	HudUi.clear(_dice_row)
	_dice_row.add_child(HudUi.label("Dice", 15, HudUi.MUTED_COLOR))
	if _last_dice.is_empty():
		_dice_row.add_child(HudUi.label("not rolled yet", 15, HudUi.MUTED_COLOR))
		return
	for value in _last_dice:
		var die := HudUi.panel(Color(0.95, 0.93, 0.88), 6, 2)
		die.custom_minimum_size = Vector2(40, 40)
		var pips := HudUi.label(str(value), 22, Color(0.1, 0.1, 0.1))
		pips.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pips.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		die.add_child(pips)
		_dice_row.add_child(die)
	var sum := _last_dice[0] + _last_dice[1]
	_dice_row.add_child(HudUi.label("= %d" % sum, 24, Color(1, 0.4, 0.35) if sum == 7 else Color.WHITE))


func _refresh_dialogs() -> void:
	for dialog: HudDialog in [_picker, _steal_list, _trade_builder]:
		if dialog.visible and not _has_legal(dialog.depends_on):
			dialog.hide()
	var hand: Array[int] = [] if state.view.own == null else state.view.own.hand
	_discard_dialog.offer(state.legal_of(SiActionDiscard), hand)
	var steals := state.legal_of(SiActionSteal)
	if not steals.is_empty():
		_open_steal(steals)


func _hint() -> String:
	if state.is_finished():
		return "The game is over."
	if _has_legal(SiActionPlaceSettlement):
		return "Click a highlighted corner on the board to place your settlement."
	if _has_legal(SiActionPlaceRoad):
		return "Click a highlighted edge next to your new settlement to place a road."
	if _has_legal(SiActionMoveRobber):
		return "Click a tile on the board to move the robber there."
	if state.view.phase is SiPhaseRoadBuilding and _has_legal(SiActionBuildRoad):
		return "Click highlighted edges on the board for your free roads."
	if _has_legal(SiActionDiscard):
		return "Choose the cards to give up."
	if _has_legal(SiActionSteal):
		return "Choose whom to rob."
	if _has_legal(SiActionAcceptTrade) or _has_legal(SiActionRejectTrade):
		return "Answer the trade offer on the right."
	if _has_legal(SiActionCancelTrade):
		return "Waiting for answers: trade with a seat that accepts, or withdraw the offer."
	if _has_legal(SiActionRollDice):
		return "Roll the dice to start your turn."
	if _has_legal(SiActionEndTurn):
		return _main_hint()
	return _waiting_hint()


func _main_hint() -> String:
	var builds: PackedStringArray = []
	if _has_legal(SiActionBuildRoad):
		builds.append("roads")
	if _has_legal(SiActionBuildSettlement):
		builds.append("settlements")
	if _has_legal(SiActionBuildCity):
		builds.append("cities")
	if builds.is_empty():
		return "Nothing to build right now: trade, buy a card or end the turn."
	return "You can build %s: click a highlighted spot on the board." % ", ".join(builds)


func _waiting_hint() -> String:
	if state.view.phase is SiPhaseDiscard:
		return "Waiting for the others to discard."
	return "Waiting for %s." % HudText.seat_name(state.view.current, state.seat)


func _has_legal(script: Script) -> bool:
	return not state.legal_of(script).is_empty()


func _is_finished() -> bool:
	return state.is_finished()


func _can_show_result() -> bool:
	return state.is_finished() and not _game_over.visible


## Offers are not listed among the legal actions; ending the turn is legal exactly when one may offer.
func _can_offer_trade() -> bool:
	var own := state.view.own
	return _has_legal(SiActionEndTurn) and own != null and HudText.total(own.hand) > 0


func _act(action: SiAction) -> void:
	state.act(action)


func _act_first(script: Script) -> void:
	var matching := state.legal_of(script)
	if not matching.is_empty():
		state.act(matching[0])


func _send_offer(action: SiActionOfferTrade) -> void:
	if not _can_offer_trade():
		return
	# `GameState.act` only sends listed actions and offers are never listed.
	state.client.send_act(action)


func _open_steal(steals: Array[SiAction]) -> void:
	var entries: Array = []
	for action in steals:
		var victim := (action as SiActionSteal).victim
		var cards := state.view.players[victim].resource_count
		entries.append(["%s  (%d cards)" % [HudText.seat_name(victim, state.seat), cards], action])
	_steal_list.open("Rob a player", entries, SiActionSteal)


func _open_trade_builder() -> void:
	_trade_builder.open(state.view.own.hand, state.view.players.size(), state.seat, SiActionEndTurn)


func _open_monopoly() -> void:
	var rows: Array[String] = ["Resource"]
	_open_picker("Monopoly: take one resource from everyone", SiActionPlayMonopoly, ["resource"], rows, _describe_monopoly)


func _open_year_of_plenty() -> void:
	var rows: Array[String] = ["First resource", "Second resource"]
	_open_picker("Year of plenty: take two resources", SiActionPlayYearOfPlenty, ["first", "second"], rows, _describe_year_of_plenty)


func _open_bank_trade() -> void:
	var rows: Array[String] = ["Give", "Receive"]
	_open_picker("Trade with the bank", SiActionBankTrade, ["give", "receive"], rows, _describe_bank_trade)


## One picker row per action property; each row offers what the legal actions allow after the earlier picks.
func _open_picker(title: String, script: Script, properties: Array[String], rows: Array[String], describe: Callable) -> void:
	_picker.open(title, rows, _picker_options.bind(script, properties), _picker_action.bind(script, properties), describe, script)


func _picker_options(row: int, picks: Array[String], script: Script, properties: Array[String]) -> Array[String]:
	var filter := {}
	for earlier in row:
		filter[properties[earlier]] = picks[earlier]
	return _distinct(script, properties[row], filter)


func _picker_action(picks: Array[String], script: Script, properties: Array[String]) -> SiAction:
	var filter := {}
	for index in properties.size():
		filter[properties[index]] = picks[index]
	return _find(script, filter)


func _describe_monopoly(action: SiAction) -> String:
	return "Take every %s the others hold." % (action as SiActionPlayMonopoly).resource


func _describe_year_of_plenty(action: SiAction) -> String:
	var plenty := action as SiActionPlayYearOfPlenty
	return "Take 1 %s and 1 %s from the bank." % [plenty.first, plenty.second]


func _describe_bank_trade(action: SiAction) -> String:
	var trade := action as SiActionBankTrade
	return "Give %d %s, get 1 %s." % [_bank_rate(trade.give), trade.give, trade.receive]


## The distinct values of `property` among the legal actions of `script` that match `filter`.
func _distinct(script: Script, property: String, filter: Dictionary) -> Array[String]:
	var values: Array[String] = []
	for action in state.legal_of(script):
		if _matches(action, filter) and not values.has(str(action.get(property))):
			values.append(str(action.get(property)))
	return values


## The legal action of `script` whose properties equal `filter`, or null.
func _find(script: Script, filter: Dictionary) -> SiAction:
	for action in state.legal_of(script):
		if _matches(action, filter):
			return action
	return null


func _matches(action: SiAction, filter: Dictionary) -> bool:
	for property: String in filter:
		if str(action.get(property)) != str(filter[property]):
			return false
	return true


## Display only: the server prices the trade; this mirrors its port rule to show the amount.
func _bank_rate(resource: String) -> int:
	var board := state.view.board
	var rate := BANK_RATE
	for corner in mini(board.corners.size(), board.buildings.size()):
		var building: SiBuilding = board.buildings[corner]
		if building == null or building.seat != state.seat:
			continue
		var port := board.corners[corner].port
		if port is SiPortGeneric:
			rate = mini(rate, GENERIC_PORT_RATE)
		elif port is SiPortSpecific and (port as SiPortSpecific).value == resource:
			rate = mini(rate, SPECIFIC_PORT_RATE)
	return rate
