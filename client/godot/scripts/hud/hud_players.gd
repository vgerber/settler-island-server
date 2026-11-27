class_name HudPlayers
extends VBoxContainer
## The opponents' panels, in turn order starting after the own seat. Created on the first view, then only updated.

var _panels: Array[HudPlayerPanel] = []
var _compact := false


func _init(compact: bool = false) -> void:
	_compact = compact
	add_theme_constant_override("separation", 6)


func show_players(view: SiPlayerView, names: SeatNames) -> void:
	if _panels.is_empty():
		_create_panels(view.players.size(), names.own_seat)
	for panel in _panels:
		var status := HudText.status_text(view, panel.seat, names)
		panel.show_player(view.players[panel.seat], view, names, status)


func set_compact(compact: bool) -> void:
	_compact = compact
	for panel in _panels:
		panel.set_compact(compact)


func _create_panels(seat_count: int, own_seat: int) -> void:
	for offset in range(1, seat_count):
		var panel := HudPlayerPanel.new((own_seat + offset) % seat_count, _compact)
		_panels.append(panel)
		add_child(panel)
