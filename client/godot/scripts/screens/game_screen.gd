class_name GameScreen
extends Control
## Owns the `GameState` of the running game and its `EventPlayer`, and hands the player to `Board` and `Hud`.
## The board fills the HUD's free middle area, so the HUD decides the layout and the board follows it.

@onready var _board: Board = %Board
@onready var _hud: Hud = %Hud

var state: GameState = null
var player := EventPlayer.new()
var _settings_popup: HudSettingsPopup = null


func _ready() -> void:
	player.name = "EventPlayer"
	add_child(player)
	player.sfx = Sfx
	_apply_settings()
	Settings.changed.connect(_apply_settings)
	_settings_popup = HudSettingsPopup.new()
	add_child(_settings_popup)
	_hud.settings_requested.connect(_open_settings)
	_hud.leave_requested.connect(func() -> void: Net.client.send_leave_lobby())
	_hud.target_filter_changed.connect(_board.set_target_filter)
	Net.client.lobby_state_received.connect(_on_lobby_state)
	_hud.board_slot.item_rect_changed.connect(_fit_board)
	_fit_board()


func _exit_tree() -> void:
	if state != null:
		player.release()


func begin(started: SiServerMessageGameStarted) -> void:
	state = GameState.new(Net.client, started)
	state.refused.connect(_on_refused)
	player.bind(state)
	_board.bind(player)
	_hud.bind(player, SeatNames.from_lobby(Net.lobby, started.seat))


func _on_lobby_state(message: SiServerMessageLobbyState) -> void:
	if state != null:
		_hud.show_names(SeatNames.from_lobby(message.lobby, state.seat))


## Places the board over the HUD's board slot, whatever mode the HUD is in.
func _fit_board() -> void:
	var slot := _hud.board_slot.get_global_rect()
	_board.position = slot.position - global_position
	_board.size = slot.size


func _apply_settings() -> void:
	player.speed_factor = Settings.speed_factor()
	player.skip_when_unfocused = Settings.skip_when_unfocused


func _open_settings() -> void:
	_settings_popup.open_below(_hud.settings_anchor())


## A refused action shows at once, never queued behind the events being played.
func _on_refused(message: String) -> void:
	_hud.toasts.push(message, &"error")
	Sfx.play(&"sfx_error")
