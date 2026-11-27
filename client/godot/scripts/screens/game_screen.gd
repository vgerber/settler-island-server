class_name GameScreen
extends Control
## Owns the `GameState` of the running game and hands it to `Board` and `Hud`. The board fills the HUD's free
## middle area, so the HUD decides the layout and the board follows it.

@onready var _board: Board = %Board
@onready var _hud: Hud = %Hud

var state: GameState = null


func _ready() -> void:
	_hud.leave_requested.connect(func() -> void: Net.client.send_leave_lobby())
	_hud.target_filter_changed.connect(_board.set_target_filter)
	Net.client.lobby_state_received.connect(_on_lobby_state)
	_hud.board_slot.item_rect_changed.connect(_fit_board)
	_fit_board()


func _exit_tree() -> void:
	if state != null:
		state.release()


func begin(started: SiServerMessageGameStarted) -> void:
	state = GameState.new(Net.client, started)
	_board.bind(state)
	_hud.bind(state, SeatNames.from_lobby(Net.lobby, started.seat))


func _on_lobby_state(message: SiServerMessageLobbyState) -> void:
	if state != null:
		_hud.show_names(SeatNames.from_lobby(message.lobby, state.seat))


## Places the board over the HUD's board slot, whatever mode the HUD is in.
func _fit_board() -> void:
	var slot := _hud.board_slot.get_global_rect()
	_board.position = slot.position - global_position
	_board.size = slot.size
