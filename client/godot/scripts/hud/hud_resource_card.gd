class_name HudResourceCard
extends PanelContainer
## One resource of the own hand as a card: icon, name and count. Built once, `set_count` updates it.

## Cards on dark terrain read better with cream text.
const LIGHT_TEXT := [SiResource.WOOD]

var resource := ""
var _count_label: Label


func _init(card_resource: String, card_size: Vector2 = Vector2(72.0, 100.0)) -> void:
	resource = card_resource
	theme_type_variation = &"ResourceCard" + card_resource
	custom_minimum_size = card_size
	var light := LIGHT_TEXT.has(card_resource)
	var column := HudUi.vbox(0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon := HudResourceIcon.new(card_resource, 32.0)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(icon)
	var name_label := HudUi.label(card_resource, &"CardLabelLight" if light else &"CardLabel")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)
	_count_label = HudUi.label("0", &"CardCountLight" if light else &"CardCount")
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_count_label)
	add_child(column)
	set_count(0)


func set_count(count: int) -> void:
	_count_label.text = str(count)
	modulate = Color.WHITE if count > 0 else Color(1, 1, 1, 0.45)
