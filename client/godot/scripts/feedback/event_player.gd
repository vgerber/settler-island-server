class_name EventPlayer
extends Node
## Plays the events of each server update before the update's view applies (doc/design/feedback.md). Board and
## Hud draw from `shown_view` and pick from `shown_legal_actions`, which change only when a beat commits, so
## feedback never touches `GameState`. The player knows no renderer: it emits `event_started` per event and
## `committed` per beat, and a 2D or 3D board hangs its animations on those signals.

signal committed
signal beat_started(events: Array[SiEvent])
signal event_started(event: SiEvent)
## The queue is drained.
signal idle
## Text for a toast of kind `error`, `info` or `alert`.
signal toast_requested(text: String, kind: StringName)
## The local seat has to act: kind `turn` (its turn starts) or `attention` (a discard or an answer is owed).
signal turn_cue(kind: StringName)

## The longest the shown state may lag behind the server, in milliseconds.
const LAG_BUDGET_MILLISECONDS := 1500.0
const MAX_PACE := 4.0
const DIGEST_LINES := 6

var shown_view: SiPlayerView = null
var shown_legal_actions: Array[SiAction] = []
var seat := 0
## Who sits where, for the lines of digests and alerts; the HUD keeps it current.
var names := SeatNames.new()
## 0 commits every beat at once; otherwise a multiplier for the holds between events.
var speed_factor := 1.0
var skip_when_unfocused := true
## Receives `play(hook)`; the game screen sets the `Sfx` autoload, tests leave it empty.
var sfx: Node = null

var _state: GameState = null
var _queue: Array[Dictionary] = []
var _running := false
## Bumped to abandon the running beat (collapse, resync, unfocus).
var _generation := 0
var _current: Dictionary = {}
var _current_events: Array[SiEvent] = []
var _current_index := 0
var _unfocused := false
var _away_digest: PackedStringArray = []


## Starts following `game_state`; the shown state is its current state.
func bind(game_state: GameState) -> void:
	_state = game_state
	seat = _state.seat
	_state.started.connect(_resync)
	_state.changed.connect(_on_changed)
	_resync()


## Stops following the state and releases it; the screen calls it before it drops the player.
func release() -> void:
	_state.release()


func legal_of(script: Script) -> Array[SiAction]:
	var matching: Array[SiAction] = []
	for action in shown_legal_actions:
		if action.get_script() == script:
			matching.append(action)
	return matching


func is_my_turn() -> bool:
	return shown_view != null and shown_view.current == seat and not is_finished()


func is_finished() -> bool:
	return shown_view != null and shown_view.phase is SiPhaseFinished


func act(action: SiAction) -> void:
	_state.act(action)


func offer_trade(action: SiActionOfferTrade) -> void:
	_state.offer_trade(action)


func is_busy() -> bool:
	return _running


## True while beats take time: animations are on and the window is in front.
func animated() -> bool:
	return speed_factor > 0.0 and not _instant()


