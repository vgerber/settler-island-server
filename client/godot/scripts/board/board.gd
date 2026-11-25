class_name Board
extends Control
## The island: tiles, buildings and click targets from the legal actions (step 2 of
## doc/plans/godot-client.md). Reads only its `GameState`, never `Net`.

var state: GameState = null


func bind(game_state: GameState) -> void:
	state = game_state
