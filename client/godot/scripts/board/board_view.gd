class_name BoardView
extends Control
## What the game screen and the UI test need from a board, 2D or 3D: it draws what its `EventPlayer` shows,
## offers the click targets of the legal board actions and tells where each target is on screen.

var player: EventPlayer = null
## Positions in hex units; built from the first view of the game.
var geometry: BoardGeometry = null
## The click targets shown: the legal board actions of the kinds in the target filter.
var _targets: Array[BoardTarget] = []
## The action variants whose targets are shown; the HUD narrows it in build mode.
var _filter: Array[Script] = BoardTarget.all_scripts


## Follows `event_player`: redraws on each commit and clicks send actions through it.
func bind(_event_player: EventPlayer) -> void:
	push_error("BoardView.bind is abstract")


## Shows only the targets of these action variants, e.g. `[SiActionBuildRoad]` in build mode.
func set_target_filter(_kinds: Array[Script]) -> void:
	push_error("BoardView.set_target_filter is abstract")


## Takes a resource name and gives the global pixel of its card in the HUD hand; a 3D board flies cards there.
var hand_slot := Callable()


## The targets currently shown.
func targets() -> Array[BoardTarget]:
	return _targets


## Where `target` is in viewport coordinates, the point a mouse click hits it.
func screen_point(_target: BoardTarget) -> Vector2:
	push_error("BoardView.screen_point is abstract")
	return Vector2.ZERO


func _collect_targets() -> void:
	_targets.clear()
	for script: Script in _filter:
		for action in player.legal_of(script):
			_targets.append(_target_of(action))


func _target_of(action: SiAction) -> BoardTarget:
	if action is SiActionMoveRobber:
		return BoardTarget.new(action, BoardTarget.Kind.TILE, geometry.tile_centers[(action as SiActionMoveRobber).tile])
	if action is SiActionPlaceRoad or action is SiActionBuildRoad:
		return BoardTarget.new(action, BoardTarget.Kind.EDGE, geometry.edge_midpoints[action.get("edge")])
	return BoardTarget.new(action, BoardTarget.Kind.CORNER, geometry.corner_points[action.get("corner")])
