extends SceneTree
## Runs the real main scene of a copy of the game project (client/godot) and plays a whole game against
## three bots through mouse clicks only (plus typing the server and name): connect screen, lobby
## browser (4 seats, 6 points), lobby room (three bots added by button), then every step clicks an
## enabled visible HUD button, dialog control or highlighted board target, chosen with a seeded RNG.
## It never calls `GameState.act` or `Net`; it only reads them to know when it is stuck.
## Fails on a dead end (legal actions for the own seat but nothing to click), a click that does not
## reach its control, a button off screen, or a game that does not finish in time.
## Usage: godot --headless --path <copy of client/godot> -s ui_game.gd -- http://127.0.0.1:<port>

const TIMEOUT_MILLISECONDS := 100000
## Below the server's 20 messages per second, as a quick player would click.
const STEP_MILLISECONDS := 80
const DEAD_END_MILLISECONDS := 3000
const MAX_CLICKS_WITHOUT_EVENTS := 150
const POINTS_TO_WIN := 6
## With the server seed of godot.rs this game reaches a discard, a knight, the steal picker and trades.
const SEED := 1

enum Stage { CONNECT, BROWSER, ROOM, GAME, LEAVING, DONE }

var _server_http := ""
var _deadline := 0
var _next_step := 0
var _main: Control = null
var _stage := Stage.CONNECT
var _random := RandomNumberGenerator.new()
var _bots_requested := 0
var _start_requested := false
var _bound_state: GameState = null
var _nothing_to_click_since := -1
var _clicks_without_events := 0
var _offered_on_turn := -1
var _used := {}
## The last clicks, printed when the test fails.
var _recent: PackedStringArray = []


func _init() -> void:
	_random.seed = SEED
	_server_http = SiTestSupport.argument(0)
	if _server_http.is_empty():
		_finish(1, "UI_GAME_FAILED missing server url")
		return
	_deadline = SiTestSupport.deadline_in(TIMEOUT_MILLISECONDS)


func _process(_delta: float) -> bool:
	if _stage == Stage.DONE:
		return true
	if SiTestSupport.expired(_deadline):
		_finish(1, "UI_GAME_FAILED timed out in stage %s %s" % [Stage.keys()[_stage], _describe_state()])
		return false
	if _main == null:
		# A headless window is 64x64 px; clicks outside it never reach a control.
		root.size = Vector2i(1600, 900)
		_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
		root.add_child(_main)
		root.get_node("Net").get("client").error_received.connect(_on_server_error)
		return false
	if Time.get_ticks_msec() < _next_step:
		return false
	_next_step = Time.get_ticks_msec() + STEP_MILLISECONDS
	match _stage:
		Stage.CONNECT:
			_step_connect()
		Stage.BROWSER:
			_step_browser()
		Stage.ROOM:
			_step_room()
		Stage.GAME:
			_step_game()
		Stage.LEAVING:
			_step_leaving()
	return false


func _finish(code: int, line: String) -> void:
	if _stage == Stage.DONE:
		return
	_stage = Stage.DONE
	if code != 0:
		print("last clicks: %s" % " | ".join(_recent))
		for node in root.find_children("*", "Button", true, false):
			var button := node as Button
			if button.is_visible_in_tree():
				print("  shown: '%s' at %s%s" % [button.text, _centre(button), " disabled" if button.disabled else ""])
	if _main != null:
		root.get_node("Net").call("stop")
		_main.queue_free()
	SiTestSupport.finish(self, code, line)


func _screen() -> Node:
	var parent := _main.get_node("%Screen")
	return parent.get_child(0) if parent.get_child_count() > 0 else null


## Screens are matched by name: their scripts use the `Net` autoload, unknown while this script compiles.
func _is_screen(scene_name: String) -> bool:
	var screen := _screen()
	return screen != null and screen.name == scene_name


func _named(name: String) -> Control:
	return _screen().find_child(name, true, false) as Control


func _step_connect() -> void:
	if not _is_screen("ConnectScreen"):
		return
	_type_into(_named("ServerEdit") as LineEdit, _server_http)
	_type_into(_named("NameEdit") as LineEdit, "Mouse")
	_click_button(_named("ConnectButton") as Button)
	_stage = Stage.BROWSER


func _step_browser() -> void:
	if not _is_screen("LobbyBrowserScreen"):
		return
	var points := _named("PointsSpin") as SpinBox
	# The lower half of the arrow column at the right edge steps the value down.
	var down_arrow := points.get_global_transform_with_canvas() * Vector2(points.size.x - 6.0, points.size.y * 0.75)
	for click in 10:
		if points.value <= POINTS_TO_WIN:
			break
		_click_at(down_arrow)
	if int(points.value) != POINTS_TO_WIN:
		_finish(1, "UI_GAME_FAILED points to win stayed at %d" % int(points.value))
		return
	_click_button(_named("CreateButton") as Button)
	_stage = Stage.ROOM


