class_name HudEventLog
extends RichTextLabel
## The game so far as readable lines, newest at the bottom; each line is tinted with its seat's colour.

## Older lines are dropped so a long game does not grow the label without bound.
const MAX_LINES := 200

var _lines: PackedStringArray = []


func _init() -> void:
	bbcode_enabled = true
	scroll_following = true
	selection_enabled = false
	add_theme_font_size_override("normal_font_size", 14)


func add_events(events: Array[SiEvent], own_seat: int) -> void:
	for event in events:
		# Phase changes repeat what the header shows and would drown the log.
		if event is SiEventPhaseChanged:
			continue
		var line := HudText.event_line(event, own_seat).replace("[", "[lb]")
		var seat = event.get("seat")
		if seat is int:
			line = "[color=#%s]%s[/color]" % [HudText.seat_color(seat).to_html(false), line]
		_lines.append(line)
	if _lines.size() > MAX_LINES:
		_lines = _lines.slice(_lines.size() - MAX_LINES)
	text = "\n".join(_lines)
