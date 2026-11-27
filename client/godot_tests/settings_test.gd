extends SceneTree
## Runs inside a copy of the game project: `Settings` keeps the table view and the graphics quality across a
## restart, falls back to 2D and Standard for unknown stored values, and writes or removes the renderer override.
## Usage: godot --headless --path <copy of client/godot> -s settings_test.gd

const SettingsScript := preload("res://scripts/settings.gd")

var _failures: PackedStringArray = []


func _initialize() -> void:
	_check_stored_values()
	_check_override()
	SiTestSupport.finish(self, 0 if _failures.is_empty() else 1, "SETTINGS_OK" if _failures.is_empty() else "SETTINGS_FAILED " + "; ".join(_failures))


func _check_stored_values() -> void:
	var file := ConfigFile.new()
	file.set_value("table", "board_view", "hologram")
	file.set_value("table", "graphics_quality", "Ultra")
	file.save(SettingsScript.PATH)
	var settings := SettingsScript.new()
	settings._ready()
	_expect(settings.board_view == "2d", "unknown board view falls back to 2d, got %s" % settings.board_view)
	_expect(settings.graphics_quality == "Standard", "unknown quality falls back to Standard, got %s" % settings.graphics_quality)
	settings.update("board_view", "3d")
	settings.update("graphics_quality", "High")
	var again := SettingsScript.new()
	again._ready()
	_expect(again.board_view == "3d" and again.graphics_quality == "High", "both choices survive a reload")
	DirAccess.remove_absolute(SettingsScript.PATH)
	settings.free()
	again.free()


func _check_override() -> void:
	var path := "user://override_test.cfg"
	var settings := SettingsScript.new()
	settings.graphics_quality = "High"
	_expect(settings.write_renderer_override(path), "High writes the override")
	var file := ConfigFile.new()
	file.load(path)
	_expect(file.get_value("rendering", "renderer/rendering_method", "") == "forward_plus", "High asks for forward_plus")
	settings.graphics_quality = "Standard"
	_expect(settings.write_renderer_override(path) and not FileAccess.file_exists(path), "Standard removes the override")
	_expect(settings.write_renderer_override(path), "Standard without a file is fine")
	_expect(not settings.write_renderer_override(""), "no executable directory means no override")
	settings.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
