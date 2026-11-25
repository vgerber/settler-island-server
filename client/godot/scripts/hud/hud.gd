class_name Hud
extends Control
## Hand, players, dice, log and the turn buttons from the legal actions (step 3 of
## doc/plans/godot-client.md). Reads only its `GameState`, never `Net`.

var state: GameState = null


func bind(game_state: GameState) -> void:
	state = game_state
