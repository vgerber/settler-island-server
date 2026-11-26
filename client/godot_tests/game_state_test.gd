extends SceneTree
## Runs inside a copy of the game project (client/godot): an act the server drops for its message rate
## (an error without request id) must give the seat its legal actions back instead of freezing it.
## Usage: godot --headless --path <copy of client/godot> -s game_state_test.gd -- <fixture.json>
## The fixture is a GameStarted message plus `rate_limited`, the server's rate limit error, both written by Rust.

## Records sent actions instead of writing to a socket.
class RecordingClient:
	extends SiClient
	var sent: Array[SiAction] = []

	func send_act(action: SiAction) -> int:
		sent.append(action)
		return sent.size()


func _init() -> void:
	var text := FileAccess.get_file_as_string(SiTestSupport.argument(0))
	var fixture: Dictionary = JSON.parse_string(text)
	var started := SiServerMessage.from_dict(fixture) as SiServerMessageGameStarted
	var client := RecordingClient.new()
	var state := GameState.new(client, started)
	var failure := _check(state, client, SiServerMessage.from_dict(fixture["rate_limited"]))
	state.release()
	client.free()
	if not failure.is_empty():
		SiTestSupport.finish(self, 1, "GAME_STATE_FAILED %s" % failure)
		return
	SiTestSupport.finish(self, 0, "GAME_STATE_OK")


func _check(state: GameState, client: RecordingClient, rate_limited: SiServerMessage) -> String:
	var legal := state.legal_actions.duplicate()
	if legal.is_empty():
		return "the fixture has no legal action"
	state.act(legal[0])
	if client.sent.size() != 1 or not state.legal_actions.is_empty():
		return "act did not send exactly once and wait"
	client.error_received.emit(rate_limited)
	if state.legal_actions != legal:
		return "after a rate-limited act the legal actions are %d instead of %d" % [state.legal_actions.size(), legal.size()]
	state.act(legal[0])
	if client.sent.size() != 2:
		return "the action could not be sent again"
	return ""
