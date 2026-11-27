extends SceneTree
## Renders the game screen in the five states the HUD design is judged on and saves one PNG each:
## setup placement, own Main turn with build mode armed, a 7 with discard, a player trade offer, game over.
## The states derive from the two board fixtures of settler_island_client_generator/tests/godot.rs
## (target/tmp/godot-board-fixtures.json); the view is edited, not simulated, so only the look is real.
## Needs a window. Quits by itself.
## Usage: godot --path client/godot --resolution 1600x900 --position 200,200 -s tools/game_screenshots.gd -- <fixtures.json> <output directory> [suffix]

const SETTLE_FRAMES := 12
const OWN_SEAT_NAMES := ["Mira", "Rolf", "Kai", "Lin"]

var _fixtures: Dictionary = {}
var _output_directory := ""
var _suffix := ""
var _steps: Array[Callable] = []
## The game screen, untyped: `GameScreen` uses the `Net` autoload, which a -s script cannot name.
var _screen: Control = null
var _name := ""
var _frames_left := -1
var _exit_code := 0


func _init() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() < 2:
		push_error("usage: -s tools/game_screenshots.gd -- <fixtures.json> <output directory> [suffix]")
		quit(1)
		return
	_fixtures = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	_output_directory = arguments[1]
	_suffix = arguments[2] if arguments.size() > 2 else ""
	_steps = [_setup, _build, _dev_cards, _log_popup, _discard, _trade, _game_over]


func _process(_delta: float) -> bool:
	if _frames_left > 0:
		_frames_left -= 1
		return false
	if _frames_left == 0:
		_save()
	if _steps.is_empty():
		quit(_exit_code)
		return true
	_steps.pop_front().call()
	return false


func _setup() -> void:
	_show("setup", _fixtures["setup"])
	_hover_first_target()


func _build() -> void:
	var message := _middle_message()
	var view: Dictionary = message["view"]
	view["phase"] = {"type": "Main"}
	var own: int = message["seat"]
	view["current"] = own
	view["own"]["hand"] = [2, 3, 1, 2, 2]
	view["own"]["development_cards"] = ["Knight", "Knight", "VictoryPoint"]
	view["own"]["new_development_cards"] = ["Monopoly"]
	message["legal_actions"] = _build_actions(view, own)
	message["legal_actions"].append({"type": "PlayKnight"})
	_show("build", message)
	_emit_dice(3, 5)
	_press_key(KEY_1)
	_hover_first_target()


## The development cards of the same state; in compact mode they sit behind the "Dev N" button.
func _dev_cards() -> void:
	var hud := _screen.get_node("%Hud") as Hud
	var stack := hud.find_children("*", "Button", true, false).filter(func(node: Node) -> bool: return (node as Button).text.begins_with("Dev "))
	if not stack.is_empty() and (stack[0] as Button).is_visible_in_tree():
		(stack[0] as Button).pressed.emit()
	_name = "dev_cards"
	_frames_left = SETTLE_FRAMES


## Compact mode only: the log as a popup over the side column.
func _log_popup() -> void:
	var hud := _screen.get_node("%Hud") as Hud
	var buttons := hud.find_children("*", "Button", true, false).filter(func(node: Node) -> bool: return (node as Button).text.begins_with("Log"))
	if buttons.is_empty() or not (buttons[0] as Button).is_visible_in_tree():
		return
	(buttons[0] as Button).pressed.emit()
	_name = "log_popup"
	_frames_left = SETTLE_FRAMES


func _discard() -> void:
	var message := _middle_message()
	var view: Dictionary = message["view"]
	var own: int = message["seat"]
	var hand := [3, 2, 1, 1, 1]
	view["phase"] = {"type": "Discard", "owed": [{"seat": own, "cards": 4}, {"seat": 1, "cards": 3}]}
	view["current"] = 0
	view["own"]["hand"] = hand
	view["players"][own]["resource_count"] = 8
	message["legal_actions"] = _discards(hand, 4)
	_show("discard", message)
	_emit_dice(3, 4)


func _trade() -> void:
	var message := _middle_message()
	var view: Dictionary = message["view"]
	view["phase"] = {"type": "TradeOffered", "offer": {"offerer": 1, "give": [0, 2, 0, 0, 0], "receive": [0, 0, 0, 1, 0], "answers": [[2, false]], "addressed": null}}
	view["current"] = 1
	view["own"]["hand"] = [1, 0, 2, 3, 1]
	message["legal_actions"] = [{"type": "AcceptTrade"}, {"type": "RejectTrade"}]
	_show("trade", message)
	_emit_dice(2, 5)


