extends SceneTree
## Runs inside a copy of the game project (client/godot): feeds `Board3D` the `GameStarted` fixtures written by
## godot.rs and checks that every legal target type can be picked at its own screen point (at both slot sizes and
## three pitches), that the island fits the slot at both resolutions, that the filter narrows the targets, that a
## second commit builds no node twice and that a camera drag sends no action.
## Projection is the rig's own camera formula, so everything runs headless; one check compares it with
## `Camera3D.unproject_position`.
## Usage: godot --headless --path <copy of client/godot> -s board3d_test.gd -- <fixtures.json>

## The board slot at 1600x900 and 1280x720.
const SLOT_SIZES: Array[Vector2] = [Vector2(1260.0, 676.0), Vector2(1008.0, 541.0)]
const PITCHES: Array[float] = [30.0, 55.0, 80.0]

var _fixtures: Dictionary = {}
var _started := false
var _boards: Array[Board3D] = []
var _clients: Array[SiRecordingClient] = []


func _init() -> void:
	var text := FileAccess.get_file_as_string(SiTestSupport.argument(0))
	_fixtures = JSON.parse_string(text) if not text.is_empty() else {}


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	root.size = Vector2i(1600, 900)
	if _fixtures.is_empty():
		return _finish("missing fixtures")
	var failure := _pick_failure()
	for check: Callable in [_framing_failure, _filter_failure, _sync_failure, _drag_failure]:
		if failure.is_empty():
			failure = check.call()
	return _finish(failure)


func _finish(failure: String) -> bool:
	for board in _boards:
		board.player.release()
		board.free()
	for client in _clients:
		client.free()
	if failure.is_empty():
		SiTestSupport.finish(self, 0, "BOARD3D_OK")
	else:
		SiTestSupport.finish(self, 1, "BOARD3D_FAILED %s" % failure)
	return true


## Every kind of target at once, in the pitches and slot sizes the camera allows.
func _pick_failure() -> String:
	for message in [_fixtures["setup"], _fixtures["middle"], _every_target_message()]:
		for slot in SLOT_SIZES:
			var board := _bound_board(message, slot)[0] as Board3D
			for pitch in PITCHES:
				board.camera_rig.tilt_by(pitch - board.camera_rig.pitch)
				var failure := _round_trip_failure(board)
				if not failure.is_empty():
					return "pitch %d slot %s: %s" % [pitch, slot, failure]
	return ""


func _round_trip_failure(board: Board3D) -> String:
	if board.targets().is_empty():
		return "no targets"
	for target in board.targets():
		var picked := board.target_at(board.camera_rig.project(Picking.surface_point(target.point)))
		if picked != target:
			return "target %s picked %s" % [target.action.to_dict(), "nothing" if picked == null else picked.action.to_dict()]
	return ""


## The middle fixture with every legal board action kind at distinct spots: all targets are legal at once.
func _every_target_message() -> Dictionary:
	var message: Dictionary = (_fixtures["middle"] as Dictionary).duplicate(true)
	var board: Dictionary = message["view"]["board"]
	var actions: Array = []
	for edge in board["edges"].size():
		actions.append({"type": "BuildRoad" if edge % 2 == 0 else "PlaceRoad", "edge": edge})
	for corner in board["buildings"].size():
		var building: Variant = board["buildings"][corner]
		if building == null:
			actions.append({"type": "BuildSettlement" if corner % 2 == 0 else "PlaceSettlement", "corner": corner})
		elif building["kind"] == "Settlement":
			actions.append({"type": "BuildCity", "corner": corner})
	for tile in board["tiles"].size():
		actions.append({"type": "MoveRobber", "tile": tile})
	message["legal_actions"] = actions
	return message


func _framing_failure() -> String:
	for slot in SLOT_SIZES:
		var board := _bound_board(_fixtures["middle"], slot)[0] as Board3D
		var rig := board.camera_rig
		if not rig.is_fitted():
			return "the island does not fit the slot %s" % slot
		var window := Rect2(Vector2.ZERO, slot)
		for corner in board.geometry.corner_points:
			for height in [0.0, PlaceholderArt.PIECE_HEIGHT]:
				var pixel := rig.project(Vector3(corner.x, height, corner.y))
				if not window.has_point(pixel):
					return "corner %s at height %s is at %s outside slot %s" % [corner, height, pixel, slot]
		var failure := _projection_failure(board)
		if not failure.is_empty():
			return failure
	return ""


