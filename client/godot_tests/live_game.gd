extends SceneTree
## Plays against a real server through `SiClient`: gets a guest token over HTTP, authenticates, opens a lobby with three bots, starts
## the game and always picks the first legal action until enough game updates arrived.
## Usage: godot --headless --path <project> -s live_game.gd -- http://127.0.0.1:<port>

const TIMEOUT_MILLISECONDS := 30000
const UPDATES_WANTED := 5

var _client := SiClient.new()
var _session := SiGuestSession.new()
var _base_url := ""
var _token := ""
var _deadline := 0
var _pending_request := 0
var _updates := 0
## The Act request whose reply is outstanding; acting again before it lands would use stale legal actions.
var _awaiting_act := 0
var _done := false


func _init() -> void:
	_base_url = SiTestSupport.argument(0)
	if _base_url.is_empty():
		_finish(1, "LIVE_FAILED missing server url")
		return
	_deadline = SiTestSupport.deadline_in(TIMEOUT_MILLISECONDS)
	# In the tree the client polls itself in `_process` and is freed when the tree quits.
	root.add_child.call_deferred(_client)
	_client.connected.connect(_on_connected)
	_client.disconnected.connect(_on_disconnected)
	_client.welcome_received.connect(_on_welcome)
	_client.lobby_state_received.connect(_on_lobby_state)
	_client.game_started_received.connect(_on_game_started)
	_client.game_update_received.connect(_on_game_update)
	_client.error_received.connect(_on_error)
	root.add_child.call_deferred(_session)
	_session.succeeded.connect(_on_session)
	_session.failed.connect(func(reason: String): _finish(1, "LIVE_FAILED %s" % reason))
	# The session node enters the tree deferred, so start the request after that.
	_session.request.call_deferred(_base_url, "Godot")


func _on_session(token: String, user: SiUser) -> void:
	print("guest session for %s (%s)" % [user.name, user.kind])
	_token = token
	var error := _client.connect_to_url(_base_url.replace("http://", "ws://") + "/api/v1/ws")
	if error != OK:
		_finish(1, "LIVE_FAILED connect_to_url returned %d" % error)


func _process(_delta: float) -> bool:
	if _done:
		return true
	if SiTestSupport.expired(_deadline):
		_finish(1, "LIVE_FAILED timed out after %d updates" % _updates)
	return false


func _finish(code: int, line: String) -> void:
	if _done:
		return
	_done = true
	_client.close()
	SiTestSupport.finish(self, code, line)


func _on_connected() -> void:
	_pending_request = _client.send_authenticate(_token)


func _on_disconnected(code: int, reason: String) -> void:
	_finish(1, "LIVE_FAILED disconnected %d %s" % [code, reason])


func _on_welcome(message: SiServerMessageWelcome) -> void:
	print("welcomed as %s" % message.user.name)
	_pending_request = _client.send_create_lobby("Godot table", 4, SiDifficulty.RANDOM, null, 3)


func _on_lobby_state(message: SiServerMessageLobbyState) -> void:
	if message.request_id == null or message.request_id != _pending_request:
		return
	var open_seats := message.lobby.seats.filter(func(seat): return seat is SiSeatOccupantOpen)
	if not open_seats.is_empty():
		_pending_request = _client.send_add_bot(SiDifficulty.RANDOM)
		return
	if not message.lobby.started:
		_pending_request = _client.send_start_game()


func _on_game_started(message: SiServerMessageGameStarted) -> void:
	print("game started, seat %d, phase %s" % [message.seat, message.view.phase.to_dict()["type"]])
	_act(message.legal_actions)


func _on_game_update(message: SiServerMessageGameUpdate) -> void:
	_updates += 1
	if message.request_id != null and message.request_id == _awaiting_act:
		_awaiting_act = 0
	if _updates >= UPDATES_WANTED:
		_finish(0, "LIVE_OK %d updates" % _updates)
		return
	_act(message.legal_actions)


func _on_error(message: SiServerMessageError) -> void:
	_finish(1, "LIVE_FAILED server error %s: %s" % [JSON.stringify(message.code.to_dict()), message.message])


func _act(legal_actions: Array[SiAction]) -> void:
	if legal_actions.is_empty() or _awaiting_act != 0:
		return
	_awaiting_act = _client.send_act(legal_actions[0])
