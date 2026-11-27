class_name HudPlayerPanel
extends PanelContainer
## One opponent: seat chip and name, points, card counts, badges and what the seat is doing now.
## Built once per seat; `show_player` only sets texts and the panel variation.

const HAND_WARNING := 7

var seat := 0
var _compact := false
var _chip: HudSeatChip
var _name_label := HudUi.label("", &"SubheadingLabel")
var _points_label := HudUi.label("0", &"HeadingLabel")
var _cards_label := HudUi.label("", &"CountLabel")
var _dev_label := HudUi.label("", &"SmallLabel")
var _status_label := HudUi.label("", &"MutedLabel")
var _knights_label := HudUi.label("", &"SmallLabel")
var _army_label := HudUi.label("Army", &"CountLabel")
var _road_label := HudUi.label("Road", &"CountLabel")
var _hourglass := HudHourglass.new()
var _army_badge := HudUi.label("A", &"CountLabel")
var _road_badge := HudUi.label("R", &"CountLabel")
var _pieces_label := HudUi.label("", &"SmallLabel")
## Row 3 of the full panel; in compact mode its content moves into the one-letter badges of row 2.
var _detail_row := HudUi.hbox(10)


func _init(panel_seat: int, compact: bool) -> void:
	seat = panel_seat
	_chip = HudSeatChip.new(seat, 26.0)
	var column := HudUi.vbox(2)
	column.add_child(_first_row())
	column.add_child(_second_row())
	_detail_row.add_child(_knights_label)
	_detail_row.add_child(_army_label)
	_detail_row.add_child(_road_label)
	_detail_row.add_child(_pieces_label)
	column.add_child(_detail_row)
	add_child(column)
	_status_label.clip_text = true
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.theme_type_variation = &"SmallLabel"
	_points_label.tooltip_text = "Victory points"
	_pieces_label.tooltip_text = "Pieces left: roads / settlements / cities"
	_dev_label.tooltip_text = "Development cards"
	_cards_label.tooltip_text = "Resource cards in hand"
	mouse_filter = Control.MOUSE_FILTER_PASS
	# Labels only show their tooltip when they take mouse events.
	for tipped: Label in [_dev_label, _cards_label, _pieces_label, _points_label]:
		tipped.mouse_filter = Control.MOUSE_FILTER_PASS
	set_compact(compact)


func set_compact(compact: bool) -> void:
	_compact = compact
	custom_minimum_size = Vector2(340.0, 72.0 if compact else 96.0)
	_detail_row.visible = not compact


func show_player(player: SiPublicPlayerView, view: SiPlayerView, names: SeatNames, status: String) -> void:
	var pending := not status.is_empty()
	theme_type_variation = _variation(pending)
	var bot := " (bot)" if names.is_bot(seat) else ""
	_name_label.text = names.name_of(seat) + bot
	_points_label.text = str(player.points)
	_cards_label.text = "%d cards" % player.resource_count
	_cards_label.theme_type_variation = &"DangerLabel" if player.resource_count > HAND_WARNING else &"CountLabel"
	_dev_label.text = "dev %d" % player.development_card_count
	_status_label.text = status
	var army := view.largest_army != null and int(view.largest_army) == seat
	var road := view.longest_road != null and int(view.longest_road) == seat
	_army_label.visible = army
	_road_label.visible = road
	_army_badge.visible = army and _compact
	_road_badge.visible = road and _compact
	_knights_label.text = "knights %d" % player.knights_played
	_pieces_label.text = "pieces %d/%d/%d" % [player.roads_left, player.settlements_left, player.cities_left]


## The active-seat glow and the hourglass of a seat the game waits for.
func mark(active: bool, waiting: bool, bot: bool, breathing: bool) -> void:
	_hourglass.visible = waiting
	HudGlow.apply(self, seat, active, bot, breathing)


func _variation(pending: bool) -> StringName:
	if _compact:
		return &"PlayerPanelCompactCurrent" if pending else &"PlayerPanelCompact"
	return &"SeatPanelCurrent" if pending else &"SeatPanel"


func _first_row() -> HBoxContainer:
	var row := HudUi.hbox(8)
	row.add_child(_chip)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = true
	row.add_child(_name_label)
	row.add_child(_points_label)
	return row


func _second_row() -> HBoxContainer:
	var row := HudUi.hbox(8)
	row.add_child(_cards_label)
	row.add_child(_dev_label)
	row.add_child(_status_label)
	row.add_child(_hourglass)
	row.add_child(_army_badge)
	row.add_child(_road_badge)
	return row
