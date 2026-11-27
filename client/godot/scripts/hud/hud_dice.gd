class_name HudDice
extends HBoxContainer
## The last roll: two dice and their sum (red for a 7). Built once.

var _faces: Array[Label] = []
var _sum_label := HudUi.label("", &"HeadingLabelDark")


func _init() -> void:
	add_theme_constant_override("separation", 8)
	for _die in 2:
		var face := HudUi.panel(&"DieFace")
		face.custom_minimum_size = Vector2(56.0, 56.0)
		var number := HudUi.label("-", &"HeadingLabel")
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		face.add_child(number)
		_faces.append(number)
		add_child(face)
	_sum_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_sum_label)


func show_roll(dice: Array[int]) -> void:
	if dice.size() != 2:
		return
	for index in 2:
		_faces[index].text = str(dice[index])
	var sum := dice[0] + dice[1]
	_sum_label.text = "= %d" % sum
	_sum_label.theme_type_variation = &"DangerLabelDark" if sum == 7 else &"HeadingLabelDark"
