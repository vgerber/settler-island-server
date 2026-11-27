class_name HudWaiting
extends Label
## One line under the dice: whom the game waits for, with trailing dots that move. The own seat among those
## waited on gets an instruction in the accent colour instead.

const DOT_STEP_SECONDS := 0.45

var _base := ""
var _dots := 0
var _timer: Timer = null


func _init() -> void:
	theme_type_variation = &"CreamMutedLabel"
	# Two wrapped lines at most, then an ellipsis; the height is fixed so the dice never move between states.
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	max_lines_visible = 2
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	custom_minimum_size = Vector2(0.0, 54.0)
	vertical_alignment = VERTICAL_ALIGNMENT_TOP
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## `animated` false (animations off) keeps the dots still.
func show_waiting(view: SiPlayerView, names: SeatNames, animated: bool) -> void:
	_base = line(view, names)
	var own_move := _base.begins_with("Your move")
	theme_type_variation = &"CreamCountLabel" if own_move else &"CreamMutedLabel"
	if _timer == null and animated:
		_start_dots()
	_dots = 0
	_render(animated and not own_move)


## The line for a view; empty when nothing is to be said (own plain turn, finished game).
static func line(view: SiPlayerView, names: SeatNames) -> String:
	var pending := HudText.pending_seats(view)
	if pending.is_empty():
		return ""
	var own := pending.has(names.own_seat)
	if view.phase is SiPhaseDiscard:
		return _discard_line(view.phase as SiPhaseDiscard, pending, names)
	if view.phase is SiPhaseTradeOffered:
		return "Your move: answer the trade" if own else "Waiting for answers: %s" % _name_list(pending, names)
	if own:
		return "Your move: move the robber" if view.phase is SiPhaseMoveRobber else ""
	if view.phase is SiPhaseMoveRobber or view.phase is SiPhaseSteal:
		return "%s is moving the robber" % names.name_of(pending[0])
	return "%s is playing" % names.name_of(pending[0])


static func _discard_line(phase: SiPhaseDiscard, pending: Array[int], names: SeatNames) -> String:
	for owed in phase.owed:
		if owed.seat == names.own_seat and owed.cards > 0:
			return "Your move: discard %d cards" % owed.cards
	return "Waiting for %s to discard" % _name_list(pending, names)


static func _name_list(seats: Array[int], names: SeatNames) -> String:
	var listed: PackedStringArray = []
	for seat in seats:
		listed.append(names.name_of(seat))
	return ", ".join(listed)


func _start_dots() -> void:
	_timer = Timer.new()
	_timer.wait_time = DOT_STEP_SECONDS
	_timer.autostart = true
	_timer.timeout.connect(_step_dots)
	add_child(_timer)


func _step_dots() -> void:
	_dots = (_dots + 1) % 4
	_render(true)


func _render(dotted: bool) -> void:
	text = _base + ".".repeat(_dots if dotted else 0)
