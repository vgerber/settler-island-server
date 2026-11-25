class_name HudGameOver
extends ColorRect
## Dims the screen at the end of the game: the winner, the final standings and the way back to the
## lobbies. "Show board" closes it so the final board stays visible.

signal leave_requested

var _title_label: Label = HudUi.label("", 34)
var _standings: VBoxContainer = HudUi.vbox(6)


func _init() -> void:
	color = Color(0, 0, 0, 0.6)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var card := HudUi.panel(HudUi.DIALOG_COLOR, 12, 28)
	card.custom_minimum_size = Vector2(460, 0)
	var column := HudUi.vbox(16)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title_label)
	column.add_child(_standings)
	var buttons := HudUi.hbox(12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_child(HudUi.button("Show board", hide))
	buttons.add_child(HudUi.button("Back to lobbies", leave_requested.emit))
	column.add_child(buttons)
	card.add_child(column)
	center.add_child(card)
	add_child(center)
	hide()


func show_result(view: SiPlayerView, own_seat: int) -> void:
	var winner := (view.phase as SiPhaseFinished).winner
	_title_label.text = "You won!" if winner == own_seat else "%s won" % HudText.seat_name(winner, own_seat)
	_title_label.add_theme_color_override("font_color", HudText.seat_color(winner))
	HudUi.clear(_standings)
	var ranked := view.players.duplicate()
	ranked.sort_custom(func(first: SiPublicPlayerView, second: SiPublicPlayerView) -> bool: return first.points > second.points)
	for player: SiPublicPlayerView in ranked:
		var row := HudUi.hbox(12)
		var name_label := HudUi.label(HudText.seat_name(player.seat, own_seat), 20, HudText.seat_color(player.seat))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(HudUi.label("%d points" % player.points, 20))
		_standings.add_child(row)
	show()
