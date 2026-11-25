extends SceneTree
## Renders the game screen for each `GameStarted` message of a fixture file (the board fixtures that
## settler_island_client_generator/tests/godot.rs writes to target/tmp/godot-board-fixtures.json) and
## saves `board_<key>.png`, with the mouse over one legal target. Needs a window; quits by itself.
## Usage: godot --path client/godot -s tools/board_screenshot.gd -- <fixtures.json> <output directory>

const SETTLE_FRAMES := 10

var _fixtures: Dictionary = {}
var _keys: Array = []
var _output_directory := ""
## The game screen, untyped: `GameScreen` uses the `Net` autoload, which a -s script cannot name.
var _screen: Control = null
var _frames_left := -1


func _init() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() < 2:
		push_error("usage: -s tools/board_screenshot.gd -- <fixtures.json> <output directory>")
		quit(1)
		return
	_fixtures = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	_keys = _fixtures.keys()
	_output_directory = arguments[1]


func _process(_delta: float) -> bool:
	if _frames_left > 0:
		_frames_left -= 1
		return false
	if _frames_left == 0:
		_save()
	if _keys.is_empty():
		quit(0)
		return true
	_show(_keys.pop_front())
	return false


func _show(key: String) -> void:
	if _screen != null:
		_screen.free()
	_screen = (load("res://scenes/game.tscn") as PackedScene).instantiate() as Control
	_screen.name = key
	root.add_child(_screen)
	_screen.call("begin", SiServerMessage.from_dict(_fixtures[key]) as SiServerMessageGameStarted)
	_frames_left = SETTLE_FRAMES
	_hover_first_target()


func _hover_first_target() -> void:
	var board := _screen.get_node("%Board") as Board
	var point := Vector2.ZERO
	for script: Script in [SiActionPlaceSettlement, SiActionBuildCity, SiActionBuildSettlement]:
		for action in board.state.legal_of(script):
			point = board.corner_position(action.get("corner"))
	for action in board.state.legal_of(SiActionMoveRobber):
		var tile := board.state.view.board.tiles[(action as SiActionMoveRobber).tile]
		point = board.to_pixels(BoardGeometry.tile_center(tile.coordinates))
	if point == Vector2.ZERO:
		return
	var motion := InputEventMouseMotion.new()
	motion.position = board.get_global_transform_with_canvas() * point
	motion.global_position = motion.position
	root.push_input(motion)


func _save() -> void:
	var path := _output_directory.path_join("board_%s.png" % _screen.name)
	var error := root.get_viewport().get_texture().get_image().save_png(path)
	print("saved %s (%d)" % [path, error])
	_frames_left = -1
