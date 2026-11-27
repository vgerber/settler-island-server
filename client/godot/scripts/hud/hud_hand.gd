class_name HudHand
extends HBoxContainer
## The own resource cards. Built once; `show_hand` sets the counts.

var _cards: Array[HudResourceCard] = []
var _total_label := HudUi.label("", &"CreamMutedLabel")


func _init() -> void:
	add_theme_constant_override("separation", 8)
	for resource in SiResource.VALUES:
		var card := HudResourceCard.new(resource)
		_cards.append(card)
		add_child(card)
	_total_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_total_label)


func show_hand(own: SiOwnView) -> void:
	var total := 0
	for index in _cards.size():
		var count := 0 if own == null or index >= own.hand.size() else own.hand[index]
		_cards[index].set_count(count)
		total += count
	_total_label.text = "= %d" % total


## Sets the card sizes of the full (72x100) or compact (58x80 real pixels at 0.8) layout.
func set_compact(compact: bool) -> void:
	for card in _cards:
		card.custom_minimum_size = Vector2(72.0, 92.0 if compact else 100.0)
