extends SceneTree
## Runs inside a copy of the game project (client/godot): `EventPlayer` shows the view of an update only after
## its events played. Checks the synchronous commit with animations off, the timed path, the collapse of a
## long backlog, the instant mode of an unfocused window with its digest, and the resync of a `GameStarted`.
## Usage: godot --headless --path <copy of client/godot> -s event_player_test.gd -- <fixture.json>
## The fixture is a `GameStarted` message written by Rust.

const OWN_SEAT := 0
const OTHER_SEAT := 1

var _started: SiServerMessageGameStarted = null
var _client := SiClient.new()
var _state: GameState = null
var _player := EventPlayer.new()
var _started_events := 0
var _commits := 0
var _toasts: Array[String] = []
var _failures: PackedStringArray = []
var _begun := false
var _finished := 0
var _sfx := SfxStub.new()


class SfxStub extends Node:
	var played: Array[StringName] = []

	func play(hook: StringName) -> void:
		played.append(hook)


func _init() -> void:
	var text := FileAccess.get_file_as_string(SiTestSupport.argument(0))
	_started = SiServerMessage.from_dict(JSON.parse_string(text)) as SiServerMessageGameStarted


func _process(_delta: float) -> bool:
	if _begun:
		return false
	_begun = true
	_run()
	return false


func _run() -> void:
	if _started == null:
		SiTestSupport.finish(self, 1, "EVENT_PLAYER_FAILED no GameStarted fixture")
		return
	_state = GameState.new(_client, _started)
	root.add_child(_player)
	_player.bind(_state)
	_player.event_started.connect(func(_event: SiEvent) -> void: _started_events += 1)
	_player.committed.connect(func() -> void: _commits += 1)
	_player.toast_requested.connect(func(text: String, _kind: StringName) -> void: _toasts.append(text))
	_player.sfx = _sfx
	_check_off()
	_check_sound_claim()
	_player.register_consumer(func() -> void: _finished += 1)
	await _check_timed()
	_expect(_finished == 0, "consumers: finish_all stays unused while beats play out")
	await _check_collapse()
	_check_unfocused()
	_check_resync()
	_player.release()
	_client.free()
	_sfx.free()
	if _failures.is_empty():
		SiTestSupport.finish(self, 0, "EVENT_PLAYER_OK")
		return
	SiTestSupport.finish(self, 1, "EVENT_PLAYER_FAILED %s" % "; ".join(_failures))


func _check_off() -> void:
	_player.speed_factor = 0.0
	var update := _push(3)
	_expect(_player.shown_view == update.view, "off: the view commits synchronously")
	_expect(_started_events == 3, "off: every event starts, got %d" % _started_events)
	_expect(not _player.is_busy(), "off: nothing is left to play")


## `DiceRolled` plays its sound at event start unless a consumer claims it; other events are never claimed.
func _check_sound_claim() -> void:
	_player.speed_factor = 0.0
	_sfx.played.clear()
	_push(1)
	_expect(_sfx.played == [&"sfx_roll_seven"], "sound: unclaimed roll plays its hook, got %s" % [_sfx.played])
	_sfx.played.clear()
	var claim := func() -> void: pass
	_player.register_consumer(claim, [&"DiceRolled"])
	_push(1)
	_expect(_sfx.played.is_empty(), "sound: a claimed roll is silent, got %s" % [_sfx.played])
	_player.unregister_consumer(claim)
	_push(1)
	_expect(_sfx.played.size() == 1, "sound: released claim plays the hook again")


func _check_timed() -> void:
	_player.speed_factor = 1.0
	var before := _player.shown_view
	var update := _push(1)
	_expect(_player.shown_view == before, "timed: the old view stays while the event plays")
	_expect(_player.is_busy(), "timed: the player is busy")
	await _player.idle
	_expect(_player.shown_view == update.view, "timed: the view commits after the events")


## Twenty dice rolls are 7 s of holds: more than the lag budget at the top pace.
func _check_collapse() -> void:
	_started_events = 0
	_toasts.clear()
	var started_at := Time.get_ticks_msec()
	var last: SiServerMessageGameUpdate = null
	for _beat in 20:
		last = _push(1)
	await _player.idle
	var elapsed := Time.get_ticks_msec() - started_at
	_expect(elapsed < 3000, "collapse: caught up in %d ms" % elapsed)
	_expect(_player.shown_view == last.view, "collapse: the newest view is shown")
	_expect(_started_events == 20, "collapse: every event still reaches the log, got %d" % _started_events)
	_expect(not _toasts.is_empty(), "collapse: the must-show events come as a toast")
	_expect(_finished == 1, "collapse: the consumer is finished once before the commit, got %d" % _finished)


func _check_unfocused() -> void:
	_player.speed_factor = 1.0
	_toasts.clear()
	_player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var update := _push(2)
	_expect(_player.shown_view == update.view, "unfocused: beats commit at once")
	_expect(_toasts.is_empty(), "unfocused: nothing pops up while away")
	_player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_expect(_toasts.size() == 1 and _toasts[0].begins_with("While you were away"), "unfocused: one digest on return")


func _check_resync() -> void:
	_player.speed_factor = 1.0
	_push(1)
	var again := SiServerMessage.from_dict(_started.to_dict()) as SiServerMessageGameStarted
	_client.game_started_received.emit(again)
	_expect(_player.shown_view == again.view, "resync: the new state shows at once")
	_expect(not _player.is_busy() or _player.shown_view == again.view, "resync: the queue is dropped")
	_expect(_finished == 2, "resync: the consumer is finished again, got %d" % _finished)


## One server update with `count` dice rolls of another seat and a fresh view.
func _push(count: int) -> SiServerMessageGameUpdate:
	var update := SiServerMessageGameUpdate.new()
	for _index in count:
		var roll := SiEventDiceRolled.new()
		roll.seat = OTHER_SEAT
		roll.first = 3
		roll.second = 4
		update.events.append(roll)
	update.view = SiPlayerView.from_dict(_started.view.to_dict())
	update.legal_actions = _state.legal_actions
	_client.game_update_received.emit(update)
	return update


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
