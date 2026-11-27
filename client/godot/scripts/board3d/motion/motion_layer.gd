class_name MotionLayer
extends Node3D
## Base of the motion layers of `BoardMotion`: they follow the `EventPlayer`, run their tweens at the player's
## speed and pace and end every one of them in `finish_all`.

## Never zero, so a tween created during a pause is not frozen when the speed returns.
const MIN_SPEED := 0.05

var player: EventPlayer = null
var layout: TableLayout = null
var _live: Array[Tween] = []


## Tweens running now, for tests.
func running_tweens() -> int:
	return _live.size()


## Ends every running animation at its end state; subclasses free their transient nodes after calling this.
func finish_all() -> void:
	for tween in _live:
		tween.kill()
	_live.clear()


func _tween() -> Tween:
	var tween := create_tween()
	tween.set_speed_scale(maxf(player.speed_factor * player.current_pace(), MIN_SPEED))
	_live.append(tween)
	tween.finished.connect(_live.erase.bind(tween))
	return tween
