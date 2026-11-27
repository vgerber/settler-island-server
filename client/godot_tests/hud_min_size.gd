extends SceneTree
## Runs inside a copy of the game project: in the states the game screen is judged on (own turn with every
## development card held, a discard, a trade offer), at 1600x900 and 1280x720, the HUD's combined minimum
## size fits the window (in the stretched 1600x900 units the project draws in), so no state pushes the right column or the action buttons off screen.
## Usage: godot --headless --path <copy of client/godot> -s hud_min_size.gd -- <board fixtures.json>

const WINDOWS: Array[Vector2i] = [Vector2i(1600, 900), Vector2i(1280, 720)]

var _failures: PackedStringArray = []
var _fixtures: Dictionary = {}


func _initialize() -> void:
	_fixtures = JSON.parse_string(FileAccess.get_file_as_string(SiTestSupport.argument(0)))
	for window in WINDOWS:
		for state: String in ["setup", "dev_cards", "all_dev_cards", "discard", "trade"]:
			await _check(window, state)
	var passed := _failures.is_empty()
	SiTestSupport.finish(self, 0 if passed else 1, "HUD_MIN_SIZE_OK" if passed else "HUD_MIN_SIZE_FAILED " + "; ".join(_failures))


func _check(window: Vector2i, state: String) -> void:
	root.size = window
	var started := SiServerMessage.from_dict(_message(state)) as SiServerMessageGameStarted
	var client := SiClient.new()
	var game_state := GameState.new(client, started)
	var hud := Hud.new()
	root.add_child(hud)
	var player := EventPlayer.new()
	hud.add_child(player)
	player.bind(game_state)
	hud.bind(player)
	await process_frame
	await process_frame
	var needed := (hud.get_child(0) as Control).get_combined_minimum_size()
	var viewport := Vector2(window) / minf(window.x / 1600.0, window.y / 900.0)
	if needed.x > viewport.x or needed.y > viewport.y:
		_failures.append("%s at %s needs %s" % [state, window, needed])
	game_state.release()
	hud.free()
	client.free()


## The same edits as tools/game_screenshots.gd makes for its states.
func _message(state: String) -> Dictionary:
	var key := "setup" if state == "setup" else "middle"
	var message: Dictionary = (_fixtures[key] as Dictionary).duplicate(true)
	message["type"] = "GameStarted"
	if state == "setup":
		return message
	var view: Dictionary = message["view"]
	var own: int = message["seat"]
	view["current"] = own
	view["phase"] = {"type": "Main"}
	message["legal_actions"] = [{"type": "EndTurn"}, {"type": "BuyDevelopmentCard"}, {"type": "PlayKnight"}]
	view["own"]["development_cards"] = ["Knight", "Knight", "VictoryPoint"]
	view["own"]["new_development_cards"] = ["Monopoly"]
	if state == "all_dev_cards":
		view["own"]["development_cards"] = ["Knight", "RoadBuilding", "YearOfPlenty", "VictoryPoint"]
	if state == "discard":
		view["phase"] = {"type": "Discard", "owed": [{"seat": own, "cards": 4}, {"seat": 1, "cards": 3}]}
		view["current"] = 0
		view["own"]["hand"] = [3, 2, 1, 1, 1]
		message["legal_actions"] = [{"type": "Discard", "resources": [1, 1, 1, 1, 0]}]
	if state == "trade":
		view["phase"] = {"type": "TradeOffered", "offer": {"offerer": 1, "give": [0, 2, 0, 0, 0], "receive": [0, 0, 0, 1, 0], "answers": [[2, false]], "addressed": null}}
		view["current"] = 1
		message["legal_actions"] = [{"type": "AcceptTrade"}, {"type": "RejectTrade"}]
	return message

