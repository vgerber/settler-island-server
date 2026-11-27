class_name HudDiscardDialog
extends HudDialog
## Rolled a 7 with too many cards: pick cards one by one until the owed count, then send the legal
## `Discard` with exactly that choice.

signal chosen(action: SiAction)

var _legal: Array[SiAction] = []
var _hand: Array[int] = []
var _chosen: Array[int] = [0, 0, 0, 0, 0]
var _required := 0
var _count_labels: Array[Label] = []
var _add_buttons: Array[Button] = []
var _remove_buttons: Array[Button] = []
var _progress_label := HudUi.label("", &"MutedLabel")
var _confirm_button: Button = HudUi.button("Discard", confirm)


func _init() -> void:
	super()
	depends_on = SiActionDiscard
	body.add_child(_progress_label)
	for index in SiResource.VALUES.size():
		body.add_child(_resource_row(index))
	buttons.add_child(_confirm_button)


## Takes the current legal discards; a changed hand starts the choice over.
func offer(legal: Array[SiAction], hand: Array[int]) -> void:
	if legal.is_empty():
		hide()
		return
	if hand != _hand:
		_chosen = [0, 0, 0, 0, 0]
	_legal = legal
	_hand = hand.duplicate()
	_required = HudText.total((legal[0] as SiActionDiscard).resources)
	set_title("Discard %d of %d" % [_required, HudText.total(_hand)])
	_update()
	show()


func add(index: int) -> void:
	if _chosen[index] >= _held(index) or HudText.total(_chosen) >= _required:
		return
	_chosen[index] += 1
	_update()


func remove(index: int) -> void:
	if _chosen[index] == 0:
		return
	_chosen[index] -= 1
	_update()


## The legal discard of exactly the chosen cards, or null while the choice is incomplete.
func matching() -> SiAction:
	for action in _legal:
		if (action as SiActionDiscard).resources == _chosen:
			return action
	return null


func confirm() -> void:
	var action := matching()
	if action == null:
		return
	chosen.emit(action)


func _held(index: int) -> int:
	return _hand[index] if index < _hand.size() else 0


func _resource_row(index: int) -> HBoxContainer:
	var row := HudUi.hbox(10)
	var resource := SiResource.VALUES[index]
	row.add_child(HudResourceIcon.new(resource, 28.0))
	var name_label := HudUi.label(resource, &"CountLabel")
	name_label.custom_minimum_size = Vector2(80, 0)
	row.add_child(name_label)
	var count_label := HudUi.label("")
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(count_label)
	var remove_button := HudUi.small_button("-", remove.bind(index))
	var add_button := HudUi.small_button("+", add.bind(index))
	row.add_child(remove_button)
	row.add_child(add_button)
	_count_labels.append(count_label)
	_remove_buttons.append(remove_button)
	_add_buttons.append(add_button)
	return row


func _update() -> void:
	var picked := HudText.total(_chosen)
	_progress_label.text = "Rolled a 7: chosen %d of %d" % [picked, _required]
	for index in SiResource.VALUES.size():
		_count_labels[index].text = "%d of %d in hand" % [_chosen[index], _held(index)]
		_add_buttons[index].disabled = _chosen[index] >= _held(index) or picked >= _required
		_remove_buttons[index].disabled = _chosen[index] == 0
	_confirm_button.disabled = matching() == null
