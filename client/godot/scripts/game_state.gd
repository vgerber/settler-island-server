class_name GameState
extends RefCounted
## The client's copy of one running game: the latest view, the legal actions of the own seat and the
## last events. Owned by the game screen; `Board` and `Hud` read it and call `act`.

signal changed(events: Array[SiEvent])
## A `GameStarted` (first or resync) replaced the whole state; `changed` follows with no events.
signal started
## The server refused the outstanding Act; the text is for the player.
signal refused(message: String)

var client: SiClient = null
var seat: int = 0
var view: SiPlayerView = null
var legal_actions: Array[SiAction] = []
var events: Array[SiEvent] = []

## The Act request whose reply is outstanding; legal actions of updates sent before it are stale.
var _awaiting_act: int = 0
## The legal actions the outstanding Act was chosen from, given back when the server drops the Act.
var _legal_before_act: Array[SiAction] = []


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
	_send(action)


## Offers are never among the legal actions (their contents are free); the server validates them.
func offer_trade(action: SiActionOfferTrade) -> void:
	if not legal_of(SiActionEndTurn).is_empty():
		_send(action)


## Until the server answers, no further action may be sent from the now stale legal actions.
func _send(action: SiAction) -> void:
	_awaiting_act = client.send_act(action)
	_legal_before_act = legal_actions
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
	started.emit()
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
	if message.code is SiErrorCodeRateLimited and _awaiting_act != 0:
		_take_back_dropped_act()
		return
	if message.request_id == null or message.request_id != _awaiting_act:
		return
	_awaiting_act = 0
	refused.emit(message.message)
	# `Main` shows the server's message as a toast; here only the state is resynchronised.
	# The refused action came from stale legal actions; `GameStarted` brings the current ones.
	client.send_get_state()


## The rate limiter drops a message unread and names no request; when that was our Act, nothing else
## would ever arrive, so the seat gets its choices back. An update for the Act, should it come, still wins.
func _take_back_dropped_act() -> void:
	_awaiting_act = 0
	legal_actions = _legal_before_act
	changed.emit([] as Array[SiEvent])
