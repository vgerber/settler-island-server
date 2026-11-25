class_name HudPlayers
extends VBoxContainer
## One row per seat: colour, name, points, cards in hand, development cards, knights and the
## longest road / largest army titles; the seat to play is marked.


func _init() -> void:
	add_theme_constant_override("separation", 4)


func show_players(view: SiPlayerView, own_seat: int) -> void:
	HudUi.clear(self)
	for player in view.players:
		add_child(_row(player, view, own_seat))


func _row(player: SiPublicPlayerView, view: SiPlayerView, own_seat: int) -> PanelContainer:
	var is_current := player.seat == view.current and not view.phase is SiPhaseFinished
	var background := Color(0.2, 0.25, 0.32, 0.9) if is_current else Color(0.14, 0.17, 0.22, 0.9)
	var row_panel := HudUi.panel(background, 6, 6)
	var row := HudUi.hbox(8)
	var swatch := ColorRect.new()
	swatch.color = HudText.seat_color(player.seat)
	swatch.custom_minimum_size = Vector2(8, 0)
	row.add_child(swatch)
	var column := HudUi.vbox(0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var marker := "> " if is_current else ""
	column.add_child(HudUi.label(marker + HudText.seat_name(player.seat, own_seat), 17, HudText.seat_color(player.seat)))
	column.add_child(HudUi.label(_details(player, view), 14, HudUi.MUTED_COLOR))
	row.add_child(column)
	var points := HudUi.label("%d" % player.points, 26)
	points.tooltip_text = "Victory points"
	points.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(points)
	row_panel.add_child(row)
	return row_panel


func _details(player: SiPublicPlayerView, view: SiPlayerView) -> String:
	var parts: PackedStringArray = [
		"%d card%s" % [player.resource_count, "" if player.resource_count == 1 else "s"],
		"%d dev" % player.development_card_count,
		"%d knights" % player.knights_played,
	]
	if view.longest_road != null and int(view.longest_road) == player.seat:
		parts.append("Longest road")
	if view.largest_army != null and int(view.largest_army) == player.seat:
		parts.append("Largest army")
	return "  ".join(parts)
