class_name ConnectScreen
extends Control
## Server address and guest name. With a stored session it connects on its own, so a restarted
## client goes straight back into a running game.

const DEFAULT_SERVER := "http://127.0.0.1:8253"

## Only the first connect screen of a run connects on its own; after a failure the player decides.
static var _tried_stored_session: bool = false

@onready var _server_edit: LineEdit = %ServerEdit
@onready var _name_edit: LineEdit = %NameEdit
@onready var _connect_button: Button = %ConnectButton
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	_connect_button.pressed.connect(_on_connect)
	_name_edit.text_submitted.connect(func(_text: String) -> void: _on_connect())
	Net.failed.connect(_on_failed)
	Net.online.connect(_on_online)
	var last_login := Net.last_login()
	_server_edit.text = str(last_login.get("server", DEFAULT_SERVER))
	_name_edit.text = str(last_login.get("name", ""))
	if _tried_stored_session or Net.stored_token(_server_edit.text, _name_edit.text).is_empty():
		return
	_tried_stored_session = true
	_on_connect()


func _on_connect() -> void:
	var user_name := _name_edit.text.strip_edges()
	if user_name.is_empty():
		_status_label.text = "Enter a name"
		return
	_set_busy(true)
	_status_label.text = "Connecting..."
	Net.start(_server_edit.text, user_name)


func _on_failed(reason: String) -> void:
	_set_busy(false)
	_status_label.text = reason


func _on_online(user: SiUser, running_lobby: Variant) -> void:
	_status_label.text = "Rejoining the running game..." if running_lobby != null else "Welcome, %s" % user.name


func _set_busy(busy: bool) -> void:
	_connect_button.disabled = busy
	_server_edit.editable = not busy
	_name_edit.editable = not busy
