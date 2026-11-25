class_name HudTradePanel
extends PanelContainer
## The open player trade: what is offered to whom, the answers so far, and the legal answers of the
## own seat (accept/reject when addressed, confirm with an accepting seat or cancel when offering).

signal chosen(action: SiAction)

var _title_label: Label = HudUi.label("", 17, Color(1, 0.85, 0.4))
var _offer_label: Label = HudUi.label("", 16)
var _answers_label: Label = HudUi.label("", 15, HudUi.MUTED_COLOR)
var _buttons: HFlowContainer = HFlowContainer.new()


func _init() -> void:
	add_theme_stylebox_override("panel", HudUi.flat_style(Color(0.25, 0.2, 0.08, 0.95), 8, 10))
	var column := HudUi.vbox(6)
	_offer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_buttons.add_theme_constant_override("h_separation", 8)
	_buttons.add_theme_constant_override("v_separation", 6)
	column.add_child(_title_label)
	column.add_child(_offer_label)
	column.add_child(_answers_label)
	column.add_child(_buttons)
	add_child(column)
	hide()


func show_trade(state: GameState) -> void:
	var offer := state.view.trade
	if offer == null:
		hide()
		return
	_title_label.text = _title(offer, state.seat)
	_offer_label.text = _terms(offer, state.seat)
	_answers_label.text = _answers_text(offer, state)
	_rebuild_buttons(state)
	show()


func _title(offer: SiTradeOffer, own_seat: int) -> String:
	var addressed := "everyone" if offer.to == null else HudText.seat_object(int(offer.to), own_seat)
	if offer.seat == own_seat:
		return "Your offer to %s" % addressed
	return "%s offers a trade to %s" % [HudText.seat_name(offer.seat, own_seat), addressed]


## The terms from the own side when the own seat is part of the trade.
func _terms(offer: SiTradeOffer, own_seat: int) -> String:
	if offer.seat == own_seat:
		return "You give %s\nYou get %s" % [HudText.counts(offer.give), HudText.counts(offer.receive)]
	var addressed := offer.to == null or int(offer.to) == own_seat
	if addressed:
		return "You get %s\nYou give %s" % [HudText.counts(offer.give), HudText.counts(offer.receive)]
	var offerer := HudText.seat_name(offer.seat, own_seat)
	return "%s gives %s\n%s wants %s" % [offerer, HudText.counts(offer.give), offerer, HudText.counts(offer.receive)]


func _answers_text(offer: SiTradeOffer, state: GameState) -> String:
	var lines: PackedStringArray = []
	for seat in state.view.players.size():
		if seat == offer.seat or (offer.to != null and int(offer.to) != seat):
			continue
		lines.append("%s: %s" % [HudText.seat_name(seat, state.seat), _answer_of(offer, seat)])
	return "\n".join(lines)


func _answer_of(offer: SiTradeOffer, seat: int) -> String:
	for answer: Array in offer.answers:
		if int(answer[0]) == seat:
			return "accepts" if bool(answer[1]) else "rejects"
	return "no answer yet"


func _rebuild_buttons(state: GameState) -> void:
	HudUi.clear(_buttons)
	for action in state.legal_of(SiActionAcceptTrade):
		_buttons.add_child(HudUi.button("Accept", _choose.bind(action)))
	for action in state.legal_of(SiActionRejectTrade):
		_buttons.add_child(HudUi.button("Reject", _choose.bind(action)))
	for action in state.legal_of(SiActionConfirmTrade):
		var with := (action as SiActionConfirmTrade).with
		_buttons.add_child(HudUi.button("Trade with %s" % HudText.seat_name(with, state.seat), _choose.bind(action)))
	for action in state.legal_of(SiActionCancelTrade):
		_buttons.add_child(HudUi.button("Withdraw offer", _choose.bind(action)))


func _choose(action: SiAction) -> void:
	chosen.emit(action)