func play_sound(hook: StringName) -> void:
	# Events without a cue have an empty hook.
	if sfx != null and hook != &"" and not _instant():
		sfx.play(hook)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_unfocused = true
		if skip_when_unfocused:
			_collapse(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_unfocused = false
		_report_away()


func _instant() -> bool:
	return _unfocused and skip_when_unfocused


func _resync() -> void:
	_generation += 1
	_queue.clear()
	_current_events = []
	seat = _state.seat
	var previous := shown_view
	shown_view = _state.view
	shown_legal_actions = _state.legal_actions
	committed.emit()
	if previous != null:
		_cue_turn(previous, shown_view)


func _on_changed(events: Array[SiEvent]) -> void:
	if events.is_empty():
		# An act only clears (or, when dropped, restores) the choices; no beat is involved.
		shown_legal_actions = _state.legal_actions
		committed.emit()
		return
	_queue.append({"events": events, "view": _state.view, "legal": _state.legal_actions})
	if _running:
		_collapse_when_behind()
		return
	_run()


func _run() -> void:
	_running = true
	while not _queue.is_empty():
		await _play(_queue.pop_front())
	_running = false
	idle.emit()


func _play(beat: Dictionary) -> void:
	var generation := _generation
	var events: Array[SiEvent] = beat["events"]
	_current = beat
	_current_events = events
	_current_index = 0
	beat_started.emit(events)
	while _current_index < events.size():
		var event := events[_current_index]
		_current_index += 1
		_start_event(event)
		var wait := _hold_seconds(event)
		if wait > 0.0:
			await get_tree().create_timer(wait).timeout
		if generation != _generation:
			return
	_current_events = []
	_commit(beat["view"], beat["legal"])


func _start_event(event: SiEvent) -> void:
	event_started.emit(event)
	if EventCues.must_show(event, seat) and _instant():
		_remember_away(event)
	play_sound(EventCues.hook(event, seat))
	_announce(event)


## Events that concern the local seat get an alert toast, whatever the speed.
func _announce(event: SiEvent) -> void:
	var worth := false
	if event is SiEventResourceStolen:
		worth = (event as SiEventResourceStolen).victim == seat
	elif event is SiEventTradeOffered:
		worth = EventCues.addressed_to(event as SiEventTradeOffered, seat)
	if worth and not _instant():
		toast_requested.emit(HudText.event_line(event, names), &"alert")


func _commit(view: SiPlayerView, legal: Array[SiAction]) -> void:
	var previous := shown_view
	shown_view = view
	shown_legal_actions = legal
	committed.emit()
	_cue_turn(previous, view)


## Own turn start or a new duty (discard, answer) for the local seat.
func _cue_turn(previous: SiPlayerView, view: SiPlayerView) -> void:
	if view.phase is SiPhaseFinished:
		return
	var kind := &""
	if view.current == seat and previous.current != seat:
		kind = &"turn"
	elif HudText.pending_seats(view).has(seat) and not HudText.pending_seats(previous).has(seat):
		kind = &"attention"
	if kind.is_empty():
		return
	_play_cue(kind)
	turn_cue.emit(kind)
	if _unfocused:
		DisplayServer.window_request_attention()


func _play_cue(kind: StringName) -> void:
	if sfx != null:
		sfx.play(&"sfx_turn_start" if kind == &"turn" else &"sfx_attention")


func _hold_seconds(event: SiEvent) -> float:
	if speed_factor <= 0.0 or _instant():
		return 0.0
	return EventCues.hold_milliseconds(event) / 1000.0 / (speed_factor * _pace())


## Nominal time of everything not yet shown.
func _backlog_milliseconds() -> float:
	var total := 0.0
	for index in range(_current_index, _current_events.size()):
		total += EventCues.hold_milliseconds(_current_events[index])
	for beat in _queue:
		for event: SiEvent in beat["events"]:
			total += EventCues.hold_milliseconds(event)
	return total


func _pace() -> float:
	return clampf(_backlog_milliseconds() / LAG_BUDGET_MILLISECONDS, 1.0, MAX_PACE)


## Past the budget even at the top pace, the queued animations are dropped and only the must-show events stay.
func _collapse_when_behind() -> void:
	if speed_factor > 0.0 and _backlog_milliseconds() / (_pace() * speed_factor) > LAG_BUDGET_MILLISECONDS:
		_collapse(false)


## Logs every event not shown yet, keeps the must-show ones as one toast (or as the away digest) and commits
## the newest view.
func _collapse(for_away: bool) -> void:
	if not _running:
		return
	_generation += 1
	var pending: Array[SiEvent] = _current_events.slice(_current_index)
	for beat in _queue:
		pending.append_array(beat["events"])
	var latest: Dictionary = _queue.back() if not _queue.is_empty() else _current
	_queue.clear()
	var kept := PackedStringArray()
	for event in pending:
		event_started.emit(event)
		if EventCues.must_show(event, seat):
			kept.append(HudText.event_line(event, names))
	_current_events = []
	_commit(latest["view"], latest["legal"])
	_deliver_collapsed(kept, for_away)


func _deliver_collapsed(kept: PackedStringArray, for_away: bool) -> void:
	if for_away:
		for line in kept:
			_remember_line(line)
		return
	if not kept.is_empty():
		toast_requested.emit("\n".join(kept.slice(maxi(0, kept.size() - 3))), &"info")


func _remember_away(event: SiEvent) -> void:
	_remember_line(HudText.event_line(event, names))


func _remember_line(line: String) -> void:
	_away_digest.append(line)
	if _away_digest.size() > DIGEST_LINES:
		_away_digest.remove_at(0)


func _report_away() -> void:
	if _away_digest.is_empty():
		return
	toast_requested.emit("While you were away:\n" + "\n".join(_away_digest), &"info")
	_away_digest.clear()
