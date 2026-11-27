class_name HudTradeBuilder
extends VBoxContainer
## The Players tab of the trade dialog: builds a player trade offer. Offers are not among the legal actions (their choices are open), so
## the pane keeps to what the server accepts: something given from the own hand, something asked
## for, no resource on both sides, addressed to everyone or one other seat.

signal offered(action: SiActionOfferTrade)

## Asking for more than this of one resource cannot be met by any hand in practice.
const MAX_ASKED := 9

var _hand: Array[int] = []
var _give: Array[int] = [0, 0, 0, 0, 0]
var _receive: Array[int] = [0, 0, 0, 0, 0]
## Option index 0 is everyone, then one entry per other seat in `_recipients`.
var _recipients: Array[int] = []
var _recipient_option := OptionButton.new()
var _give_labels: Array[Label] = []
var _receive_labels: Array[Label] = []
var _buttons_by_side: Dictionary[String, Array] = {"give": [], "receive": []}
var _send_button: Button = null


func _init() -> void:
	add_theme_constant_override("separation", 10)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 8)
	for heading in ["", "You give", "", "", "You get", "", ""]:
		grid.add_child(HudUi.label(heading, &"SmallLabel"))
	for index in SiResource.VALUES.size():
		_add_row(grid, index)
	add_child(grid)
	var recipient_row := HudUi.hbox(10)
	recipient_row.add_child(HudUi.label("To", &"SmallLabel"))
	_recipient_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipient_row.add_child(_recipient_option)
	add_child(recipient_row)
	_send_button = HudUi.button("Offer", _send)
	_send_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	add_child(_send_button)


func open(hand: Array[int], seats: int, names: SeatNames) -> void:
	_hand = hand.duplicate()
	_give = [0, 0, 0, 0, 0]
	_receive = [0, 0, 0, 0, 0]
	_recipients = []
	_recipient_option.clear()
	_recipient_option.add_item("Everyone")
	for seat in seats:
		if seat != names.own_seat:
			_recipients.append(seat)
			_recipient_option.add_item(names.name_of(seat))
	_update()


func change(side: String, index: int, delta: int) -> void:
	var counts: Array[int] = _give if side == "give" else _receive
	counts[index] = clampi(counts[index] + delta, 0, _limit(side, index))
	_update()


func _limit(side: String, index: int) -> int:
	if side == "give":
		return _hand[index] if _receive[index] == 0 else 0
	return MAX_ASKED if _give[index] == 0 else 0


func _add_row(grid: GridContainer, index: int) -> void:
	var resource := SiResource.VALUES[index]
	var name_row := HudUi.hbox(6)
	name_row.add_child(HudResourceIcon.new(resource, 24.0))
	name_row.add_child(HudUi.label(resource, &"SmallLabel"))
	name_row.custom_minimum_size = Vector2(100, 0)
	grid.add_child(name_row)
	for side in ["give", "receive"]:
		var count_label := HudUi.label("0", &"CountLabel")
		count_label.custom_minimum_size = Vector2(36, 0)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var less := HudUi.small_button("-", change.bind(side, index, -1))
		var more := HudUi.small_button("+", change.bind(side, index, 1))
		grid.add_child(less)
		grid.add_child(count_label)
		grid.add_child(more)
		(_give_labels if side == "give" else _receive_labels).append(count_label)
		(_buttons_by_side[side] as Array).append([less, more])


func _update() -> void:
	for index in SiResource.VALUES.size():
		_give_labels[index].text = str(_give[index])
		_receive_labels[index].text = str(_receive[index])
		for side: String in ["give", "receive"]:
			var pair: Array = (_buttons_by_side[side] as Array)[index]
			var count: int = (_give if side == "give" else _receive)[index]
			(pair[0] as Button).disabled = count == 0
			(pair[1] as Button).disabled = count >= _limit(side, index)
	_send_button.disabled = HudText.total(_give) == 0 or HudText.total(_receive) == 0


func _send() -> void:
	if HudText.total(_give) == 0 or HudText.total(_receive) == 0:
		return
	var action := SiActionOfferTrade.new()
	action.give = _give.duplicate()
	action.receive = _receive.duplicate()
	var selected := _recipient_option.selected
	action.to = null if selected <= 0 else _recipients[selected - 1]
	offered.emit(action)