## The rig's projection against the engine's.
func _projection_failure(board: Board3D) -> String:
	var point := Vector3(1.0, 0.0, 2.0)
	var expected := board.camera_rig.camera.unproject_position(point)
	var actual := board.camera_rig.project(point)
	if expected.distance_to(actual) > 1.5:
		return "rig projects %s but the camera %s" % [actual, expected]
	return ""


func _filter_failure() -> String:
	var board := _bound_board(_every_target_message(), SLOT_SIZES[0])[0] as Board3D
	board.set_target_filter([SiActionBuildRoad])
	var expected := board.player.legal_of(SiActionBuildRoad).size()
	if expected == 0 or board.targets().size() != expected:
		return "road filter shows %d targets, %d legal roads" % [board.targets().size(), expected]
	for target in board.targets():
		if target.kind != BoardTarget.Kind.EDGE:
			return "road filter shows a target of kind %d" % target.kind
	if board.markers.ring_count() != expected:
		return "road filter draws %d rings for %d targets" % [board.markers.ring_count(), expected]
	return ""


func _sync_failure() -> String:
	var board := _bound_board(_fixtures["middle"], SLOT_SIZES[0])[0] as Board3D
	var view := board.player.shown_view.board
	var roads := view.roads.filter(func(seat: Variant) -> bool: return seat != null).size()
	var buildings := view.buildings.filter(func(building: SiBuilding) -> bool: return building != null).size()
	var expected := roads + buildings + 1
	if board.scene.piece_count() != expected:
		return "%d pieces for %d roads, buildings and the robber" % [board.scene.piece_count(), expected]
	var nodes := _count_nodes(board)
	board.player.committed.emit()
	board.player.committed.emit()
	if board.scene.piece_count() != expected or _count_nodes(board) != nodes:
		return "committing the same view again changed %d nodes to %d" % [nodes, _count_nodes(board)]
	return ""


func _count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_nodes(child)
	return total


func _drag_failure() -> String:
	var bound := _bound_board(_fixtures["setup"], SLOT_SIZES[0])
	var board := bound[0] as Board3D
	var client := bound[1] as SiRecordingClient
	var target := board.targets()[0]
	var point := board.camera_rig.project(Picking.surface_point(target.point))
	var before := board.camera_rig.yaw
	_mouse_button(board, MOUSE_BUTTON_RIGHT, true, point)
	_drag(board, Vector2(40.0, 0.0))
	_mouse_button(board, MOUSE_BUTTON_RIGHT, false, point)
	if is_equal_approx(board.camera_rig.yaw, before):
		return "a right drag did not orbit"
	if not client.sent.is_empty():
		return "a camera drag sent %s" % client.sent[0].to_dict()
	var moved := board.camera_rig.project(Picking.surface_point(target.point))
	_mouse_button(board, MOUSE_BUTTON_LEFT, true, moved)
	if client.sent.size() != 1 or client.sent[0] != target.action:
		return "a left click on the target sent %d actions" % client.sent.size()
	return ""


func _drag(board: Board3D, relative: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = relative
	motion.position = board.size / 2.0
	board._gui_input(motion)


func _mouse_button(board: Board3D, index: MouseButton, pressed: bool, point: Vector2) -> void:
	var button := InputEventMouseButton.new()
	button.button_index = index
	button.pressed = pressed
	button.position = point
	board._gui_input(button)


## A board of `slot` size bound to a state fed from one `GameStarted` message; returns [board, client].
func _bound_board(message: Dictionary, slot: Vector2) -> Array:
	var started := SiServerMessage.from_dict(message) as SiServerMessageGameStarted
	for previous in _boards:
		previous.visible = false
	var client := SiRecordingClient.new()
	var state := GameState.new(client, started)
	var board := Board3D.new()
	_boards.append(board)
	_clients.append(client)
	root.add_child(board)
	board.size = slot
	var player := EventPlayer.new()
	board.add_child(player)
	player.bind(state)
	board.bind(player)
	return [board, client]
