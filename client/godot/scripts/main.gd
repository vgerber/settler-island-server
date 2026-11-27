extends Control
## Swaps the four screens on what the server says: `Welcome` leads to the lobby browser (or back
## into a running game), `LobbyState` to the lobby room, `GameStarted` to the game, `LobbyLeft` back
## to the browser. Server errors show as a toast.

const CONNECT_SCENE := preload("res://scenes/connect.tscn")
const LOBBY_BROWSER_SCENE := preload("res://scenes/lobby_browser.tscn")
const LOBBY_ROOM_SCENE := preload("res://scenes/lobby_room.tscn")
const GAME_SCENE := preload("res://scenes/game.tscn")

@onready var _screen_parent: Control = %Screen
@onready var _toast: PanelContainer = %Toast
@onready var _toast_label: Label = %ToastLabel
@onready var _toast_timer: Timer = %ToastTimer

var _screen: Node = null


func _ready() -> void:
	Net.online.connect(_on_online)
	Net.failed.connect(_on_failed)
	Net.client.lobby_state_received.connect(_on_lobby_state)
	Net.client.game_started_received.connect(_on_game_started)
	Net.client.lobby_left_received.connect(_on_lobby_left)
	Net.client.error_received.connect(_on_error)
	_toast_timer.timeout.connect(_toast.hide)
	_show(CONNECT_SCENE)


func show_toast(text: String) -> void:
	_toast_label.text = text
	_toast.show()
	_toast_timer.start()


## Replaces the current screen at once, so messages later in the same frame reach the new one.
func _show(scene: PackedScene) -> Node:
	if _screen != null:
		_screen_parent.remove_child(_screen)
		_screen.queue_free()
	_screen = scene.instantiate()
	_screen_parent.add_child(_screen)
	Atmosphere.set_mood(Atmosphere.MOOD_TABLE if scene == GAME_SCENE else Atmosphere.MOOD_MENU)
	return _screen


func _on_online(_user: SiUser, running_lobby: Variant) -> void:
	if running_lobby == null:
		_show(LOBBY_BROWSER_SCENE)
		return
	# The seat is held for us; joining brings `LobbyState` and `GameStarted`.
	Net.client.send_join_lobby(int(running_lobby))


func _on_failed(reason: String) -> void:
	if not _screen is ConnectScreen:
		_show(CONNECT_SCENE)
	show_toast(reason)


func _on_lobby_state(message: SiServerMessageLobbyState) -> void:
	# A started lobby is followed by `GameStarted`; the game screen keeps the stage until the player leaves.
	if _screen is GameScreen or message.lobby.info.started:
		return
	if not _screen is LobbyRoomScreen:
		_show(LOBBY_ROOM_SCENE)
	(_screen as LobbyRoomScreen).show_lobby(message.lobby)


func _on_game_started(message: SiServerMessageGameStarted) -> void:
	# A running game screen resynchronises itself through its `GameState`.
	if _screen is GameScreen:
		return
	(_show(GAME_SCENE) as GameScreen).begin(message)


func _on_lobby_left(_message: SiServerMessageLobbyLeft) -> void:
	_show(LOBBY_BROWSER_SCENE)


func _on_error(message: SiServerMessageError) -> void:
	# In a game, errors answering a request belong to its acts; the game screen's toasts show them.
	if _screen is GameScreen and message.request_id != null:
		return
	show_toast(message.message)
	# A rejoin can fail when the game ended meanwhile; the browser is the way on from there.
	if _screen is ConnectScreen and Net.is_online():
		_show(LOBBY_BROWSER_SCENE)