func _step_room() -> void:
	if _is_screen("GameScreen"):
		_stage = Stage.GAME
		return
	if not _is_screen("LobbyRoomScreen"):
		return
	var bots := 0
	for row in _named("SeatRows").get_children():
		bots += 1 if ((row as HBoxContainer).get_child(0) as Label).text.contains("Bot") else 0
	# One click per bot the server has confirmed, so a slow reply never adds a fourth.
	var add_bot := _named("AddBotButton") as Button
	if bots == _bots_requested and not add_bot.disabled:
		_bots_requested += 1
		_click_button(add_bot)
		return
	var start := _named("StartButton") as Button
	if bots == 3 and not start.disabled and not _start_requested:
		_start_requested = true
		_click_button(start)


func _step_game() -> void:
	if not _is_screen("GameScreen"):
		_finish(1, "UI_GAME_FAILED left the game screen for %s" % _screen())
		return
	var screen := _screen() as Control
	var state := screen.get("state") as GameState
	if state == null:
		return
	if state != _bound_state:
		_bound_state = state
		state.changed.connect(_on_changed)
	var hud := screen.get_node("%Hud") as Hud
	var game_over := _first_of(hud, HudGameOver) as HudGameOver
	if state.is_finished():
		_leave(game_over)
		return
	var candidates := _candidates(screen, hud)
	if candidates.is_empty():
		_check_dead_end(state)
		return
	_nothing_to_click_since = -1
	if not state.legal_actions.is_empty():
		_clicks_without_events += 1
	if _clicks_without_events > MAX_CLICKS_WITHOUT_EVENTS:
		_finish(1, "UI_GAME_FAILED %d clicks without any game event %s" % [_clicks_without_events, _describe_state()])
		return
	_click_candidate(_pick(candidates, state))


func _on_changed(events: Array[SiEvent]) -> void:
	if not events.is_empty():
		_clicks_without_events = 0


func _check_dead_end(state: GameState) -> void:
	if state.legal_actions.is_empty():
		_nothing_to_click_since = -1
		return
	var now := Time.get_ticks_msec()
	if _nothing_to_click_since < 0:
		_nothing_to_click_since = now
		return
	if now - _nothing_to_click_since > DEAD_END_MILLISECONDS:
		_finish(1, "UI_GAME_FAILED dead end: nothing to click %s" % _describe_state())


func _describe_state() -> String:
	if _main == null or not _is_screen("GameScreen") or _screen().get("state") == null:
		return ""
	var state := _screen().get("state") as GameState
	var types: PackedStringArray = []
	for action in state.legal_actions:
		var type := str(action.to_dict().get("type", "?"))
		if not types.has(type):
			types.append(type)
	return "(phase %s, legal %s)" % [JSON.stringify(state.view.phase.to_dict()), ", ".join(types)]


func _leave(game_over: HudGameOver) -> void:
	if game_over == null or not game_over.visible:
		_finish(1, "UI_GAME_FAILED the game is over but no result overlay shows")
		return
	var back := _buttons_in(game_over).filter(func(button: Button) -> bool: return button.text == "Back to lobbies")
	if back.is_empty():
		_finish(1, "UI_GAME_FAILED the result overlay has no way back")
		return
	_click_button(back[0])
	_stage = Stage.LEAVING


func _step_leaving() -> void:
	if not _is_screen("LobbyBrowserScreen"):
		return
	var used := _used.keys()
	used.sort()
	_finish(0, "UI_GAME_OK used %s" % ", ".join(used))


## `{button: Button}` or `{target: Dictionary}` entries the player could click right now.
func _candidates(screen: Control, hud: Hud) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var dialog := _open_dialog(hud)
	var scope: Node = dialog if dialog != null else hud
	for button in _buttons_in(scope):
		if dialog == null and _inside_dialog(button):
			continue
		candidates.append({"button": button})
	if dialog != null:
		return candidates
	var board := screen.get_node("%Board") as Board
	for target: Dictionary in board.get("_targets"):
		candidates.append({"target": target, "board": board})
	return candidates


func _open_dialog(hud: Hud) -> HudDialog:
	for node in hud.find_children("*", "", true, false):
		if node is HudDialog and (node as HudDialog).is_visible_in_tree():
			return node as HudDialog
	return null


