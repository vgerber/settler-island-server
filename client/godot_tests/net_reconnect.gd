extends SceneTree
## Runs inside a copy of the game project with its `Net` autoload: a start against a dead address fails,
## and the next start against the real server goes online.
## Usage: godot --headless --path <project> -s net_reconnect.gd -- <http://host:port>

const DEAD_SERVER := "http://127.0.0.1:1"
const TIMEOUT_SECONDS := 15.0

var _net: Node
var _server_http := ""
var _failed_once := false
var _elapsed := 0.0
var _done := false


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty():
		_finish(1, "NET_RECONNECT_FAILED missing server address")
		return
	_server_http = arguments[0]
	_net = root.get_node("Net")
	_net.failed.connect(_on_failed)
	_net.online.connect(_on_online)
	# The autoload connects its session signals in `_ready`, which runs after `_initialize`.
	_net.start.call_deferred(DEAD_SERVER, "reconnect-test")


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > TIMEOUT_SECONDS:
		_finish(1, "NET_RECONNECT_FAILED timeout (failed once: %s)" % _failed_once)
	return _done


func _on_failed(_reason: String) -> void:
	if _failed_once:
		_finish(1, "NET_RECONNECT_FAILED failed twice")
		return
	_failed_once = true
	_net.start(_server_http, "reconnect-test")


func _on_online(_user: SiUser, _running_lobby: Variant) -> void:
	if not _failed_once:
		_finish(1, "NET_RECONNECT_FAILED online before the failure")
		return
	_finish(0, "NET_RECONNECT_OK")


func _finish(code: int, line: String) -> void:
	if _done:
		return
	_done = true
	print(line)
	quit(code)
