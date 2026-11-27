class_name HudOwnSummary
extends PanelContainer
## The own seat at the left of the bottom bar: chip, name, points and the pieces still to build.

var _chip: HudSeatChip
var _name_label := HudUi.label("", &"SubheadingLabel")
var _points_label := HudUi.label("", &"HeadingLabel")
var _pieces_label := HudUi.label("", &"SmallLabel")


func _init(own_seat: int) -> void:
	theme_type_variation = &"SeatPanel"
	custom_minimum_size = Vector2(190.0, 0.0)
	_chip = HudSeatChip.new(own_seat, 26.0)
	var column := HudUi.vbox(2)
	var first := HudUi.hbox(8)
	first.add_child(_chip)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = true
	first.add_child(_name_label)
	column.add_child(first)
	column.add_child(_points_label)
	_pieces_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_pieces_label)
	add_child(column)


func set_seat(own_seat: int) -> void:
	_chip.seat = own_seat


func show_own(view: SiPlayerView, names: SeatNames) -> void:
	var player := view.players[names.own_seat]
	_name_label.text = names.name_of(names.own_seat)
	_points_label.text = "%d / %d points" % [player.points, view.points_to_win]
	_pieces_label.text = "left: %d roads, %d settlements, %d cities" % [player.roads_left, player.settlements_left, player.cities_left]
