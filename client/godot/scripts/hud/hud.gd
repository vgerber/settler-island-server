class_name Hud
extends Control
## The game screen's overlay (doc/design/layout.md): top bar, opponents and log at the right, hand, dice and
## actions at the bottom. The board's rect is `board_slot`, the free area in the middle; dialogs, the open trade
## and the result live over it. Every widget is built once and updated on `GameState.changed`. Reads only its
## `GameState`, never `Net`; legal actions decide what is enabled.

signal leave_requested
## The action variants whose board targets are shown: everything, or only the armed build kind in `Main`.
signal target_filter_changed(kinds: Array[Script])

const SIDE_WIDTH := 340.0
const BOTTOM_HEIGHT := 176.0
## Windows lower than this many real pixels get the compact layout.
const COMPACT_BELOW := 800


var state: GameState = null
var _build_keys := {KEY_1: SiActionBuildRoad, KEY_2: SiActionBuildSettlement, KEY_3: SiActionBuildCity}
var names := SeatNames.new()
## The free middle of the screen; the board is laid over exactly this rect.
var board_slot := Control.new()

var _legal: HudLegal = null
var _top_bar := HudTopBar.new()
var _players := HudPlayers.new()
var _log := HudEventLog.new()
var _log_panel := HudUi.panel()
var _log_button := HudUi.button("Log", _toggle_log)
var _side_column := HudUi.vbox(8)
var _own_summary: HudOwnSummary = null
var _hand := HudHand.new()
var _dev_row := HudDevRow.new()
var _dice := HudDice.new()
var _action_bar := HudActionBar.new()
var _trade_card := HudTradePanel.new()
var _discard_dialog := HudDiscardDialog.new()
var _picker := HudResourcePicker.new()
var _steal_list := HudActionList.new()
var _trade_dialog := HudTradeDialog.new()
var _game_over := HudGameOver.new()
var _bottom_row := HudUi.hbox(20)
var _last_dice: Array[int] = []
## The build kind (an action variant) that board clicks place, or null.
var _armed: Script = null
var _shift_on_click := false
var _shown_filter: Array[Script] = []
var _filter_sent := false
var _unread_lines := 0
## The overlay opens once by itself at the end; afterwards "Results" brings it back.
var _result_shown := false
var _compact := false
var _refresh_queued := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layout := HudUi.vbox(0)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(_top_bar)
	layout.add_child(_build_middle())
	layout.add_child(_build_bottom_bar())
	add_child(layout)
	_top_bar.results_requested.connect(_game_over.show)
	# Closing the overlay brings back the "Results" button.
	_game_over.visibility_changed.connect(_queue_refresh)
	_game_over.leave_requested.connect(leave_requested.emit)
	board_slot.add_child(_game_over)
	_connect_actions()


func _ready() -> void:
	get_window().size_changed.connect(_apply_compact)
	_apply_compact()


## Starts showing `game_state`. `seat_names` falls back to "Seat N" when no lobby is known.
func bind(game_state: GameState, seat_names: SeatNames = null) -> void:
	state = game_state
	names = seat_names if seat_names != null else SeatNames.new()
	names.own_seat = state.seat
	_legal = HudLegal.new(state)
	_own_summary.set_seat(names.own_seat)
	state.changed.connect(_on_changed)
	_unread_lines = 0
	_log.add_events(state.events, names)
	_refresh()


## Takes the seats of a newer `LobbyState`, as players leave and rejoin during the game.
func show_names(seat_names: SeatNames) -> void:
	names = seat_names
	_queue_refresh()


func _input(event: InputEvent) -> void:
	if state == null or not is_visible_in_tree():
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed:
		_shift_on_click = click.shift_pressed
		if click.button_index == MOUSE_BUTTON_RIGHT and _armed != null:
			_disarm()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE and _armed != null:
		_disarm()
	elif _build_keys.has(key.keycode):
		_arm(_build_keys[key.keycode])
	elif key.keycode == KEY_SPACE and _legal.has(SiActionRollDice):
		_act_first(SiActionRollDice)
	elif key.keycode in [KEY_ENTER, KEY_KP_ENTER] and _legal.has(SiActionEndTurn):
		_act_first(SiActionEndTurn)
	else:
		return
	get_viewport().set_input_as_handled()


func _build_middle() -> HBoxContainer:
	var middle := HudUi.hbox(0)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_slot.clip_contents = true
	board_slot.add_child(_build_dialog_area())
	middle.add_child(board_slot)
	middle.add_child(_build_side_column())
	return middle


