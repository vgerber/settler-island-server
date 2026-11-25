class_name GameState
extends RefCounted
## The client's copy of one running game: the latest view, the legal actions of the own seat and the
## last events. Owned by the game screen; `Board` and `Hud` read it and call `act`.

signal changed(events: Array[SiEvent])
## A request of this game was refused; the state is resynchronised from the server afterwards.
signal refused(message: String)

var client: SiClient = null
var seat: int = 0
var view: SiPlayerView = null
var legal_actions: Array[SiAction] = []
var events: Array[SiEvent] = []

## The Act request whose reply is outstanding; legal actions of updates sent before it are stale.
var _awaiting_act: int = 0


func _init(game_client: SiClient, started: SiServerMessageGameStarted) -> void:
	client = game_client
	_take_started(started)
	client.game_started_received.connect(_take_started)
	client.game_update_received.connect(_on_game_update)
	client.error_received.connect(_on_error)


## Stops listening; the screen calls it before it drops the state.
func release() -> void:
	client.game_started_received.disconnect(_take_started)
	client.game_update_received.disconnect(_on_game_update)
	client.error_received.disconnect(_on_error)


## Sends one of `legal_actions`; until the reply lands no further action is legal.
func act(action: SiAction) -> void:
	if not legal_actions.has(action):
		push_warning("GameState: ignoring an action that is not among the legal ones")
		return
	_awaiting_act = client.send_act(action)
	legal_actions = []
	changed.emit([] as Array[SiEvent])


## All legal actions of one variant class, e.g. `legal_of(SiActionBuildRoad)`.
func legal_of(script: Script) -> Array[SiAction]:
	var matching: Array[SiAction] = []
	for action in legal_actions:
		if action.get_script() == script:
			matching.append(action)
	return matching


func is_my_turn() -> bool:
	return view != null and view.current == seat and not is_finished()


func is_finished() -> bool:
	return view != null and view.phase is SiPhaseFinished


func _take_started(message: SiServerMessageGameStarted) -> void:
	_awaiting_act = 0
	seat = message.seat
	view = message.view
	legal_actions = message.legal_actions
	events = []
	changed.emit(events)


func _on_game_update(message: SiServerMessageGameUpdate) -> void:
	view = message.view
	events = message.events
	var answers_my_act: bool = message.request_id != null and message.request_id == _awaiting_act
	if answers_my_act:
		_awaiting_act = 0
	if _awaiting_act == 0:
		legal_actions = message.legal_actions
	changed.emit(events)


func _on_error(message: SiServerMessageError) -> void:
	if message.request_id == null or message.request_id != _awaiting_act:
		return
	_awaiting_act = 0
	refused.emit(message.message)
	# The refused action came from stale legal actions; `GameStarted` brings the current ones.
	client.send_get_state()
