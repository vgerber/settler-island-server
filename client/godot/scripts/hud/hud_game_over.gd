class_name HudGameOver
extends ColorRect
## Dims the board at the end of the game: the winner, the ranking and the way back to the lobbies. "Show board"
## closes it so the final board stays visible; the top bar then offers "Results" again.

signal leave_requested

var _winner_chip := HudSeatChip.new(0, 36.0)
var _title_label := HudUi.label("", &"TitleLabel")
var _subtitle_label := HudUi.label("", &"MutedLabel")
var _ranking: VBoxContainer = HudUi.vbox(6)


func _init() -> void:
	color = Color(0, 0, 0, 0.6)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var card := HudUi.panel(&"DialogPanel")
	card.custom_minimum_size = Vector2(520.0, 420.0)
	var column := HudUi.vbox(14)
	var headline := HudUi.hbox(12)
	headline.alignment = BoxContainer.ALIGNMENT_CENTER
	headline.add_child(_winner_chip)
	headline.add_child(_title_label)
	column.add_child(headline)
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_subtitle_label)
	column.add_child(HSeparator.new())
	_ranking.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_ranking)
	var buttons := HudUi.hbox(12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_child(HudUi.button("Show board", hide))
	buttons.add_child(HudUi.button("Back to lobbies", leave_requested.emit, &"AccentButton"))
	column.add_child(buttons)
	card.add_child(column)
	center.add_child(card)
	add_child(center)
	hide()


func show_result(view: SiPlayerView, names: SeatNames) -> void:
	var winner := (view.phase as SiPhaseFinished).winner
	_winner_chip.seat = winner
	_title_label.text = "You win!" if winner == names.own_seat else "%s wins" % names.name_of(winner)
	_subtitle_label.text = "with %d points" % view.players[winner].points
	HudUi.clear(_ranking)
	var ranked := view.players.duplicate()
	ranked.sort_custom(func(first: SiPublicPlayerView, second: SiPublicPlayerView) -> bool: return first.points > second.points)
	for player: SiPublicPlayerView in ranked:
		_ranking.add_child(_row(player, view, names))
	show()


func _row(player: SiPublicPlayerView, view: SiPlayerView, names: SeatNames) -> PanelContainer:
	var row_panel := HudUi.panel(&"SeatPanelCurrent" if player.seat == names.own_seat else &"SeatPanel")
	var row := HudUi.hbox(10)
	row.add_child(HudSeatChip.new(player.seat, 26.0))
	var name_label := HudUi.label(names.name_of(player.seat), &"CountLabel")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(HudUi.label("%d points" % player.points, &"CountLabel"))
	row.add_child(HudUi.label("knights %d" % player.knights_played, &"SmallLabel"))
	var badges: PackedStringArray = []
	if view.longest_road != null and int(view.longest_road) == player.seat:
		badges.append("road")
	if view.largest_army != null and int(view.largest_army) == player.seat:
		badges.append("army")
	row.add_child(HudUi.label(" ".join(badges), &"SmallLabel"))
	row_panel.add_child(row)
	return row_panel
