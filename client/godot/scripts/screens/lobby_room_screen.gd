class_name LobbyRoomScreen
extends Control
## One lobby before its game: the seats, and for the owner bot seats and the start button. `main.gd`
## passes every `LobbyState` to `show_lobby`.

@onready var _title_label: Label = %TitleLabel
@onready var _info_label: Label = %InfoLabel
@onready var _seat_rows: VBoxContainer = %SeatRows
@onready var _bot_difficulty_option: OptionButton = %BotDifficultyOption
@onready var _add_bot_button: Button = %AddBotButton
@onready var _leave_button: Button = %LeaveButton
@onready var _start_button: Button = %StartButton


func _ready() -> void:
	for difficulty in SiDifficulty.VALUES:
		_bot_difficulty_option.add_item(difficulty)
	_add_bot_button.pressed.connect(_on_add_bot)
	_leave_button.pressed.connect(func() -> void: Net.client.send_leave_lobby())
	_start_button.pressed.connect(func() -> void: Net.client.send_start_game())


func show_lobby(lobby: SiLobbyDetails) -> void:
	var is_owner := Net.user != null and lobby.owner.id == Net.user.id
	var open_seats := lobby.seats.filter(func(occupant: SiSeatOccupant) -> bool: return occupant is SiSeatOccupantOpen)
	_title_label.text = lobby.name
	_info_label.text = "%d points to win%s" % [lobby.points_to_win, "  -  password protected" if lobby.has_password else ""]
	if _seat_rows.get_child_count() == 0:
		_bot_difficulty_option.select(SiDifficulty.VALUES.find(lobby.bot_difficulty))
	for row in _seat_rows.get_children():
		_seat_rows.remove_child(row)
		row.queue_free()
	for seat in lobby.seats.size():
		_seat_rows.add_child(_seat_row(seat, lobby.seats[seat], lobby, is_owner))
	_add_bot_button.disabled = not is_owner or open_seats.is_empty()
	_bot_difficulty_option.disabled = not is_owner
	_start_button.disabled = not is_owner or not open_seats.is_empty()
	_start_button.text = "Start game" if is_owner else "Waiting for %s to start" % lobby.owner.name


func _seat_row(seat: int, occupant: SiSeatOccupant, lobby: SiLobbyDetails, is_owner: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = "Seat %d:  %s" % [seat + 1, _describe(occupant, lobby)]
	row.add_child(label)
	if is_owner and occupant is SiSeatOccupantBot:
		var remove_button := Button.new()
		remove_button.text = "Remove bot"
		remove_button.theme_type_variation = &"DangerButton"
		remove_button.pressed.connect(func() -> void: Net.client.send_remove_bot(seat))
		row.add_child(remove_button)
	return row


func _describe(occupant: SiSeatOccupant, lobby: SiLobbyDetails) -> String:
	if occupant is SiSeatOccupantHuman:
		var user := (occupant as SiSeatOccupantHuman).user
		var marks := ""
		if user.id == lobby.owner.id:
			marks += "  (owner)"
		if Net.user != null and user.id == Net.user.id:
			marks += "  (you)"
		return user.name + marks
	if occupant is SiSeatOccupantBot:
		return "Bot (%s)" % (occupant as SiSeatOccupantBot).difficulty
	return "open"


func _on_add_bot() -> void:
	Net.client.send_add_bot(SiDifficulty.VALUES[_bot_difficulty_option.selected])
