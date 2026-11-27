extends SceneTree
## Runs inside a copy of the game project (client/godot): feeds `Board` the `GameStarted` fixtures written
## by godot.rs, checks that every tile listing a corner puts it on the same pixel, and that clicking a
## legal target sends exactly that action (a settlement corner in setup, a robber tile mid-game).
## Usage: godot --headless --path <copy of client/godot> -s board_test.gd -- <fixtures.json>

## Records sent actions instead of writing to a socket.
class RecordingClient:
	extends SiClient
	var sent: Array[SiAction] = []

	func send_act(action: SiAction) -> int:
		sent.append(action)
		return sent.size()


const TOLERANCE_PIXELS := 0.5

var _fixtures: Dictionary = {}
var _started := false
## Everything `_bound_board` made, freed before quitting so nothing leaks.
var _boards: Array[Board] = []
var _clients: Array[RecordingClient] = []


func _init() -> void:
	var text := FileAccess.get_file_as_string(SiTestSupport.argument(0))
	_fixtures = JSON.parse_string(text) if not text.is_empty() else {}


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	# A headless window is 64x64 px; clicks outside it never reach the board.
	root.size = Vector2i(1600, 900)
	if _fixtures.is_empty():
		return _fail("missing fixtures")
	var failure := _check_setup()
	if failure.is_empty():
		failure = _check_middle()
	if not failure.is_empty():
		return _fail(failure)
	_release()
	SiTestSupport.finish(self, 0, "BOARD_OK")
	return true


func _fail(reason: String) -> bool:
	_release()
	SiTestSupport.finish(self, 1, "BOARD_FAILED %s" % reason)
	return true


func _release() -> void:
	for board in _boards:
		board.player.release()
		board.free()
	for client in _clients:
		client.free()


func _check_setup() -> String:
	var setup := _bound_board("setup")
	var board: Board = setup[0]
	var client: RecordingClient = setup[1]
	var failure := _corner_failure(board) + _port_failure(board)
	if not failure.is_empty():
		return "setup: " + failure
	var settlements := board.player.legal_of(SiActionPlaceSettlement)
	if settlements.is_empty():
		return "setup has no PlaceSettlement"
	# A tile centre is no target in the setup phase.
	_click(board, board.to_pixels(BoardGeometry.tile_center(board.player.shown_view.board.tiles[0].coordinates)))
	if not client.sent.is_empty():
		return "a click beside every target sent %s" % client.sent[0].to_dict()
	var wanted := settlements[settlements.size() / 2] as SiActionPlaceSettlement
	_click(board, board.corner_position(wanted.corner))
	if client.sent.size() != 1 or client.sent[0] != wanted:
		return "clicking corner %d sent %s" % [wanted.corner, client.sent.map(func(action: SiAction) -> Dictionary: return action.to_dict())]
	return ""


func _check_middle() -> String:
	var middle := _bound_board("middle")
	var board: Board = middle[0]
	var client: RecordingClient = middle[1]
	var failure := _corner_failure(board)
	if not failure.is_empty():
		return "middle: " + failure
	var robber_moves := board.player.legal_of(SiActionMoveRobber)
	if robber_moves.is_empty():
		return "middle has no MoveRobber"
	var wanted := robber_moves[robber_moves.size() - 1] as SiActionMoveRobber
	var tile := board.player.shown_view.board.tiles[wanted.tile]
	_click(board, board.to_pixels(BoardGeometry.tile_center(tile.coordinates)))
	if client.sent.size() != 1 or client.sent[0] != wanted:
		return "clicking tile %d sent %d actions" % [wanted.tile, client.sent.size()]
	return ""


## A board in a 1220x644 rect (the window minus the HUD) bound to a state fed from one fixture.
func _bound_board(key: String) -> Array:
	var started := SiServerMessage.from_dict(_fixtures[key]) as SiServerMessageGameStarted
	for previous in _boards:
		previous.visible = false
	var client := RecordingClient.new()
	var state := GameState.new(client, started)
	var board := Board.new()
	_boards.append(board)
	_clients.append(client)
	root.add_child(board)
	board.position = Vector2(0.0, 56.0)
	board.size = Vector2(1220.0, 644.0)
	var player := EventPlayer.new()
	board.add_child(player)
	player.bind(state)
	board.bind(player)
	return [board, client]


## Nine ports (4 generic, one per resource), each on its own spot in the sea.
func _port_failure(board: Board) -> String:
	var ports := board.geometry.ports
	if ports.size() != 9:
		return "%d ports instead of 9" % ports.size()
	for index in ports.size():
		for other in range(index + 1, ports.size()):
			var distance: float = (ports[index]["marker"] as Vector2).distance_to(ports[other]["marker"])
			if distance < BoardGeometry.PORT_RADIUS * 2.0:
				return "ports %d and %d overlap" % [index, other]
	return ""


func _corner_failure(board: Board) -> String:
	var tiles := board.player.shown_view.board.tiles
	for tile_index in tiles.size():
		for index in 6:
			var corner := tiles[tile_index].corners[index]
			var distance := board.tile_corner_position(tile_index, index).distance_to(board.corner_position(corner))
			if distance > TOLERANCE_PIXELS:
				return "tile %d corner %d (id %d) is %.2f px off" % [tile_index, index, corner, distance]
	return ""


## Presses and releases the left button at a point of the board, through the viewport like a mouse.
func _click(board: Board, point: Vector2) -> void:
	var global_point := board.get_global_transform_with_canvas() * point
	var motion := InputEventMouseMotion.new()
	motion.position = global_point
	motion.global_position = global_point
	root.push_input(motion)
	for pressed in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		button.position = global_point
		button.global_position = global_point
		root.push_input(button)
