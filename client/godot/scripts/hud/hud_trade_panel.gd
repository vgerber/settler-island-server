class_name HudTradePanel
extends PanelContainer
## The open player trade as a card at the top of the board: the terms, one row per addressed seat with its
## answer, and the legal answers of the own seat (accept or decline when addressed, confirm with an accepting
## seat or withdraw when offering). Built once; `show_trade` sets texts and which buttons show.

signal chosen(action: SiAction)

var _title_label := HudUi.label("", &"SubheadingLabel")
var _offer_label := HudUi.label("")
var _answer_rows: Array[HBoxContainer] = []
var _answer_chips: Array[HudSeatChip] = []
var _answer_labels: Array[Label] = []
var _accept := HudUi.button("Accept", _choose_pending.bind(0), &"AccentButton")
var _decline := HudUi.button("Decline", _choose_pending.bind(1))
var _withdraw := HudUi.button("Withdraw", _choose_pending.bind(2))
var _confirms: Array[Button] = []
## The legal action each button sends right now: accept, decline, withdraw, then one confirm per button.
var _actions: Array[SiAction] = [null, null, null]
var _confirm_actions: Array[SiAction] = []


func _init() -> void:
	theme_type_variation = &"TradeCard"
	custom_minimum_size = Vector2(480.0, 0.0)
	var column := HudUi.vbox(6)
	column.add_child(_title_label)
	_offer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_offer_label)
	for _seat in SiLimits.MAX_SEATS:
		var row := HudUi.hbox(8)
		var chip := HudSeatChip.new(0, 22.0)
		var answer := HudUi.label("", &"SmallLabel")
		row.add_child(chip)
		row.add_child(answer)
		_answer_rows.append(row)
		_answer_chips.append(chip)
		_answer_labels.append(answer)
		column.add_child(row)
	var buttons := HudUi.hbox(8)
	buttons.add_child(_accept)
	buttons.add_child(_decline)
	for index in SiLimits.MAX_SEATS - 1:
		var confirm := HudUi.button("", _choose_confirm.bind(index))
		_confirms.append(confirm)
		_confirm_actions.append(null)
		buttons.add_child(confirm)
	buttons.add_child(_withdraw)
	column.add_child(buttons)
	add_child(column)
	hide()


func show_trade(state: GameState, names: SeatNames) -> void:
	if not state.view.phase is SiPhaseTradeOffered:
		hide()
		return
	var offer := (state.view.phase as SiPhaseTradeOffered).offer
	_title_label.text = _title(offer, names)
	_offer_label.text = _terms(offer, names)
	_show_answers(offer, state.view.players.size(), names)
	_show_buttons(state, names)
	show()


func _title(offer: SiTradeOffer, names: SeatNames) -> String:
	var addressed := "everyone" if offer.addressed == null else names.object(int(offer.addressed))
	if offer.offerer == names.own_seat:
		return "Your offer to %s" % addressed
	return "%s offers a trade to %s" % [names.name_of(offer.offerer), addressed]


## The terms from the own side when the own seat is part of the trade.
func _terms(offer: SiTradeOffer, names: SeatNames) -> String:
	if offer.offerer == names.own_seat:
		return "You give %s\nYou get %s" % [HudText.counts(offer.give), HudText.counts(offer.receive)]
	var addressed := offer.addressed == null or int(offer.addressed) == names.own_seat
	if addressed:
		return "You get %s\nYou give %s" % [HudText.counts(offer.give), HudText.counts(offer.receive)]
	var offerer := names.name_of(offer.offerer)
	return "%s gives %s\n%s wants %s" % [offerer, HudText.counts(offer.give), offerer, HudText.counts(offer.receive)]


func _show_answers(offer: SiTradeOffer, seat_count: int, names: SeatNames) -> void:
	var row := 0
	for seat in seat_count:
		if seat == offer.offerer or (offer.addressed != null and int(offer.addressed) != seat):
			continue
		_answer_chips[row].seat = seat
		_answer_labels[row].text = "%s: %s" % [names.subject(seat), _answer_of(offer, seat)]
		row += 1
	for index in _answer_rows.size():
		_answer_rows[index].visible = index < row


func _answer_of(offer: SiTradeOffer, seat: int) -> String:
	for answer: Array in offer.answers:
		if int(answer[0]) == seat:
			return "accepts" if bool(answer[1]) else "declines"
	return "waiting"


func _show_buttons(state: GameState, names: SeatNames) -> void:
	_actions = [_first(state, SiActionAcceptTrade), _first(state, SiActionRejectTrade), _first(state, SiActionCancelTrade)]
	_accept.visible = _actions[0] != null
	_decline.visible = _actions[1] != null
	_withdraw.visible = _actions[2] != null
	var confirms := state.legal_of(SiActionConfirmTrade)
	for index in _confirms.size():
		_confirm_actions[index] = confirms[index] if index < confirms.size() else null
		_confirms[index].visible = index < confirms.size()
		if index < confirms.size():
			_confirms[index].text = "Trade with %s" % names.name_of((confirms[index] as SiActionConfirmTrade).with)


func _first(state: GameState, script: Script) -> SiAction:
	var matching := state.legal_of(script)
	return null if matching.is_empty() else matching[0]


func _choose_pending(slot: int) -> void:
	if _actions[slot] != null:
		chosen.emit(_actions[slot])


func _choose_confirm(index: int) -> void:
	if _confirm_actions[index] != null:
		chosen.emit(_confirm_actions[index])
