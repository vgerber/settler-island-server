extends SceneTree
## Runs inside a copy of the game project against a real server: a name one character over the limit
## shows the server's HttpError message on the connect screen, the longest name the name field accepts
## goes online, and the lobby browser offers exactly the protocol's seat and points range.
## Usage: godot --headless --path <project> -s screen_limits.gd -- <fixture.json>
## The fixture holds `server` (http://host:port) and `invalid_name_message` (the server's text).

const TIMEOUT_MILLISECONDS := 15000

var _net: Node
var _screen: Control
var _server_http := ""
var _invalid_name_message := ""
var _deadline := 0
var _rejected_once := false
var _done := false


func _initialize() -> void:
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(SiTestSupport.argument(0)))
	if not fixture is Dictionary:
		_finish(1, "SCREEN_LIMITS_FAILED unreadable fixture")
		return
	_server_http = str(fixture["server"])
	_invalid_name_message = str(fixture["invalid_name_message"])
	_deadline = SiTestSupport.deadline_in(TIMEOUT_MILLISECONDS)
	_net = root.get_node("Net")
	_screen = load("res://scenes/connect.tscn").instantiate()
	root.add_child.call_deferred(_screen)
	_start_too_long.call_deferred()


func _process(_delta: float) -> bool:
	if not _done and SiTestSupport.expired(_deadline):
		_finish(1, "SCREEN_LIMITS_FAILED timed out (rejected once: %s)" % _rejected_once)
	return _done


## Bypasses the name field, so the server itself must refuse the name and explain why.
func _start_too_long() -> void:
	_net.failed.connect(_on_failed)
	_net.online.connect(_on_online)
	_net.start(_server_http, "n".repeat(SiLimits.MAX_USER_NAME_CHARS + 1))


func _on_failed(_reason: String) -> void:
	if _rejected_once:
		_finish(1, "SCREEN_LIMITS_FAILED the longest accepted name was refused: %s" % _label("%StatusLabel").text)
		return
	_rejected_once = true
	_check_rejection.call_deferred()


func _check_rejection() -> void:
	var shown := _label("%StatusLabel").text
	if shown != _invalid_name_message:
		_finish(1, "SCREEN_LIMITS_FAILED status shows %s, expected %s" % [shown, _invalid_name_message])
		return
	_connect_with_the_longest_name()


## Types more than any limit into the name field and connects through the button.
func _connect_with_the_longest_name() -> void:
	var name_edit: LineEdit = _screen.get_node("%NameEdit")
	var server_edit: LineEdit = _screen.get_node("%ServerEdit")
	server_edit.text = _server_http
	name_edit.text = "n".repeat(1000)
	if name_edit.text.length() == 1000:
		_finish(1, "SCREEN_LIMITS_FAILED the name field has no length limit")
		return
	var button: Button = _screen.get_node("%ConnectButton")
	button.pressed.emit()


func _on_online(user: SiUser, _running_lobby: Variant) -> void:
	var typed: String = (_screen.get_node("%NameEdit") as LineEdit).text
	if user.name != typed:
		_finish(1, "SCREEN_LIMITS_FAILED online as %s, typed %s" % [user.name, typed])
		return
	_check_lobby_browser()


func _check_lobby_browser() -> void:
	var browser: Control = load("res://scenes/lobby_browser.tscn").instantiate()
	root.add_child(browser)
	var points: SpinBox = browser.get_node("%PointsSpin")
	var seats: OptionButton = browser.get_node("%SeatsOption")
	var lobby_name: LineEdit = browser.get_node("%LobbyNameEdit")
	var problems: Array[String] = []
	if points.min_value != SiLimits.MIN_POINTS_TO_WIN or points.max_value != SiLimits.MAX_POINTS_TO_WIN:
		problems.append("points range %d-%d" % [points.min_value, points.max_value])
	if points.value != SiLimits.DEFAULT_POINTS_TO_WIN:
		problems.append("points default %d" % points.value)
	if seats.item_count != SiLimits.MAX_SEATS - SiLimits.MIN_SEATS + 1:
		problems.append("%d seat choices" % seats.item_count)
	if lobby_name.max_length != SiLimits.MAX_LOBBY_NAME_CHARS:
		problems.append("lobby name limit %d" % lobby_name.max_length)
	if not problems.is_empty():
		_finish(1, "SCREEN_LIMITS_FAILED lobby browser: %s" % ", ".join(problems))
		return
	_finish(0, "SCREEN_LIMITS_OK")


func _label(path: String) -> Label:
	return _screen.get_node(path)


func _finish(code: int, line: String) -> void:
	if _done:
		return
	_done = true
	SiTestSupport.finish(self, code, line)
