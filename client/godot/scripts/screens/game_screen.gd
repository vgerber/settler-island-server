class_name GameScreen
extends Control
## Owns the `GameState` of the running game and hands it to `Board` and `Hud`. Until the HUD exists,
## the status bar shows phase, current seat and the legal action count, with a roll/end turn button.

@onready var _board: Board = %Board
@onready var _hud: Hud = %Hud
@onready var _status_label: Label = %StatusLabel
@onready var _action_button: Button = %ActionButton
@onready var _back_button: Button = %BackButton

var state: GameState = null
## The action `_action_button` sends, always one of the current legal actions.
var _button_action: SiAction = null


func _ready() -> void:
	_action_button.pressed.connect(_on_action_pressed)
	_back_button.pressed.connect(func() -> void: Net.client.send_leave_lobby())


func _exit_tree() -> void:
	if state != null:
		state.release()


func begin(started: SiServerMessageGameStarted) -> void:
	state = GameState.new(Net.client, started)
	state.changed.connect(func(_events: Array[SiEvent]) -> void: _refresh())
	_board.bind(state)
	_hud.bind(state)
	_refresh()


func _refresh() -> void:
	var view := state.view
	var phase := str(view.phase.to_dict().get("type", "?"))
	var turn := "your turn" if state.is_my_turn() else "seat %d to play" % (view.current + 1)
	if view.phase is SiPhaseFinished:
		turn = "seat %d won" % ((view.phase as SiPhaseFinished).winner + 1)
	_status_label.text = "You are seat %d  -  turn %d  -  %s  -  %s  -  %d legal actions" % [
		state.seat + 1, view.turn_number, phase, turn, state.legal_actions.size(),
	]
	_button_action = _pick_button_action()
	_action_button.visible = _button_action != null
	_action_button.text = "Roll" if _button_action is SiActionRollDice else "End turn"
	_back_button.visible = state.is_finished()


func _pick_button_action() -> SiAction:
	for script: Script in [SiActionRollDice, SiActionEndTurn]:
		var matching := state.legal_of(script)
		if not matching.is_empty():
			return matching[0]
	return null


func _on_action_pressed() -> void:
	if _button_action != null:
		state.act(_button_action)
