extends SceneTree
## Runs inside a copy of the game project with its `Sfx` and `Atmosphere` autoloads: every hook has a loadable
## file and every sound file is a hook, the same hook twice within the duplicate window plays once, and the moods
## switch headless without errors.
## Usage: godot --headless --path <copy of client/godot> -s sfx_atmosphere.gd

const AUDIO_DIRECTORY := "res://audio"


func _initialize() -> void:
	# The autoloads enter the tree before their `_ready` has run.
	_run.call_deferred()


func _run() -> void:
	var failures := _check_files()
	failures.append_array(_check_dedupe())
	failures.append_array(_check_moods())
	# Playbacks still running at quit are reported as leaked resources; both sounds are far shorter.
	await create_timer(0.5).timeout
	if failures.is_empty():
		SiTestSupport.finish(self, 0, "SFX_ATMOSPHERE_OK")
		return
	SiTestSupport.finish(self, 1, "SFX_ATMOSPHERE_FAILED %s" % ", ".join(failures))


func _check_files() -> PackedStringArray:
	var failures: PackedStringArray = []
	var hooks: Array[StringName] = root.get_node("Sfx").HOOKS
	for hook in hooks:
		if not load("%s/%s.ogg" % [AUDIO_DIRECTORY, hook]) is AudioStream:
			failures.append("hook %s has no loadable stream" % hook)
	for file in DirAccess.get_files_at(AUDIO_DIRECTORY):
		var hook := StringName(file.get_basename())
		if file.ends_with(".ogg") and not hooks.has(hook):
			failures.append("%s is no hook" % file)
	return failures


func _check_dedupe() -> PackedStringArray:
	var sfx := root.get_node("Sfx")
	var failures: PackedStringArray = []
	if not sfx.play(&"sfx_ui_click"):
		failures.append("first play was dropped")
	if sfx.play(&"sfx_ui_click"):
		failures.append("repeat within the window played")
	if not sfx.play(&"sfx_ui_hover"):
		failures.append("another hook was dropped")
	if sfx.play(&"sfx_no_such_hook"):
		failures.append("unknown hook played")
	return failures


func _check_moods() -> PackedStringArray:
	var atmosphere := root.get_node("Atmosphere")
	var failures: PackedStringArray = []
	for mood: StringName in [&"menu", &"table", &"silent"]:
		atmosphere.set_mood(mood)
		if atmosphere.mood != mood:
			failures.append("mood %s not set" % mood)
	return failures