func _game_over() -> void:
	var message := _middle_message()
	var view: Dictionary = message["view"]
	view["phase"] = {"type": "Finished", "winner": 1}
	view["current"] = 1
	view["players"][1]["points"] = view["points_to_win"]
	view["longest_road"] = 1
	message["legal_actions"] = []
	_show("game_over", message)


func _middle_message() -> Dictionary:
	return (_fixtures["middle"] as Dictionary).duplicate(true)


## The legal actions of a Main turn: roads next to the own network, a city on every own settlement, and the always-legal rest.
func _build_actions(view: Dictionary, own: int) -> Array:
	var board: Dictionary = view["board"]
	var reachable := {}
	for corner in board["buildings"].size():
		var building: Variant = board["buildings"][corner]
		if building != null and int(building["seat"]) == own:
			reachable[corner] = true
	for edge in board["edges"].size():
		if board["roads"][edge] != null and int(board["roads"][edge]) == own:
			for corner in board["edges"][edge]["corners"]:
				reachable[int(corner)] = true
	var actions: Array = [{"type": "EndTurn"}, {"type": "BuyDevelopmentCard"}]
	for edge in board["edges"].size():
		var corners: Array = board["edges"][edge]["corners"]
		if board["roads"][edge] == null and (reachable.has(int(corners[0])) or reachable.has(int(corners[1]))):
			actions.append({"type": "BuildRoad", "edge": edge})
	for corner in board["buildings"].size():
		var building: Variant = board["buildings"][corner]
		if building != null and int(building["seat"]) == own and building["kind"] == "Settlement":
			actions.append({"type": "BuildCity", "corner": corner})
	actions.append({"type": "BankTrade", "give": "Wood", "receive": "Ore"})
	return actions


## Every way to discard `count` cards out of `hand`.
func _discards(hand: Array, count: int) -> Array:
	var actions: Array = []
	for first in range(mini(hand[0], count) + 1):
		for second in range(mini(hand[1], count - first) + 1):
			for third in range(mini(hand[2], count - first - second) + 1):
				for fourth in range(mini(hand[3], count - first - second - third) + 1):
					var fifth := count - first - second - third - fourth
					if fifth <= hand[4]:
						actions.append({"type": "Discard", "resources": [first, second, third, fourth, fifth]})
	return actions


func _show(key: String, message: Dictionary) -> void:
	if _screen != null:
		_screen.free()
	_name = key
	var net := root.get_node("Net")
	net.set("lobby", _lobby(int(message["seat"]), (message["view"]["players"] as Array).size()))
	message["type"] = "GameStarted"
	_screen = (load("res://scenes/game.tscn") as PackedScene).instantiate() as Control
	root.add_child(_screen)
	_screen.call("begin", SiServerMessage.from_dict(message) as SiServerMessageGameStarted)
	_frames_left = SETTLE_FRAMES


func _lobby(own_seat: int, seat_count: int) -> SiLobbyDetails:
	var seats: Array = []
	for seat in seat_count:
		if seat == own_seat:
			seats.append({"type": "Human", "user": {"id": "me", "name": OWN_SEAT_NAMES[seat], "kind": "Guest"}})
		else:
			seats.append({"type": "Bot", "difficulty": "Heuristic"})
	var owner := {"id": "me", "name": OWN_SEAT_NAMES[own_seat], "kind": "Guest"}
	var info := {"id": 1, "name": "Screenshots", "owner": owner, "has_password": false, "started": true, "points_to_win": 10, "bot_difficulty": "Heuristic"}
	return SiLobbyDetails.from_dict({"info": info, "seats": seats})


## Feeds a roll through the state's own signal, as an update from the server would.
func _emit_dice(first: int, second: int) -> void:
	var state := _screen.get("state") as GameState
	var event := SiEvent.from_dict({"type": "DiceRolled", "seat": 0, "first": first, "second": second})
	state.changed.emit([event] as Array[SiEvent])


func _press_key(keycode: Key) -> void:
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.pressed = pressed
		root.push_input(key)


func _hover_first_target() -> void:
	var board := _screen.get_node("%Board") as Board
	# Hover waits one frame: the board is only sized after the first layout pass.
	await process_frame
	await process_frame
	var targets := board.targets()
	if targets.is_empty():
		return
	var target := targets[targets.size() / 2]
	var motion := InputEventMouseMotion.new()
	motion.position = board.get_global_transform_with_canvas() * board.to_pixels(target.point)
	motion.global_position = motion.position
	root.push_input(motion)


func _save() -> void:
	var path := _output_directory.path_join("%s%s.png" % [_name, _suffix])
	var error := root.get_viewport().get_texture().get_image().save_png(path)
	print("saved %s (%d)" % [path, error])
	if error != OK:
		push_error("game_screenshots: saving %s failed (%d)" % [path, error])
		_exit_code = 1
	_frames_left = -1
