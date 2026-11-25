extends SceneTree
## Runs inside a copy of the game project: a `GameStarted` in a discard phase (from a real game)
## opens the HUD's discard dialog; it refuses to send an incomplete choice, caps picks at the hand and
## the owed count, and sends exactly the legal `Discard` that matches the picked cards.
## Usage: godot --headless --path <copy of client/godot> -s hud_discard.gd -- <fixture.json>

var _failures: PackedStringArray = []


func _init() -> void:
	var arguments := OS.get_cmdline_user_args()
	var text := FileAccess.get_file_as_string(arguments[0]) if not arguments.is_empty() else ""
	var started := SiServerMessage.from_dict(JSON.parse_string(text)) as SiServerMessageGameStarted
	if started == null:
		_finish(["no GameStarted fixture"])
		return
	_check(started)
	_finish(_failures)


func _check(started: SiServerMessageGameStarted) -> void:
	var client := SiClient.new()
	var state := GameState.new(client, started)
	var hud := Hud.new()
	root.add_child(hud)
	hud.bind(state)
	var dialog := hud.get("_discard_dialog") as HudDiscardDialog
	var legal := state.legal_of(SiActionDiscard)
	var hand := state.view.own.hand
	_expect(not legal.is_empty(), "the fixture has legal discards")
	_expect(dialog.visible, "the discard dialog opens by itself")
	var sent: Array[SiAction] = []
	dialog.chosen.connect(func(action: SiAction) -> void: sent.append(action))

	var target := (legal[legal.size() - 1] as SiActionDiscard).resources
	var required := HudText.total(target)
	_pick(dialog, target, required - 1)
	dialog.confirm()
	_expect(sent.is_empty(), "an incomplete choice is not sent")
	for index in SiResource.VALUES.size():
		# Taken, such a card would fill the count with a choice no legal discard has.
		if hand[index] == 0:
			dialog.add(index)
	_pick_rest(dialog, target)
	_expect(dialog.matching() != null, "cards not in hand cannot be picked")
	for index in SiResource.VALUES.size():
		dialog.add(index)
	_expect(dialog.matching() != null, "extra picks are refused once the count is reached")
	dialog.confirm()

	_expect(sent.size() == 1, "exactly one discard is sent")
	if sent.size() == 1:
		_expect(legal.has(sent[0]), "the sent discard is one of the legal action objects")
		_expect((sent[0] as SiActionDiscard).resources == target, "the sent discard holds the picked cards")
	_expect(state.legal_actions.is_empty(), "GameState accepted the discard as legal")
	print("discarded %s of hand %s" % [str(target), str(hand)])
	state.release()
	hud.free()
	client.free()


## Adds `limit` cards of `target` in resource order.
func _pick(dialog: HudDiscardDialog, target: Array[int], limit: int) -> void:
	var picked := 0
	for index in target.size():
		for _count in target[index]:
			if picked == limit:
				return
			dialog.add(index)
			picked += 1


## Completes `target` after `_pick` stopped one card short: the last card it skipped.
func _pick_rest(dialog: HudDiscardDialog, target: Array[int]) -> void:
	for index in range(target.size() - 1, -1, -1):
		if target[index] > 0:
			dialog.add(index)
			return


func _expect(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)


func _finish(failures: PackedStringArray) -> void:
	if failures.is_empty():
		print("HUD_DISCARD_OK")
		quit(0)
		return
	print("HUD_DISCARD_FAILED %s" % ", ".join(failures))
	quit(1)
