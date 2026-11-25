class_name GameScreen
extends Control
## Owns the `GameState` of the running game and hands it to `Board` and `Hud`.

@onready var _board: Board = %Board
@onready var _hud: Hud = %Hud

var state: GameState = null


func _ready() -> void:
	_hud.leave_requested.connect(func() -> void: Net.client.send_leave_lobby())


func _exit_tree() -> void:
	if state != null:
		state.release()


func begin(started: SiServerMessageGameStarted) -> void:
	state = GameState.new(Net.client, started)
	_board.bind(state)
	_hud.bind(state)
