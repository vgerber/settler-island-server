extends Node
## Autoload `Atmosphere`: the background of a screen. `menu` plays calm music; `table` adds the island waves, an
## occasional gull call and the table music. Moods crossfade; `silent` (also used headless) plays nothing.

const MOOD_MENU := &"menu"
const MOOD_TABLE := &"table"
const MOOD_SILENT := &"silent"
const CROSSFADE_SECONDS := 1.0
const SILENT_DB := -80.0
const GULL_DELAY_SECONDS := Vector2(20.0, 60.0)
const GULL_FILES: Array[String] = [
	"res://audio/ambience/gull_1.ogg", "res://audio/ambience/gull_2.ogg", "res://audio/ambience/gull_3.ogg",
	"res://audio/ambience/gull_4.ogg", "res://audio/ambience/gull_5.ogg",
]

var mood := MOOD_SILENT

var _menu_music := _make_loop("res://audio/music/menu_snow_theme.ogg", &"Music")
var _table_music := _make_loop("res://audio/music/table_old_tower_inn.ogg", &"Music")
var _waves := _make_loop("res://audio/ambience/waves_loop.ogg", &"Ambience")
var _gull := AudioStreamPlayer.new()
var _gull_timer := Timer.new()
var _gulls: Array[AudioStream] = []
var _muted := DisplayServer.get_name() == "headless"
var _tween: Tween


func _ready() -> void:
	for file in GULL_FILES:
		_gulls.append(load(file))
	_gull.bus = &"Ambience"
	_gull_timer.one_shot = true
	_gull_timer.timeout.connect(_on_gull_timer)
	add_child(_gull)
	add_child(_gull_timer)
	for player in _loops():
		add_child(player)


func set_mood(new_mood: StringName) -> void:
	if new_mood == mood:
		return
	mood = new_mood
	if _muted:
		return
	var targets := {_menu_music: mood == MOOD_MENU, _table_music: mood == MOOD_TABLE, _waves: mood == MOOD_TABLE}
	_crossfade(targets)
	if mood == MOOD_TABLE:
		_schedule_gull()
		return
	_gull_timer.stop()


func _crossfade(targets: Dictionary) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel()
	for player: AudioStreamPlayer in targets:
		var audible: bool = targets[player]
		if audible and not player.playing:
			player.volume_db = SILENT_DB
			player.play()
		_tween.tween_property(player, "volume_db", 0.0 if audible else SILENT_DB, CROSSFADE_SECONDS)
	_tween.chain().tween_callback(_stop_silent_loops)


func _stop_silent_loops() -> void:
	for player in _loops():
		if player.volume_db <= SILENT_DB:
			player.stop()


func _loops() -> Array[AudioStreamPlayer]:
	return [_menu_music, _table_music, _waves]


func _schedule_gull() -> void:
	_gull_timer.start(randf_range(GULL_DELAY_SECONDS.x, GULL_DELAY_SECONDS.y))


func _on_gull_timer() -> void:
	_gull.stream = _gulls.pick_random()
	_gull.play()
	_schedule_gull()


func _make_loop(path: String, bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	var stream: AudioStreamOggVorbis = load(path)
	# Looping is set here because the `.import` files are generated, not committed.
	stream.loop = true
	player.stream = stream
	player.bus = bus
	player.volume_db = SILENT_DB
	return player
