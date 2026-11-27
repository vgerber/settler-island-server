extends Node
## Autoload `Sfx`: plays a sound effect by hook name from `res://audio/<hook>.ogg`. Callers only name the hook, so a
## missing file never breaks gameplay.

const BUS := &"Sfx"
const POOL_SIZE := 6
const DUPLICATE_WINDOW_MILLISECONDS := 80
const PITCH_SPREAD := 0.05
## The hooks of `doc/design/feedback.md`; each has a file in `res://audio`.
const HOOKS: Array[StringName] = [
	&"sfx_place_settlement", &"sfx_place_road", &"sfx_build_city", &"sfx_dice_shake", &"sfx_dice_land",
	&"sfx_roll_seven", &"sfx_card_gain", &"sfx_pay", &"sfx_discard", &"sfx_robber_move", &"sfx_steal",
	&"sfx_stolen_from_me", &"sfx_trade_bank", &"sfx_trade_offer", &"sfx_trade_accept", &"sfx_trade_reject",
	&"sfx_trade_done", &"sfx_trade_cancel", &"sfx_dev_buy", &"sfx_dev_play_knight",
	&"sfx_dev_play_road_building", &"sfx_dev_play_year_of_plenty", &"sfx_dev_play_monopoly",
	&"sfx_dev_play_victory_point", &"sfx_monopoly", &"sfx_dev_gain", &"sfx_award_road", &"sfx_award_army",
	&"sfx_turn_start", &"sfx_attention", &"sfx_error", &"sfx_victory", &"sfx_game_over", &"sfx_ui_click",
	&"sfx_ui_hover",
]

var _streams: Dictionary[StringName, AudioStream] = {}
var _last_played_milliseconds: Dictionary[StringName, int] = {}
var _warned: Dictionary[StringName, bool] = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
## Headless runs have no audio output, and playbacks still running at quit are reported as leaks.
var _silent := DisplayServer.get_name() == "headless"


func _ready() -> void:
	for _index in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = BUS
		add_child(player)
		_players.append(player)
	for hook in HOOKS:
		_load(hook)


func _exit_tree() -> void:
	# Streams still held at quit are reported as leaked resources.
	for player in _players:
		player.stop()
		player.stream = null
	_streams.clear()


## Starts the sound of `hook`; false when it is unknown, missing or a repeat within the duplicate window.
func play(hook: StringName) -> bool:
	var stream := _stream_of(hook)
	if stream == null:
		return false
	var now := Time.get_ticks_msec()
	if now - _last_played_milliseconds.get(hook, -DUPLICATE_WINDOW_MILLISECONDS) < DUPLICATE_WINDOW_MILLISECONDS:
		return false
	_last_played_milliseconds[hook] = now
	var player := _free_player()
	player.stream = stream
	player.pitch_scale = randf_range(1.0 - PITCH_SPREAD, 1.0 + PITCH_SPREAD)
	if not _silent:
		player.play()
	return true


func _stream_of(hook: StringName) -> AudioStream:
	if not _streams.has(hook) and not _warned.has(hook):
		_load(hook)
	return _streams.get(hook)


func _load(hook: StringName) -> void:
	var path := "res://audio/%s.ogg" % hook
	if ResourceLoader.exists(path):
		_streams[hook] = load(path)
		return
	_warned[hook] = true
	push_warning("Sfx: no sound file for hook %s" % hook)


## An idle player, else the next one in turn so a burst replaces the oldest sound.
func _free_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	_next_player = (_next_player + 1) % POOL_SIZE
	return _players[_next_player]