func _inside_dialog(node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null:
		if parent is HudDialog or parent is HudGameOver:
			return true
		parent = parent.get_parent()
	return false


func _first_of(parent: Node, script: Script) -> Node:
	for node in parent.find_children("*", "", true, false):
		if node.get_script() == script:
			return node
	return null


## Enabled buttons shown on screen; one shown outside the window fails the test, a player could not reach it.
func _buttons_in(scope: Node) -> Array[Button]:
	var found: Array[Button] = []
	var window := Rect2(Vector2.ZERO, Vector2(root.size))
	for node in scope.find_children("*", "Button", true, false):
		var button := node as Button
		if not button.is_visible_in_tree() or button.disabled:
			continue
		if not window.has_point(_centre(button)):
			_finish(1, "UI_GAME_FAILED button '%s' is outside the window at %s" % [button.text, _centre(button)])
			return []
		found.append(button)
	return found


## Weighted choice: board targets and dialog progress first, ending the turn last, one offer per turn.
func _pick(candidates: Array[Dictionary], state: GameState) -> Dictionary:
	var weights: Array[float] = []
	for candidate in candidates:
		weights.append(_weight(candidate, state))
	var total := 0.0
	for weight in weights:
		total += weight
	var roll := _random.randf() * total
	for index in candidates.size():
		roll -= weights[index]
		if roll <= 0.0:
			return candidates[index]
	return candidates[candidates.size() - 1]


func _weight(candidate: Dictionary, state: GameState) -> float:
	if candidate.has("target"):
		return 6.0
	var button := candidate["button"] as Button
	if _inside_dialog(button):
		return _dialog_weight(button)
	match button.text:
		"End turn":
			return 1.0
		"Offer trade...":
			return 0.0 if _offered_on_turn == state.view.turn_number else 1.0
		"Show result", "Back to lobbies":
			return 0.0
	# Development cards are rare; buying and playing them often reaches their pickers in a short game.
	if button.text.begins_with("Play") or button.text in ["Buy development card", "Year of plenty...", "Monopoly..."]:
		return 8.0
	return 3.0


## The dialog's confirm button as soon as it is enabled; cancel and "-" rarely, so every dialog completes.
## In the trade builder grid (name, give -, count, give +, get -, count, get +) giving comes before asking,
## since a resource asked for can no longer be given. Option buttons open popups and are left alone.
func _dialog_weight(button: Button) -> float:
	if button is OptionButton:
		return 0.0
	if button.get_parent() is GridContainer and button.get_index() % 7 == 6:
		return 0.5
	match button.text:
		"Discard", "Confirm", "Offer":
			return 1000.0
		"Cancel":
			return 0.1
		"-":
			return 0.3
	return 3.0


func _click_candidate(candidate: Dictionary) -> void:
	if candidate.has("target"):
		_click_target(candidate["board"], candidate["target"])
		return
	var button := candidate["button"] as Button
	_note_use(button)
	_click_button(button)


func _note_use(button: Button) -> void:
	var dialog := button.get_parent()
	while dialog != null and not dialog is HudDialog and not dialog is HudTradePanel:
		dialog = dialog.get_parent()
	var kind := button.text
	if dialog is HudDiscardDialog:
		kind = "discard dialog"
	elif dialog is HudActionList:
		kind = "steal picker"
	elif dialog is HudTradeBuilder:
		kind = "trade builder"
	elif dialog is HudResourcePicker:
		kind = "resource picker"
	elif dialog is HudTradePanel:
		kind = "trade answer " + button.text.get_slice(" ", 0)
	if button.text == "Offer trade...":
		_offered_on_turn = (_screen().get("state") as GameState).view.turn_number
	_used[kind] = true


func _click_target(board: Board, target: Dictionary) -> void:
	var state := board.state
	var point := board.get_global_transform_with_canvas() * board.to_pixels(target["point"])
	_used["board " + str((target["action"] as SiAction).to_dict()["type"])] = true
	_click_at(point)
	if not state.legal_actions.is_empty():
		_finish(1, "UI_GAME_FAILED clicking the highlighted target at %s sent nothing %s" % [point, _describe_state()])


func _click_button(button: Button) -> void:
	var pressed := [false]
	var on_pressed := func() -> void: pressed[0] = true
	button.pressed.connect(on_pressed)
	_click_at(_centre(button))
	if is_instance_valid(button) and button.pressed.is_connected(on_pressed):
		button.pressed.disconnect(on_pressed)
	if not pressed[0]:
		_finish(1, "UI_GAME_FAILED clicking '%s' at %s did not press it %s" % [button.text, _centre(button), _describe_state()])


func _centre(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size / 2.0)


## Moves the mouse there, then presses and releases the left button, through the viewport.
func _click_at(point: Vector2) -> void:
	_recent.append("%s %s" % [point, _hovered_text(point)])
	if _recent.size() > 15:
		_recent.remove_at(0)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	for is_pressed in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = is_pressed
		button.position = point
		button.global_position = point
		root.push_input(button)


func _hovered_text(point: Vector2) -> String:
	for node in root.find_children("*", "Button", true, false):
		var button := node as Button
		if button.is_visible_in_tree() and button.get_global_rect().has_point(point):
			return "'%s'" % button.text
	return ""


## Clicks into the field, selects what is there and types over it.
func _type_into(edit: LineEdit, text: String) -> void:
	_click_at(_centre(edit))
	_press_key(KEY_A, true)
	for character in text:
		var key := InputEventKey.new()
		key.unicode = character.unicode_at(0)
		key.pressed = true
		root.push_input(key)
		key = key.duplicate() as InputEventKey
		key.pressed = false
		root.push_input(key)
	if edit.text != text:
		_finish(1, "UI_GAME_FAILED typing '%s' left '%s'" % [text, edit.text])


func _press_key(keycode: Key, control: bool = false) -> void:
	for is_pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.ctrl_pressed = control
		key.pressed = is_pressed
		root.push_input(key)


func _on_server_error(message: SiServerMessageError) -> void:
	print("server error: %s" % message.message)