func _build_side_column() -> VBoxContainer:
	_side_column.custom_minimum_size = Vector2(SIDE_WIDTH, 0.0)
	_side_column.add_child(_players)
	_side_column.add_child(_log_button)
	_log_button.hide()
	_log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := HudUi.vbox(6)
	var header := HudUi.hbox(8)
	var title := HudUi.label("Log", &"SubheadingLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	column.add_child(header)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_log)
	_log_panel.add_child(column)
	_side_column.add_child(_log_panel)
	return _side_column


func _build_bottom_bar() -> PanelContainer:
	var bar := HudUi.panel(&"BottomBarPanel")
	bar.custom_minimum_size = Vector2(0.0, BOTTOM_HEIGHT)
	_own_summary = HudOwnSummary.new(0)
	_bottom_row.add_child(_own_summary)
	_bottom_row.add_child(_hand)
	_bottom_row.add_child(VSeparator.new())
	_bottom_row.add_child(_dev_row)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bottom_row.add_child(spacer)
	_dice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bottom_row.add_child(_dice)
	_action_bar.custom_minimum_size = Vector2(330.0, 0.0)
	_bottom_row.add_child(_action_bar)
	bar.add_child(_bottom_row)
	return bar


## The modal dialogs centred over the board, the trade card on top of it.
func _build_dialog_area() -> Control:
	var area := Control.new()
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for dialog: HudDialog in [_discard_dialog, _picker, _steal_list, _trade_dialog]:
		center.add_child(dialog)
	area.add_child(center)
	_trade_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12)
	area.add_child(_trade_card)
	return area


func _connect_actions() -> void:
	_action_bar.act_requested.connect(_act_first)
	_action_bar.build_requested.connect(_toggle_build)
	_action_bar.trade_requested.connect(_open_trade)
	_dev_row.play_requested.connect(_play_card)
	_trade_card.chosen.connect(_act)
	_discard_dialog.chosen.connect(_act)
	_picker.chosen.connect(_act)
	_steal_list.chosen.connect(_act)
	_trade_dialog.chosen.connect(_act)
	_trade_dialog.offered.connect(_send_offer)


## Wide windows keep the full layout; below 800 px of height the compact one drops detail rows, folds the
## development cards into one stack and the log into a popup.
func _apply_compact() -> void:
	_compact = get_window().size.y < COMPACT_BELOW
	_players.set_compact(_compact)
	_hand.set_compact(_compact)
	_dev_row.set_compact(_compact)
	_log_button.visible = _compact
	_set_log_open(not _compact)
	if state != null:
		_queue_refresh()


func _toggle_log() -> void:
	_set_log_open(not _log_panel.visible)


## In compact mode the log is a popup over the side column; in the full layout it is the column's last panel.
func _set_log_open(open: bool) -> void:
	_log_panel.visible = open
	_log_panel.top_level = open and _compact
	if open and _compact:
		_log_panel.global_position = _side_column.global_position
		_log_panel.size = _side_column.size
	if open:
		_unread_lines = 0
	_update_log_button()


func _update_log_button() -> void:
	_log_button.text = "Log (%d new)" % _unread_lines if _unread_lines > 0 else "Log"


func _on_changed(events: Array[SiEvent]) -> void:
	var added := _log.add_events(events, names)
	if _compact and not _log_panel.visible:
		_unread_lines += added
		_update_log_button()
	_remember_dice(events)
	if _armed != null and not _shift_on_click and _built_by_own_seat(events):
		_armed = null
	_queue_refresh()


func _built_by_own_seat(events: Array[SiEvent]) -> bool:
	for event in events:
		var built := event is SiEventSettlementPlaced or event is SiEventRoadPlaced or event is SiEventCityBuilt
		if built and int(event.get("seat")) == names.own_seat:
			return true
	return false


func _remember_dice(events: Array[SiEvent]) -> void:
	for event in events:
		if event is SiEventDiceRolled:
			var dice := event as SiEventDiceRolled
			_last_dice = [dice.first, dice.second]


## Deferred so a button press that acts never sees its widgets change under it.
func _queue_refresh() -> void:
	if state == null or _refresh_queued:
		return
	_refresh_queued = true
	_refresh.call_deferred()


func _refresh() -> void:
	_refresh_queued = false
	_keep_armed_kind_valid()
	var view := state.view
	var prompt := HudText.prompt(state, names, _armed)
	var away := names.away_note()
	if not away.is_empty() and not state.is_finished():
		prompt = away if prompt.is_empty() else "%s  |  %s" % [prompt, away]
	var results_available := state.is_finished() and not _game_over.visible
	_top_bar.show_state(state, names, prompt, results_available)
	_players.show_players(view, names)
	_own_summary.show_own(view, names)
	_hand.show_hand(view.own)
	_dev_row.show_cards(view.own, state)
	_dice.show_roll(_last_dice)
	_action_bar.show_actions(_legal, _armed)
	_trade_card.show_trade(state, names)
	_refresh_dialogs()
	_refresh_target_filter()
	if state.is_finished() and not _result_shown:
		_result_shown = true
		_game_over.show_result(view, names)


