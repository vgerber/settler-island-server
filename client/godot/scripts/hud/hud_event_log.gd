class_name HudEventLog
extends RichTextLabel
## The game so far as readable lines, newest at the bottom. A line starts with the chip of its seat; text
## stays ink on parchment because seat colours as text colour are unreadable for Ivory and Charcoal.

## Older lines are dropped so a long game does not grow the label without bound.
const MAX_LINES := 200

var _line_count := 0


func _init() -> void:
	scroll_following = true
	selection_enabled = false
	fit_content = false
	custom_minimum_size = Vector2(0.0, 60.0)


## Appends the new lines only; earlier ones are never rebuilt. Returns how many lines were added.
func add_events(events: Array[SiEvent], names: SeatNames) -> int:
	var added := 0
	for event in events:
		# Phase changes repeat what the header shows and would drown the log.
		if event is SiEventPhaseChanged:
			continue
		_add_line(event, names)
		added += 1
	while _line_count > MAX_LINES:
		remove_paragraph(0)
		_line_count -= 1
	return added


func _add_line(event: SiEvent, names: SeatNames) -> void:
	if _line_count > 0:
		newline()
	var seat: Variant = event.get("seat")
	if seat is int:
		add_image(HudSeatChip.texture(seat), 16, 16)
		add_text(" ")
	add_text(HudText.event_line(event, names))
	_line_count += 1
