class_name LobbyBrowserScreen
extends Control
## Lists open lobbies (refreshed every few seconds, the server does not push the list), joins one or
## creates a new one. The server's `LobbyState` reply moves on to the lobby room.


@onready var _user_label: Label = %UserLabel
@onready var _lobby_list: ItemList = %LobbyList
@onready var _refresh_button: Button = %RefreshButton
@onready var _join_password_edit: LineEdit = %JoinPasswordEdit
@onready var _join_button: Button = %JoinButton
@onready var _lobby_name_edit: LineEdit = %LobbyNameEdit
@onready var _seats_option: OptionButton = %SeatsOption
@onready var _points_spin: SpinBox = %PointsSpin
@onready var _difficulty_option: OptionButton = %DifficultyOption
@onready var _create_password_edit: LineEdit = %CreatePasswordEdit
@onready var _create_button: Button = %CreateButton
@onready var _refresh_timer: Timer = %RefreshTimer

var _lobbies: Array[SiLobbySummary] = []
## Largest first, so the default choice is a full table.
var _seat_choices: Array[int] = []


func _ready() -> void:
	_lobby_name_edit.max_length = SiLimits.MAX_LOBBY_NAME_CHARS
	_points_spin.min_value = SiLimits.MIN_POINTS_TO_WIN
	_points_spin.max_value = SiLimits.MAX_POINTS_TO_WIN
	_points_spin.value = SiLimits.DEFAULT_POINTS_TO_WIN
	for seats in range(SiLimits.MAX_SEATS, SiLimits.MIN_SEATS - 1, -1):
		_seat_choices.append(seats)
		_seats_option.add_item("%d players" % seats)
	for difficulty in SiDifficulty.VALUES:
		_difficulty_option.add_item(difficulty)
	_difficulty_option.select(SiDifficulty.VALUES.find(SiLimits.DEFAULT_BOT_DIFFICULTY))
	if Net.user != null:
		_user_label.text = "Playing as %s" % Net.user.name
		_lobby_name_edit.text = "%s's table" % Net.user.name
	_refresh_button.pressed.connect(_refresh)
	_refresh_timer.timeout.connect(_refresh)
	_lobby_list.item_selected.connect(func(_index: int) -> void: _update_join_button())
	_lobby_list.item_activated.connect(func(_index: int) -> void: _on_join())
	_join_button.pressed.connect(_on_join)
	_create_button.pressed.connect(_on_create)
	Net.client.lobbies_received.connect(_on_lobbies)
	_refresh()


func _refresh() -> void:
	Net.client.send_list_lobbies(0, SiLimits.MAX_LOBBIES_PER_PAGE)


func _on_lobbies(message: SiServerMessageLobbies) -> void:
	var selected_id := _selected_lobby_id()
	_lobbies = message.lobbies
	_lobby_list.clear()
	for lobby in _lobbies:
		var index := _lobby_list.add_item(_describe(lobby))
		if lobby.info.id == selected_id:
			_lobby_list.select(index)
	_update_join_button()


func _describe(lobby: SiLobbySummary) -> String:
	var info := lobby.info
	var state := "running" if info.started else "%d of %d seats open" % [lobby.open_seats, lobby.seats]
	var lock := "  [password]" if info.has_password else ""
	return "%s  -  %s  -  %s  -  %d points, %s bots%s" % [
		info.name, info.owner.name, state, info.points_to_win, info.bot_difficulty, lock,
	]


func _selected_lobby_id() -> int:
	var selected := _lobby_list.get_selected_items()
	if selected.is_empty() or selected[0] >= _lobbies.size():
		return -1
	return _lobbies[selected[0]].info.id


func _update_join_button() -> void:
	_join_button.disabled = _selected_lobby_id() < 0


func _on_join() -> void:
	var lobby_id := _selected_lobby_id()
	if lobby_id < 0:
		return
	var password := _join_password_edit.text
	Net.client.send_join_lobby(lobby_id, null if password.is_empty() else password)


func _on_create() -> void:
	var password := _create_password_edit.text
	Net.client.send_create_lobby(
		_lobby_name_edit.text.strip_edges(),
		_seat_choices[_seats_option.selected],
		SiDifficulty.VALUES[_difficulty_option.selected],
		null if password.is_empty() else password,
		int(_points_spin.value),
	)
