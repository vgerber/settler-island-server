class_name BoardView
extends Control
## What the game screen and the UI test need from a board, 2D or 3D: it draws what its `EventPlayer` shows,
## offers the click targets of the legal board actions and tells where each target is on screen.

var player: EventPlayer = null
## The click targets shown: the legal board actions of the kinds in the target filter.
var _targets: Array[BoardTarget] = []


## Follows `event_player`: redraws on each commit and clicks send actions through it.
func bind(_event_player: EventPlayer) -> void:
	push_error("BoardView.bind is abstract")


## Shows only the targets of these action variants, e.g. `[SiActionBuildRoad]` in build mode.
func set_target_filter(_kinds: Array[Script]) -> void:
	push_error("BoardView.set_target_filter is abstract")


## The targets currently shown.
func targets() -> Array[BoardTarget]:
	return _targets


## Where `target` is in viewport coordinates, the point a mouse click hits it.
func screen_point(_target: BoardTarget) -> Vector2:
	push_error("BoardView.screen_point is abstract")
	return Vector2.ZERO
