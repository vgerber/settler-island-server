class_name BoardTarget
extends RefCounted
## One click target of the board: the legal action it sends and where it sits, in hex units.

enum Kind { CORNER, EDGE, TILE }

## Every action variant that can be a board target; the default filter of a board.
static var all_scripts: Array[Script] = [
	SiActionPlaceSettlement, SiActionBuildSettlement, SiActionBuildCity,
	SiActionPlaceRoad, SiActionBuildRoad, SiActionMoveRobber,
]

var action: SiAction
var kind: Kind
var point: Vector2


func _init(target_action: SiAction, target_kind: Kind, target_point: Vector2) -> void:
	action = target_action
	kind = target_kind
	point = target_point
