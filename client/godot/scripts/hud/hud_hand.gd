class_name HudHand
extends VBoxContainer
## The own hand: one card tile per resource with its count, and the development cards held.

var _tiles: HBoxContainer = HudUi.hbox(8)
var _cards_label: Label = HudUi.label("", 15, HudUi.MUTED_COLOR)


func _init() -> void:
	add_theme_constant_override("separation", 8)
	add_child(HudUi.label("Your hand", 15, HudUi.MUTED_COLOR))
	add_child(_tiles)
	_cards_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cards_label.custom_minimum_size = Vector2(360, 0)
	add_child(_cards_label)


func show_hand(own: SiOwnView) -> void:
	HudUi.clear(_tiles)
	if own == null:
		_cards_label.text = ""
		return
	for index in SiResource.VALUES.size():
		var count: int = own.hand[index] if index < own.hand.size() else 0
		_tiles.add_child(HudUi.resource_tile(SiResource.VALUES[index], count))
	_cards_label.text = "Development cards: %s" % _cards_text(own)


func _cards_text(own: SiOwnView) -> String:
	var parts: PackedStringArray = []
	for card in SiDevelopmentCard.VALUES:
		var held := own.development_cards.count(card)
		var fresh := own.new_development_cards.count(card)
		if held + fresh == 0:
			continue
		# Cards bought this turn cannot be played yet.
		var suffix := "" if fresh == 0 else " (%d new)" % fresh
		parts.append("%s x%d%s" % [HudText.card_name(card), held + fresh, suffix])
	if parts.is_empty():
		return "none"
	return ", ".join(parts)
