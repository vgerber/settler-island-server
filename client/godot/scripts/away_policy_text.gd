class_name AwayPolicyText
extends RefCounted
## How the lobby screens name an `SiAwayPolicy`: what happens to the seat of a player who leaves a running game.


## The create form's choice, read after "If a player leaves".
static func choice(policy: String) -> String:
	if policy == SiAwayPolicy.WAIT_FOR_PLAYER:
		return "the game waits for them"
	return "a bot plays for them"


## A short note for the lobby list and the lobby room.
static func summary(policy: String) -> String:
	if policy == SiAwayPolicy.WAIT_FOR_PLAYER:
		return "waits for players who leave"
	return "bots replace players who leave"
