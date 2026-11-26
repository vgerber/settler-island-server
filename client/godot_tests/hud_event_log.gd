extends SceneTree
## Runs inside a copy of the game project: every `SiEvent` variant, built from a dict, becomes a
## non-empty log line that the log accepts. A variant missing here fails the test.
## Usage: godot --headless --path <copy of client/godot> -s hud_event_log.gd -- -

const OWN_SEAT := 1


func _init() -> void:
	var failures := _check_lines()
	if failures.is_empty():
		SiTestSupport.finish(self, 0, "HUD_EVENT_LOG_OK")
		return
	SiTestSupport.finish(self, 1, "HUD_EVENT_LOG_FAILED %s" % ", ".join(failures))


func _check_lines() -> PackedStringArray:
	var failures: PackedStringArray = []
	var covered: PackedStringArray = []
	var log := HudEventLog.new()
	for data: Dictionary in _event_dicts():
		var event := SiEvent.from_dict(data)
		var variant := str(data["type"])
		covered.append(variant)
		if event == null or event.get_script() == SiEvent:
			failures.append("%s did not decode" % variant)
			continue
		var line := HudText.event_line(event, OWN_SEAT)
		print("%s -> %s" % [variant, line])
		if line.strip_edges().is_empty() or line == variant:
			failures.append("%s has no readable line" % variant)
		log.add_events([event] as Array[SiEvent], OWN_SEAT)
	for variant in _api_variants():
		if not covered.has(variant):
			failures.append("%s has no sample here" % variant)
	log.free()
	return failures


## The variant names of the generated `SiEvent*` classes.
func _api_variants() -> PackedStringArray:
	var variants: PackedStringArray = []
	for file in DirAccess.get_files_at("res://settler_island_api"):
		if file.begins_with("SiEvent") and file.ends_with(".gd") and file != "SiEvent.gd":
			variants.append(file.trim_prefix("SiEvent").trim_suffix(".gd"))
	return variants


func _event_dicts() -> Array[Dictionary]:
	var cards := [1, 0, 2, 0, 1]
	return [
		{"type": "SettlementPlaced", "seat": 0, "corner": 4},
		{"type": "RoadPlaced", "seat": 1, "edge": 7},
		{"type": "CityBuilt", "seat": 2, "corner": 9},
		{"type": "DiceRolled", "seat": 3, "first": 3, "second": 4},
		{"type": "ResourcesProduced", "seat": 0, "resources": cards},
		{"type": "ResourcesPaid", "seat": 1, "resources": cards},
		{"type": "RobberMoved", "seat": 2, "tile": 5},
		{"type": "CardsDiscarded", "seat": 3, "resources": cards},
		{"type": "ResourceStolen", "thief": 0, "victim": 1, "resource": "Ore"},
		{"type": "ResourceStolen", "thief": 2, "victim": 3, "resource": null},
		{"type": "BankTraded", "seat": 1, "gave": [4, 0, 0, 0, 0], "received": [0, 0, 0, 0, 1]},
		{"type": "TradeOffered", "seat": 0, "give": [1, 0, 0, 0, 0], "receive": [0, 1, 0, 0, 0], "to": null},
		{"type": "TradeOffered", "seat": 0, "give": [1, 0, 0, 0, 0], "receive": [0, 1, 0, 0, 0], "to": 1},
		{"type": "TradeAnswered", "seat": 2, "accepted": true},
		{"type": "TradeCompleted", "seat": 0, "with": 2, "gave": [1, 0, 0, 0, 0], "received": [0, 1, 0, 0, 0]},
		{"type": "TradeCancelled", "seat": 0},
		{"type": "DevelopmentCardBought", "seat": 1, "card": "Monopoly"},
		{"type": "DevelopmentCardBought", "seat": 2, "card": null},
		{"type": "DevelopmentCardPlayed", "seat": 3, "card": "YearOfPlenty"},
		{"type": "MonopolyTaken", "seat": 3, "resource": "Wheat", "amount": 5},
		{"type": "YearOfPlentyTaken", "seat": 1, "resources": [0, 1, 0, 1, 0]},
		{"type": "LongestRoadChanged", "length": 6, "holder": 2},
		{"type": "LongestRoadChanged", "length": 0, "holder": null},
		{"type": "LargestArmyChanged", "knights": 3, "holder": 1},
		{"type": "LargestArmyChanged", "knights": 0, "holder": null},
		{"type": "PhaseChanged", "phase": {"type": "RoadBuilding", "roads_left": 2}},
		{"type": "TurnStarted", "seat": 2},
		{"type": "TurnEnded", "seat": 2},
		{"type": "GameWon", "seat": 1, "points": 10},
	]
