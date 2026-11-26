extends Node
## Autoload `Net`: owns the one `SiClient` and the guest session. `start` gets (or reuses) a guest
## token, opens the WebSocket and authenticates; `online` follows the server's `Welcome`.

signal online(user: SiUser, running_lobby: Variant)
signal failed(reason: String)

const SESSION_PATH := "user://session.cfg"
const SESSION_SECTION := "session"
const WEBSOCKET_PATH := "/api/v1/ws"

var client: SiClient = SiClient.new()
var user: SiUser = null
var server_http: String = ""
var user_name: String = ""

var _session: SiGuestSession = SiGuestSession.new()
var _token: String = ""
## True while the token came from the session file; the server may have forgotten it since.
var _token_is_stored: bool = false
## True while a fresh token replaces a refused stored one on the still open socket.
var _reauthenticating: bool = false
var _authenticate_request: int = 0
## True from opening our socket until it closes or `stop`; a close outside that window belongs to a
## socket we gave up on and is not a failure.
var _socket_opened: bool = false


func _ready() -> void:
	add_child(client)
	add_child(_session)
	_session.succeeded.connect(_on_session_succeeded)
	_session.failed.connect(_fail)
	client.connected.connect(_on_connected)
	client.disconnected.connect(_on_disconnected)
	client.welcome_received.connect(_on_welcome)
	client.error_received.connect(_on_error)


## Connects as the guest `name`, reusing the stored token when it was issued by this server for this name.
func start(new_server_http: String, new_user_name: String) -> void:
	server_http = new_server_http.strip_edges().trim_suffix("/")
	user_name = new_user_name.strip_edges()
	_reset_connection()
	_token = stored_token(server_http, user_name)
	_token_is_stored = not _token.is_empty()
	if _token_is_stored:
		_open_socket()
		return
	_session.request(server_http, user_name)


func stop() -> void:
	_reset_connection()


func is_online() -> bool:
	return user != null


## The last server and name used, for prefilling the connect screen.
func last_login() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(SESSION_PATH) != OK:
		return {}
	return {
		"server": str(config.get_value(SESSION_SECTION, "server", "")),
		"name": str(config.get_value(SESSION_SECTION, "name", "")),
	}


func stored_token(for_server: String, for_name: String) -> String:
	var config := ConfigFile.new()
	if config.load(SESSION_PATH) != OK:
		return ""
	var same_login: bool = config.get_value(SESSION_SECTION, "server", "") == for_server \
		and config.get_value(SESSION_SECTION, "name", "") == for_name
	if not same_login:
		return ""
	return str(config.get_value(SESSION_SECTION, "token", ""))


func _store_token() -> void:
	var config := ConfigFile.new()
	config.set_value(SESSION_SECTION, "server", server_http)
	config.set_value(SESSION_SECTION, "name", user_name)
	config.set_value(SESSION_SECTION, "token", _token)
	var error := config.save(SESSION_PATH)
	if error != OK:
		push_warning("Net: could not save the session (%d)" % error)


func _on_session_succeeded(token: String, _guest: SiUser) -> void:
	_token = token
	_token_is_stored = false
	_store_token()
	if _reauthenticating:
		_reauthenticating = false
		_authenticate_request = client.send_authenticate(_token)
		return
	_open_socket()


func _open_socket() -> void:
	_socket_opened = true
	var url := server_http.replace("https://", "wss://").replace("http://", "ws://") + WEBSOCKET_PATH
	var error := client.connect_to_url(url)
	if error != OK:
		_fail("cannot open %s (%d)" % [url, error])


func _on_connected() -> void:
	_authenticate_request = client.send_authenticate(_token)


func _on_disconnected(code: int, reason: String) -> void:
	var was_online := user != null
	user = null
	_authenticate_request = 0
	if not _socket_opened:
		return
	_socket_opened = false
	if was_online:
		_fail("connection lost (%d %s)" % [code, reason])
		return
	_fail("cannot reach %s (%d %s)" % [server_http, code, reason])


func _on_welcome(message: SiServerMessageWelcome) -> void:
	_authenticate_request = 0
	user = message.user
	online.emit(user, message.running_lobby)


func _on_error(message: SiServerMessageError) -> void:
	if message.request_id == null or message.request_id != _authenticate_request:
		return
	_authenticate_request = 0
	# A stored token can outlive the server's secret; a fresh guest session replaces it.
	if message.code is SiErrorCodeInvalidToken and _token_is_stored:
		_token_is_stored = false
		_reauthenticating = true
		_session.request(server_http, user_name)
		return
	_fail("login refused: %s" % message.message)


## The single failure exit: no socket or flag survives it, so the next `start` begins clean.
func _fail(reason: String) -> void:
	_reset_connection()
	failed.emit(reason)


## Clears the flags before closing so the close's own `disconnected` is not taken for a failure.
func _reset_connection() -> void:
	user = null
	_socket_opened = false
	_reauthenticating = false
	_authenticate_request = 0
	client.close()
