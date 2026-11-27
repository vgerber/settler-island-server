extends SceneTree
## The 3D motion that is not built yet (doc/plans/godot-3d.md, Status): each check names its symptom and fails today.
## Run only by the ignored Rust test; it passes once the cut is built.
## Usage: godot --headless --path <copy of client/godot> -s motion_cuts_test.gd -- <fixtures.json>

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
	root.size = Vector2i(1600, 900)
	var started := SiServerMessage.from_dict(_fixtures["middle"]) as SiServerMessageGameStarted
	_board = Board3D.new()
	root.add_child(_board)
	_board.size = Vector2(1260.0, 676.0)
	_board.hand_slot = func(_resource: String) -> Vector2: return Vector2(400.0, 860.0)
	var player := EventPlayer.new()
	_board.add_child(player)
	player.bind(GameState.new(_client, started))
	_board.bind(player)
	player.speed_factor = 1.0
	await _check_victim_stand_shakes()
	_check_award_glows_the_roads()
	_board.player.release()
	_board.free()
	_client.free()
	if _failures.is_empty():
		SiTestSupport.finish(self, 0, "CUTS_OK")
		return
	SiTestSupport.finish(self, 1, "CUTS_FAILED %s" % "; ".join(_failures))


## Symptom: a steal does not move the victim's stand, so the loss is only visible in the card counts.
func _check_victim_stand_shakes() -> void:
	var player := _board.player
	var victim := (player.seat + 1) % player.shown_view.players.size()
	var rest := _board.scene.stand_node(victim).position
	var stolen := SiEventResourceStolen.new()
	stolen.thief = player.seat
	stolen.victim = victim
	stolen.resource = SiResource.VALUES[0]
	player.event_started.emit(stolen)
	await create_timer(0.1).timeout
	if _board.scene.stand_node(victim).position.is_equal_approx(rest):
		_failures.append("the victim's stand does not shake after a steal")
	_board.motion.finish_all()


## Symptom: the roads of the new longest road holder do not glow while the badge flies to the holder's stand.
func _check_award_glows_the_roads() -> void:
	var player := _board.player
	var holder := player.seat
	var award := SiEventLongestRoadChanged.new()
	award.length = 5
	award.holder = holder
	var roads: Array[MeshInstance3D] = []
	for edge in player.shown_view.board.roads.size():
		var seat: Variant = player.shown_view.board.roads[edge]
		if seat != null and int(seat) == holder:
			roads.append(_board.scene.node_of("e%d" % edge) as MeshInstance3D)
	var before: Array[Material] = []
	for road in roads:
		before.append(road.material_override)
	player.event_started.emit(award)
	for index in roads.size():
		if roads[index].material_override == before[index]:
			_failures.append("road %d of the holder does not glow" % index)
			break
	_board.motion.finish_all()
