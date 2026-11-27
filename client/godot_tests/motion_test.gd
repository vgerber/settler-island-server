extends SceneTree
## Runs inside a copy of the game project (client/godot): the motion layer of `Board3D`. The dice land on the server's
## faces for all 36 outcomes (snapped, and after a real animated throw), `finish_all` leaves no tween, ghost or token
## behind even after a burst larger than the token pool (the collapse path), and a commit that adds a piece replaces
## its ghost in the same call.
## Usage: godot --headless --path <copy of client/godot> -s motion_test.gd -- <fixtures.json>
## The fixtures are the ones of board3d_test.gd.

var _fixtures: Dictionary = {}
var _begun := false
var _failures: PackedStringArray = []
var _board: Board3D = null
var _client := SiRecordingClient.new()


func _init() -> void:
	var text := FileAccess.get_file_as_string(SiTestSupport.argument(0))
	_fixtures = JSON.parse_string(text) if not text.is_empty() else {}


func _process(_delta: float) -> bool:
	if _begun:
		return false
	_begun = true
	_run()
	return false


func _run() -> void:
	if _fixtures.is_empty():
		SiTestSupport.finish(self, 1, "MOTION_FAILED missing fixtures")
		return
	root.size = Vector2i(1600, 900)
	_build_board()
	_check_every_roll()
	await _check_animated_throw()
	_check_burst_finishes_clean()
	_check_commit_replaces_the_ghost()
	_check_nothing_animates_when_off()
	_board.player.release()
	_board.free()
	_client.free()
	if _failures.is_empty():
		SiTestSupport.finish(self, 0, "MOTION_OK")
		return
	SiTestSupport.finish(self, 1, "MOTION_FAILED %s" % "; ".join(_failures))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _build_board() -> void:
	var started := SiServerMessage.from_dict(_fixtures["middle"]) as SiServerMessageGameStarted
	var state := GameState.new(_client, started)
	_board = Board3D.new()
	root.add_child(_board)
	_board.size = Vector2(1260.0, 676.0)
	_board.hand_slot = func(_resource: String) -> Vector2: return Vector2(400.0, 860.0)
	var player := EventPlayer.new()
	_board.add_child(player)
	player.bind(state)
	_board.bind(player)
	player.speed_factor = 1.0


func _dice_event(first: int, second: int) -> SiEventDiceRolled:
	var event := SiEventDiceRolled.new()
	event.seat = _board.player.seat
	event.first = first
	event.second = second
	return event


func _check_every_roll() -> void:
	var dice := _board.motion.dice
	for first in range(1, 7):
		for second in range(1, 7):
			dice.roll(_dice_event(first, second), false)
			_expect(dice.top_value(0) == first and dice.top_value(1) == second, "snapped roll %d %d shows %d %d" % [first, second, dice.top_value(0), dice.top_value(1)])


func _check_animated_throw() -> void:
	var dice := _board.motion.dice
	dice.roll(_dice_event(3, 6), true)
	_expect(dice.running_tweens() == 1, "an animated throw runs one tween")
	await create_timer(1.0).timeout
	_expect(dice.running_tweens() == 0, "the throw ends by itself")
	_expect(dice.top_value(0) == 3 and dice.top_value(1) == 6, "the thrown dice rest on 3 and 6, got %d %d" % [dice.top_value(0), dice.top_value(1)])


## Every kind of event twice, more cards than the pool holds: the state a collapse finds.
func _check_burst_finishes_clean() -> void:
	var player := _board.player
	var view := player.shown_view
	var counts: Array[int] = [2, 2, 2, 2, 2]
	for round in 3:
		for event in _events(view, counts):
			player.event_started.emit(event)
	var motion := _board.motion
	_expect(motion.pieces.ghost_count() > 0 and motion.cards.flights_in_air() > 0, "the burst starts ghosts and flights")
	_expect(motion.cards.tokens_in_use() <= CardFlights.POOL_SIZE + CardFlights.FLAT_POOL_SIZE, "the pool is never exceeded")
	player.event_started.emit(_dice_event(2, 5))
	motion.finish_all()
	_expect_idle("after finish_all")
	_expect(_board.motion.dice.top_value(0) == 2 and _board.motion.dice.top_value(1) == 5, "finish_all lands the dice on their faces")


func _expect_idle(when: String) -> void:
	var motion := _board.motion
	for layer: MotionLayer in [motion.dice, motion.pieces, motion.cards]:
		_expect(layer.running_tweens() == 0, "%s: %s still has tweens" % [when, layer.name])
	_expect(motion.pieces.ghost_count() == 0, "%s: ghosts left" % when)
	_expect(motion.cards.flights_in_air() == 0 and motion.cards.tokens_in_use() == 0, "%s: tokens in flight" % when)


func _events(view: SiPlayerView, counts: Array[int]) -> Array[SiEvent]:
	var seat := _board.player.seat
	var other := (seat + 1) % view.players.size()
	var board := view.board
	var events: Array[SiEvent] = []
	var settlement := SiEventSettlementPlaced.new()
	settlement.seat = seat
	settlement.corner = board.buildings.find(null)
	events.append(settlement)
	var road := SiEventRoadPlaced.new()
	road.seat = seat
	road.edge = board.roads.find(null)
	events.append(road)
	var city := SiEventCityBuilt.new()
	city.seat = seat
	city.corner = board.buildings.find(null)
	events.append(city)
	var robber := SiEventRobberMoved.new()
	robber.seat = seat
	robber.tile = (board.robber + 1) % board.tiles.size()
	events.append(robber)
	var produced := SiEventResourcesProduced.new()
	produced.seat = seat
	produced.resources = counts
	events.append(produced)
	var paid := SiEventResourcesPaid.new()
	paid.seat = other
	paid.resources = counts
	events.append(paid)
	var stolen := SiEventResourceStolen.new()
	stolen.thief = seat
	stolen.victim = other
	stolen.resource = SiResource.VALUES[0]
	events.append(stolen)
	var traded := SiEventBankTraded.new()
	traded.seat = seat
	traded.gave = counts
	traded.received = counts
	events.append(traded)
	return events


func _check_commit_replaces_the_ghost() -> void:
	var player := _board.player
	var view := player.shown_view
	var corner := view.board.buildings.find(null)
	var event := SiEventSettlementPlaced.new()
	event.seat = player.seat
	event.corner = corner
	var before := _board.scene.piece_count()
	player.event_started.emit(event)
	_expect(_board.motion.pieces.ghost_count() > 0, "a placed settlement starts a ghost")
	_expect(_board.scene.piece_count() == before, "the static set does not change while the ghost plays")
	var next := SiPlayerView.from_dict(view.to_dict())
	var building := SiBuilding.new()
	building.seat = player.seat
	building.kind = SiBuildingKind.SETTLEMENT
	next.board.buildings[corner] = building
	player.shown_view = next
	player.committed.emit()
	_expect(_board.scene.piece_count() == before + 1, "the commit adds exactly one static piece")
	_expect(_board.motion.pieces.ghost_count() == 0, "the ghost is gone in the same call")
	_expect_idle("after commit")


func _check_nothing_animates_when_off() -> void:
	var player := _board.player
	player.speed_factor = 0.0
	var counts: Array[int] = [1, 1, 1, 1, 1]
	for event in _events(player.shown_view, counts):
		player.event_started.emit(event)
	player.event_started.emit(_dice_event(4, 4))
	_expect_idle("animation off")
	_expect(_board.motion.dice.top_value(0) == 4 and _board.motion.dice.top_value(1) == 4, "animation off: dice sit on their faces")
