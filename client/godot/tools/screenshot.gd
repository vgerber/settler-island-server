extends SceneTree
## Walks the main scene through its screens against a running server and saves one PNG per screen:
## connect, lobby browser, lobby room, game. Needs a window (not --headless); quits by itself.
## With a third argument "live" it then plays the human seat (first legal action, preferring progress over ending
## the turn) until the log has several lines and dice were rolled, and saves live-<width>x<height>.png.
## Usage: godot --path client/godot --position 200,200 -s tools/screenshot.gd -- http://127.0.0.1:<port> <output directory> [live]

const SETTLE_FRAMES := 20
const TIMEOUT_MILLISECONDS := 30000
const LIVE_TIMEOUT_MILLISECONDS := 120000
const LIVE_MIN_UPDATES := 25
## First match wins; ending the turn is the last resort so the game moves on.
const LIVE_PREFERENCE := ["SiActionRollDice", "SiActionPlaceSettlement", "SiActionPlaceRoad", "SiActionMoveRobber", "SiActionDiscard", "SiActionEndTurn"]

var _server_http := ""
var _output_directory := ""
var _net: Node = null
var _client: SiClient = null
var _main: Node = null
var _deadline := 0
## Frames left before the next capture, then the step that follows it.
var _wait_frames := -1
var _after_capture: Callable
var _capture_name := ""
var _exit_code := 0
var _live := false
var _live_updates := 0


func _init() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() < 2:
		push_error("usage: -s tools/screenshot.gd -- <server url> <output directory>")
		_exit_code = 1
		quit(1)
		return
	_server_http = arguments[0]
	_output_directory = arguments[1]
	_live = arguments.size() > 2 and arguments[2] == "live"
	_deadline = Time.get_ticks_msec() + (LIVE_TIMEOUT_MILLISECONDS if _live else TIMEOUT_MILLISECONDS)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > _deadline:
		push_error("screenshot: timed out waiting for %s" % _capture_name)
		_exit_code = 1
		quit(1)
		return true
	if _net == null:
		_start()
		return false
	if _wait_frames > 0:
		_wait_frames -= 1
		return false
	if _wait_frames == 0:
		_wait_frames = -1
		_save(_capture_name)
		_after_capture.call()
	return false


func _start() -> void:
	# A stored session would log in on its own and skip the connect screen.
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://session.cfg"))
	_net = root.get_node("Net")
	_client = _net.get("client") as SiClient
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_capture_after_settling("connect", _log_in)


func _capture_after_settling(capture_name: String, next_step: Callable) -> void:
	_capture_name = capture_name
	_after_capture = next_step
	_wait_frames = SETTLE_FRAMES


func _log_in() -> void:
	_net.connect("online", func(_user: SiUser, _running_lobby: Variant) -> void: _capture_after_settling("lobby_browser", _create_lobby))
	_net.call("start", _server_http, "Screenshot")


func _create_lobby() -> void:
	_client.lobby_state_received.connect(_on_lobby_state)
	_client.send_create_lobby("Screenshot table", 4, null, SiDifficulty.HEURISTIC, null, 10)


func _on_lobby_state(message: SiServerMessageLobbyState) -> void:
	var open_seats := message.lobby.seats.filter(func(seat: SiSeatOccupant) -> bool: return seat is SiSeatOccupantOpen)
	if open_seats.size() == 1 and _capture_name == "lobby_browser":
		_capture_after_settling("lobby_room", _add_last_bot)
		return
	if open_seats.size() > 1:
		_client.send_add_bot(SiDifficulty.HEURISTIC)


func _add_last_bot() -> void:
	_client.lobby_state_received.disconnect(_on_lobby_state)
	_client.lobby_state_received.connect(func(message: SiServerMessageLobbyState) -> void:
		if not message.lobby.info.started:
			_client.send_start_game()
	)
	_client.game_started_received.connect(func(_message: SiServerMessageGameStarted) -> void: _capture_after_settling("game", _play_live if _live else _quit))
	_client.send_add_bot(SiDifficulty.HEURISTIC)


func _play_live() -> void:
	_client.game_update_received.connect(func(_message: SiServerMessageGameUpdate) -> void: _live_updates += 1)
	_client.game_update_received.connect(_live_step)
	_live_step(null)


## Acts when it is the human's turn; deferred one frame so the game screen has taken the update first.
func _live_step(_message: Variant) -> void:
	await process_frame
	var screen: Node = _main.get("_screen")
	var state: GameState = screen.get("state")
	if state == null:
		return
	if _live_ready(screen):
		_live_ready_capture()
		return
	if state.legal_actions.is_empty():
		return
	for script_name in LIVE_PREFERENCE:
		for action in state.legal_actions:
			if (action.get_script() as Script).get_global_name() == script_name:
				state.act(action)
				return
	state.act(state.legal_actions[0])


func _live_ready(screen: Node) -> bool:
	var hud: Node = screen.get("_hud")
	var log_label: RichTextLabel = hud.get("_log")
	return _live_updates >= LIVE_MIN_UPDATES and log_label.get_paragraph_count() >= 6 and not (hud.get("_last_dice") as Array).is_empty()


func _live_ready_capture() -> void:
	if _capture_name.begins_with("live"):
		return
	# Under canvas_items stretching the viewport reports the design size, not the window's pixels.
	var size := DisplayServer.window_get_size()
	_open_log_if_collapsed()
	_capture_after_settling("live-%dx%d" % [size.x, size.y], _quit)


## The compact layout keeps the log behind a "Log" button; open it so the capture shows the log text.
func _open_log_if_collapsed() -> void:
	var hud: Node = _main.get("_screen").get("_hud")
	var buttons := hud.find_children("*", "Button", true, false).filter(func(node: Node) -> bool: return (node as Button).text.begins_with("Log"))
	if not buttons.is_empty() and (buttons[0] as Button).is_visible_in_tree():
		(buttons[0] as Button).pressed.emit()


func _quit() -> void:
	_net.call("stop")
	quit(_exit_code)


func _save(capture_name: String) -> void:
	var path := _output_directory.path_join("%s.png" % capture_name)
	var error := root.get_viewport().get_texture().get_image().save_png(path)
	print("saved %s (%d)" % [path, error])
	if error != OK:
		push_error("screenshot: saving %s failed (%d)" % [path, error])
		_exit_code = 1
