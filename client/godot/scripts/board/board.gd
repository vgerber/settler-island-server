class_name Board
extends BoardView
## The island: tiles, buildings and click targets from the legal actions (step 2 of
## doc/plans/godot-client.md). Draws what its `EventPlayer` shows, never `Net`. Fits and centres the island
## in its own rect and re-fits when the rect changes.

const MARGIN := 16.0
## Pick radius around a corner or edge target, in hex units.
const PICK_RADIUS := 0.32
## Pick radius around a tile centre, in hex units (inside the hexagon's inner circle).
const TILE_PICK_RADIUS := 0.8

## Pixels per hex unit and the pixel position of the unit origin, set by `_fit`.
var hex_size := 1.0
var origin := Vector2.ZERO

var _hovered: BoardTarget = null
## Seconds since the targets appeared, for their glow.
var _pulse_time := 0.0


func _ready() -> void:
	resized.connect(_fit)
	mouse_exited.connect(func() -> void: _set_hovered(null))
	set_process(false)


## Redraws the target glow while any target is shown.
func _process(delta: float) -> void:
	_pulse_time += delta
	queue_redraw()


func set_target_filter(kinds: Array[Script]) -> void:
	_filter = kinds
	if geometry != null:
		_refresh()


func targets() -> Array[BoardTarget]:
	return _targets


func bind(event_player: EventPlayer) -> void:
	player = event_player
	player.committed.connect(_refresh)
	_refresh()


func screen_point(target: BoardTarget) -> Vector2:
	return get_global_transform_with_canvas() * to_pixels(target.point)


## Pixel position (in this control) of a corner.
func corner_position(corner: int) -> Vector2:
	return to_pixels(geometry.corner_points[corner])


## Pixel position of corner `index` of a tile, computed from that tile alone.
func tile_corner_position(tile_index: int, index: int) -> Vector2:
	return to_pixels(BoardGeometry.tile_corner(player.shown_view.board.tiles[tile_index].coordinates, index))


func to_pixels(point: Vector2) -> Vector2:
	return origin + point * hex_size


func _refresh() -> void:
	# The layout never changes during a game; only a new game brings a new board.
	if geometry == null or geometry.corner_points.size() != player.shown_view.board.corners.size():
		geometry = BoardGeometry.new(player.shown_view.board)
		_fit()
	_collect_targets()
	_set_hovered(_target_at(get_local_mouse_position()) if is_visible_in_tree() else null)
	set_process(not _targets.is_empty())
	queue_redraw()


func _fit() -> void:
	if geometry == null:
		return
	var available := size - Vector2.ONE * MARGIN * 2.0
	var bounds := geometry.bounds
	hex_size = maxf(1.0, minf(available.x / bounds.size.x, available.y / bounds.size.y))
	origin = size / 2.0 - bounds.get_center() * hex_size
	queue_redraw()


func _target_at(pixel: Vector2) -> BoardTarget:
	var best: BoardTarget = null
	var best_distance := INF
	for target in _targets:
		var radius := TILE_PICK_RADIUS if target.kind == BoardTarget.Kind.TILE else PICK_RADIUS
		var distance := pixel.distance_to(to_pixels(target.point)) / hex_size
		if distance <= radius and distance < best_distance:
			best = target
			best_distance = distance
	return best


func _set_hovered(target: BoardTarget) -> void:
	if target == _hovered:
		return
	_hovered = target
	mouse_default_cursor_shape = Control.CURSOR_ARROW if target == null else Control.CURSOR_POINTING_HAND
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if player == null or geometry == null:
		return
	if event is InputEventMouseMotion:
		_set_hovered(_target_at((event as InputEventMouseMotion).position))
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	var target := _target_at(button.position)
	if target == null:
		return
	accept_event()
	player.act(target.action)


func _draw() -> void:
	if player == null or geometry == null:
		return
	var painter := BoardPainter.new(self, player.shown_view.board, geometry)
	painter.draw_sea()
	painter.draw_tiles()
	# Piers reach under the tiles' edge, so ports go on top of them.
	painter.draw_ports()
	painter.draw_roads()
	painter.draw_buildings()
	painter.draw_robber()
	painter.draw_targets(_targets, _hovered, player.seat, _pulse())


## Brightness of the target glow, 0.55 to 1.
func _pulse() -> float:
	return 0.775 + 0.225 * sin(_pulse_time * TAU * 0.8)