## Build mode ends with the Main phase; a kind that stops being legal (cards spent) disarms too.
func _keep_armed_kind_valid() -> void:
	if _armed == null:
		return
	if not state.view.phase is SiPhaseMain:
		_armed = null
	# An empty list is the moment between an action and its answer, not a verdict.
	elif not state.legal_actions.is_empty() and not _legal.has(_armed):
		_armed = null


func _refresh_target_filter() -> void:
	var kinds: Array[Script] = BoardTarget.all_scripts
	if state.view.phase is SiPhaseMain:
		kinds = []
		if _armed != null:
			kinds.append(_armed)
	if not _filter_sent or kinds != _shown_filter:
		_filter_sent = true
		_shown_filter = kinds
		target_filter_changed.emit(kinds)


func _refresh_dialogs() -> void:
	# Between an action and its answer nothing is legal; dialogs stay until the answer says otherwise.
	if not state.legal_actions.is_empty():
		for dialog: HudDialog in [_picker, _steal_list, _trade_dialog]:
			if dialog.visible and not _legal.has(dialog.depends_on):
				dialog.hide()
	if _trade_dialog.visible:
		_trade_dialog.refresh(_legal)
	var hand: Array[int] = [] if state.view.own == null else state.view.own.hand
	_discard_dialog.offer(state.legal_of(SiActionDiscard), hand)
	var steals := state.legal_of(SiActionSteal)
	if not steals.is_empty() and not _steal_list.visible:
		_open_steal(steals)


func _arm(script: Script) -> void:
	if state.view.phase is SiPhaseMain and _legal.has(script):
		_armed = script
		_queue_refresh()


func _disarm() -> void:
	_armed = null
	_queue_refresh()


func _toggle_build(script: Script) -> void:
	if _armed == script:
		_disarm()
		return
	_arm(script)


func _act(action: SiAction) -> void:
	state.act(action)


func _act_first(script: Script) -> void:
	var matching := state.legal_of(script)
	if not matching.is_empty():
		state.act(matching[0])


func _send_offer(action: SiActionOfferTrade) -> void:
	if _legal.can_offer_trade():
		state.offer_trade(action)


func _play_card(card: String) -> void:
	match card:
		SiDevelopmentCard.YEAR_OF_PLENTY:
			_open_year_of_plenty()
		SiDevelopmentCard.MONOPOLY:
			_open_monopoly()
		_:
			_act_first(HudDevRow.play_actions[card])


func _open_steal(steals: Array[SiAction]) -> void:
	var entries: Array = []
	for action in steals:
		var victim := (action as SiActionSteal).victim
		var cards := state.view.players[victim].resource_count
		entries.append(["%s  (%d cards)" % [names.name_of(victim), cards], action, victim])
	_steal_list.open("Rob a player", entries, SiActionSteal)


func _open_trade() -> void:
	_trade_dialog.open(_legal, state.view.own.hand, state.view.players.size(), names)


func _open_monopoly() -> void:
	var rows: Array[String] = ["Resource"]
	_open_picker("Monopoly: take one resource from everyone", SiActionPlayMonopoly, ["resource"], rows, _describe_monopoly)


func _open_year_of_plenty() -> void:
	var rows: Array[String] = ["First resource", "Second resource"]
	_open_picker("Year of plenty: take two resources", SiActionPlayYearOfPlenty, ["first", "second"], rows, _describe_year_of_plenty)


## One picker row per action property; each row offers what the legal actions allow after the earlier picks.
func _open_picker(title: String, script: Script, properties: Array[String], rows: Array[String], describe: Callable) -> void:
	_picker.open(title, rows, _picker_options.bind(script, properties), _picker_action.bind(script, properties), describe, script)


func _picker_options(row: int, picks: Array[String], script: Script, properties: Array[String]) -> Array[String]:
	var filter := {}
	for earlier in row:
		filter[properties[earlier]] = picks[earlier]
	return _legal.distinct(script, properties[row], filter)


func _picker_action(picks: Array[String], script: Script, properties: Array[String]) -> SiAction:
	var filter := {}
	for index in properties.size():
		filter[properties[index]] = picks[index]
	return _legal.find(script, filter)


func _describe_monopoly(action: SiAction) -> String:
	return "Take every %s the others hold." % (action as SiActionPlayMonopoly).resource


func _describe_year_of_plenty(action: SiAction) -> String:
	var plenty := action as SiActionPlayYearOfPlenty
	return "Take 1 %s and 1 %s from the bank." % [plenty.first, plenty.second]
