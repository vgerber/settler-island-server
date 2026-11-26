extends SceneTree
## Runs inside a copy of the game project with its `Net` autoload: a session file holding a token the server
## refuses is replaced by a fresh guest session, `online` fires and the file keeps the new token.
## Usage: godot --headless --path <project> -s net_stale_token.gd -- <http://host:port>

# The "guest." prefix makes the server check the signature (and refuse it) instead of treating it as an account token.
const BOGUS_TOKEN := "guest.bogus.signature"
const USER_NAME := "stale-token-test"
const TIMEOUT_SECONDS := 15.0

var _net: Node
var _elapsed := 0.0
var _done := false


func _initialize() -> void:
	var server_http := SiTestSupport.argument(0)
	if server_http.is_empty():
		_finish(1, "NET_STALE_TOKEN_FAILED missing server address")
		return
	_net = root.get_node("Net")
	_write_session(server_http)
	_net.failed.connect(_on_failed)
	_net.online.connect(_on_online)
	# The autoload connects its session signals in `_ready`, which runs after `_initialize`.
	_net.start.call_deferred(server_http, USER_NAME)


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > TIMEOUT_SECONDS:
		_finish(1, "NET_STALE_TOKEN_FAILED timeout")
	return _done


func _write_session(server_http: String) -> void:
	var config := ConfigFile.new()
	config.set_value(_net.SESSION_SECTION, "server", server_http)
	config.set_value(_net.SESSION_SECTION, "name", USER_NAME)
	config.set_value(_net.SESSION_SECTION, "token", BOGUS_TOKEN)
	if config.save(_net.SESSION_PATH) != OK:
		_finish(1, "NET_STALE_TOKEN_FAILED cannot write the session file")


func _on_failed(reason: String) -> void:
	_finish(1, "NET_STALE_TOKEN_FAILED %s" % reason)


func _on_online(user: SiUser, _running_lobby: Variant) -> void:
	var token: String = _net.stored_token(_net.server_http, USER_NAME)
	if token.is_empty() or token == BOGUS_TOKEN:
		_finish(1, "NET_STALE_TOKEN_FAILED the bogus token is still stored")
		return
	if user.name != USER_NAME:
		_finish(1, "NET_STALE_TOKEN_FAILED welcomed as %s" % user.name)
		return
	_finish(0, "NET_STALE_TOKEN_OK")


func _finish(code: int, line: String) -> void:
	if _done:
		return
	_done = true
	SiTestSupport.finish(self, code, line)
