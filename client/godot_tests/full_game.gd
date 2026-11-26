extends SceneTree
## Runs inside a copy of the game project (client/godot) with its `Net` autoload: logs in as a guest,
## opens a lobby with three bots and plays through `GameState`, always sending the first legal action.
## Midway it closes the connection and logs in again, which must hand back the running game; then it
## plays on until the game is finished.
## Usage: godot --headless --path <copy of client/godot> -s full_game.gd -- http://127.0.0.1:<port>

const TIMEOUT_MILLISECONDS := 100000
## Still in the setup round (16 placements, at most 2 points each), so bots cannot end the 3-point game before
## the reconnect lands.
const UPDATES_BEFORE_RECONNECT := 5
const USER_NAME := "Godot"

var _net: Node = null
var _client: SiClient = null
var _server_http := ""
var _deadline := 0
var _pending_request := 0
var _state: GameState = null
var _updates := 0
var _user_id := ""
var _lobby_id := -1
var _reconnected := false
var _done := false


func _init() -> void:
	_server_http = SiTestSupport.argument(0)
	if _server_http.is_empty():
		_finish(1, "FULL_GAME_FAILED missing server url")
		return
	_deadline = SiTestSupport.deadline_in(TIMEOUT_MILLISECONDS)


func _process(_delta: float) -> bool:
	if _done:
		return true
	if SiTestSupport.expired(_deadline):
		_finish(1, "FULL_GAME_FAILED timed out after %d updates" % _updates)
		return false
	# Autoloads enter the tree after `_init`, so the first frame wires them up.
	if _net == null:
		_start()
	return false


func _start() -> void:
	_net = root.get_node("Net")
	_client = _net.get("client") as SiClient
	_net.connect("online", _on_online)
	_net.connect("failed", func(reason: String) -> void: _finish(1, "FULL_GAME_FAILED %s" % reason))
	_client.lobby_state_received.connect(_on_lobby_state)
	_client.game_started_received.connect(_on_game_started)
	_client.error_received.connect(_on_error)
	_net.call("start", _server_http, USER_NAME)


func _finish(code: int, line: String) -> void:
	if _done:
		return
	_done = true
	if _state != null:
		_state.release()
		_state = null
	if _net != null:
		_net.call("stop")
	SiTestSupport.finish(self, code, line)


func _on_online(user: SiUser, running_lobby: Variant) -> void:
	print("online as %s, running lobby %s" % [user.name, running_lobby])
	if not _reconnected:
		_user_id = user.id
		_pending_request = _client.send_create_lobby("Godot full game", 4, SiDifficulty.HEURISTIC, null, 3)
		return
	if user.id != _user_id or running_lobby == null or int(running_lobby) != _lobby_id:
		_finish(1, "FULL_GAME_FAILED login after reconnect did not return the running game")
		return
	_client.send_join_lobby(_lobby_id)


func _on_lobby_state(message: SiServerMessageLobbyState) -> void:
	if message.request_id == null or message.request_id != _pending_request:
		return
	_lobby_id = message.lobby.id
	var open_seats := message.lobby.seats.filter(func(seat: SiSeatOccupant) -> bool: return seat is SiSeatOccupantOpen)
	if not open_seats.is_empty():
		_pending_request = _client.send_add_bot(SiDifficulty.HEURISTIC)
		return
	if not message.lobby.started:
		_pending_request = _client.send_start_game()


func _on_game_started(message: SiServerMessageGameStarted) -> void:
	if _state != null:
		return
	print("game started, seat %d" % message.seat)
	_state = GameState.new(_client, message)
	_state.changed.connect(_on_changed)
	_on_changed([] as Array[SiEvent])


func _on_changed(events: Array[SiEvent]) -> void:
	if not events.is_empty():
		_updates += 1
	if _state.is_finished():
		var winner := (_state.view.phase as SiPhaseFinished).winner
		var line := "FULL_GAME_OK seat %d won after %d updates" % [winner, _updates]
		_finish(0 if _reconnected else 1, line if _reconnected else "FULL_GAME_FAILED finished before the reconnect")
		return
	if _updates >= UPDATES_BEFORE_RECONNECT and not _reconnected:
		_reconnect.call_deferred()
		return
	if not _state.legal_actions.is_empty():
		_state.act(_state.legal_actions[0])


## Drops the game screen's state and the connection, then logs in again like a restarted client.
func _reconnect() -> void:
	if _reconnected or _done:
		return
	_reconnected = true
	_state.release()
	_state = null
	_net.call("stop")
	_net.call("start", _server_http, USER_NAME)


func _on_error(message: SiServerMessageError) -> void:
	_finish(1, "FULL_GAME_FAILED server error %s: %s" % [JSON.stringify(message.code.to_dict()), message.message])
