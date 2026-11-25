class_name Board
extends Control
## The island: tiles, buildings and click targets from the legal actions (step 2 of
## doc/plans/godot-client.md). Reads only its `GameState`, never `Net`. Fits and centres the island
## in its own rect and re-fits when the rect changes.

enum TargetKind { CORNER, EDGE, TILE }

const MARGIN := 16.0
## Pick radius around a corner or edge target, in hex units.
const PICK_RADIUS := 0.32
## Pick radius around a tile centre, in hex units (inside the hexagon's inner circle).
const TILE_PICK_RADIUS := 0.8

var state: GameState = null
## Pixels per hex unit and the pixel position of the unit origin, set by `_fit`.
var hex_size := 1.0
var origin := Vector2.ZERO

## Positions in hex units; built from the first view of the game.
var geometry: BoardGeometry = null
## The current click targets: `{action: SiAction, kind: TargetKind, point: Vector2}` in hex units.
var _targets: Array[Dictionary] = []
var _hovered: Dictionary = {}


func _ready() -> void:
	resized.connect(_fit)
	mouse_exited.connect(func() -> void: _set_hovered({}))


func bind(game_state: GameState) -> void:
	state = game_state
	state.changed.connect(func(_events: Array[SiEvent]) -> void: _refresh())
	_refresh()


## Pixel position (in this control) of a corner.
func corner_position(corner: int) -> Vector2:
	return to_pixels(geometry.corner_points[corner])


## Pixel position of corner `index` of a tile, computed from that tile alone.
func tile_corner_position(tile_index: int, index: int) -> Vector2:
	return to_pixels(BoardGeometry.tile_corner(state.view.board.tiles[tile_index].coordinates, index))


func to_pixels(point: Vector2) -> Vector2:
	return origin + point * hex_size


func _refresh() -> void:
	# The layout never changes during a game; only a new game brings a new board.
	if geometry == null or geometry.corner_points.size() != state.view.board.corners.size():
		geometry = BoardGeometry.new(state.view.board)
		_fit()
	_collect_targets()
	_set_hovered(_target_at(get_local_mouse_position()) if is_visible_in_tree() else {})
	queue_redraw()


func _fit() -> void:
	if geometry == null:
		return
	var available := size - Vector2.ONE * MARGIN * 2.0
	var bounds := geometry.bounds
	hex_size = maxf(1.0, minf(available.x / bounds.size.x, available.y / bounds.size.y))
	origin = size / 2.0 - bounds.get_center() * hex_size
	queue_redraw()


func _collect_targets() -> void:
	_targets.clear()
	for script: Script in [SiActionPlaceSettlement, SiActionBuildSettlement, SiActionBuildCity]:
		for action in state.legal_of(script):
			_add_target(action, TargetKind.CORNER, geometry.corner_points[action.get("corner")])
	for script: Script in [SiActionPlaceRoad, SiActionBuildRoad]:
		for action in state.legal_of(script):
			_add_target(action, TargetKind.EDGE, geometry.edge_midpoints[action.get("edge")])
	for action in state.legal_of(SiActionMoveRobber):
		_add_target(action, TargetKind.TILE, geometry.tile_centers[(action as SiActionMoveRobber).tile])


func _add_target(action: SiAction, kind: TargetKind, point: Vector2) -> void:
	_targets.append({"action": action, "kind": kind, "point": point})


func _target_at(pixel: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for target in _targets:
		var radius := TILE_PICK_RADIUS if target["kind"] == TargetKind.TILE else PICK_RADIUS
		var distance := pixel.distance_to(to_pixels(target["point"])) / hex_size
		if distance <= radius and distance < best_distance:
			best = target
			best_distance = distance
	return best


func _set_hovered(target: Dictionary) -> void:
	if target == _hovered:
		return
	_hovered = target
	mouse_default_cursor_shape = Control.CURSOR_ARROW if target.is_empty() else Control.CURSOR_POINTING_HAND
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if state == null or geometry == null:
		return
	if event is InputEventMouseMotion:
		_set_hovered(_target_at((event as InputEventMouseMotion).position))
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	var target := _target_at(button.position)
	if target.is_empty():
		return
	accept_event()
	state.act(target["action"])


func _draw() -> void:
	if state == null or geometry == null:
		return
	var painter := BoardPainter.new(self, state.view.board, geometry)
	painter.draw_sea()
	painter.draw_ports()
	painter.draw_tiles()
	painter.draw_roads()
	painter.draw_buildings()
	painter.draw_robber()
	painter.draw_targets(_targets, _hovered, state.seat)
