extends SceneTree
## Runs inside a copy of the game project: every `SiEvent` variant, built from a dict, becomes a
## non-empty log line that the log accepts. The samples are the Rust fixtures; a variant without one fails.
## Usage: godot --headless --path <copy of client/godot> -s hud_event_log.gd -- <fixtures.json>

const OWN_SEAT := 1


func _init() -> void:
	var fixtures: Variant = JSON.parse_string(FileAccess.get_file_as_string(SiTestSupport.argument(0)))
	if not fixtures is Dictionary:
		SiTestSupport.finish(self, 1, "HUD_EVENT_LOG_FAILED fixtures are not a JSON object")
		return
	var failures := _check_lines(fixtures["events"])
	if failures.is_empty():
		SiTestSupport.finish(self, 0, "HUD_EVENT_LOG_OK")
		return
	SiTestSupport.finish(self, 1, "HUD_EVENT_LOG_FAILED %s" % ", ".join(failures))


func _check_lines(samples: Array) -> PackedStringArray:
	var failures: PackedStringArray = []
	var log := HudEventLog.new()
	for data: Dictionary in samples:
		var event := SiEvent.from_dict(data)
		var variant := str(data["type"])
		if event == null or event.get_script() == SiEvent:
			failures.append("%s did not decode" % variant)
			continue
		var line := HudText.event_line(event, OWN_SEAT)
		print("%s -> %s" % [variant, line])
		if line.strip_edges().is_empty() or line == variant:
			failures.append("%s has no readable line" % variant)
		log.add_events([event] as Array[SiEvent], OWN_SEAT)
	for variant in SiTestSupport.missing_variants("SiEvent", samples):
		failures.append("%s has no sample" % variant)
	log.free()
	return failures
