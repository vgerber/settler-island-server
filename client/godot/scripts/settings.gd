extends Node
## Player settings in user://settings.cfg next to session.cfg: animation speed, skipping while unfocused and
## the sound volumes. Volumes go to the AudioServer buses "Sfx", "Ambience" and "Music"; a missing bus is skipped.

signal changed

enum AnimationSpeed { OFF, FAST, NORMAL, RELAXED }

const PATH := "user://settings.cfg"
const SPEED_NAMES := ["Off", "Fast", "Normal", "Relaxed"]
## Tween speed multiplier per `AnimationSpeed`; 0 means every beat commits at once.
const SPEED_FACTORS := [0.0, 2.0, 1.0, 0.75]
const BUSES := {"sfx_volume": "Sfx", "ambience_volume": "Ambience", "music_volume": "Music"}

var animation_speed := AnimationSpeed.NORMAL
var skip_when_unfocused := true
var sound_enabled := true
var sfx_volume := 0.8
var ambience_volume := 0.4
var music_volume := 0.0


func _ready() -> void:
	_load()
	apply_volumes()


func speed_factor() -> float:
	return SPEED_FACTORS[animation_speed]


## Sets one of the properties above by name, applies it and saves.
func update(key: String, value: Variant) -> void:
	set(key, value)
	apply_volumes()
	_save()
	changed.emit()


func apply_volumes() -> void:
	for key: String in BUSES:
		var bus := AudioServer.get_bus_index(BUSES[key])
		if bus < 0:
			continue
		var volume: float = get(key)
		AudioServer.set_bus_mute(bus, not sound_enabled or volume <= 0.0)
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))


func _load() -> void:
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return
	var stored := int(file.get_value("feedback", "animation_speed", animation_speed))
	animation_speed = clampi(stored, 0, SPEED_NAMES.size() - 1) as AnimationSpeed
	skip_when_unfocused = bool(file.get_value("feedback", "skip_when_unfocused", skip_when_unfocused))
	sound_enabled = bool(file.get_value("sound", "sound_enabled", sound_enabled))
	for key: String in BUSES:
		set(key, clampf(float(file.get_value("sound", key, get(key))), 0.0, 1.0))


func _save() -> void:
	var file := ConfigFile.new()
	file.set_value("feedback", "animation_speed", int(animation_speed))
	file.set_value("feedback", "skip_when_unfocused", skip_when_unfocused)
	file.set_value("sound", "sound_enabled", sound_enabled)
	for key: String in BUSES:
		file.set_value("sound", key, get(key))
	var error := file.save(PATH)
	if error != OK:
		push_warning("Settings: could not save %s (error %d)" % [PATH, error])
