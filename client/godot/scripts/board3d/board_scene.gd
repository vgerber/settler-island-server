class_name BoardScene
extends Node3D
## The 3D contents of the table: lighting, table, water hexes, tiles and ports built once per game, the seat stands,
## and the pieces, which `sync` makes equal to a board without ever duplicating one (a piece is keyed by its corner
## or edge).

## How far the stand of the seat on the move is raised, and how far a pending seat pulses up.
const STAND_RAISE := 0.14
const STAND_PULSE_RAISE := 0.07

var _island := Node3D.new()
var _pieces := Node3D.new()
var _stands := Node3D.new()
## The stands that pulse, by node; refreshed by `sync_stands`.
var _pending_stands: Array[Node3D] = []
var _stands_signature := ""
## Key (`c<corner>`, `e<edge>`, `robber`) to `{node, signature}`.
var _shown: Dictionary = {}
var _built_corners := -1


func _ready() -> void:
	_island.name = "Island"
	_pieces.name = "Pieces"
	add_child(_island)
	add_child(_pieces)
	_stands.name = "Stands"
	add_child(_stands)
	TableLight.add_to(self)


## Builds the tiles and ports of a new game's board; the same layout is kept.
func build(board: SiBoard, geometry: BoardGeometry) -> void:
	if board.corners.size() == _built_corners:
		return
	_built_corners = board.corners.size()
	for child in _island.get_children() + _pieces.get_children():
		child.get_parent().remove_child(child)
		child.queue_free()
	_shown.clear()
	_island.add_child(BoardArt.table())
	_island.add_child(BoardArt.water(WaterArt.cells(geometry.tile_centers)))
	for index in board.tiles.size():
		var tile := board.tiles[index]
		_island.add_child(BoardArt.tile(tile.coordinates, geometry.tile_centers[index], tile.resource, tile.number))
	for port in geometry.ports:
		var corners: Array[Vector2] = []
		for corner: int in port["corners"]:
			corners.append(geometry.corner_points[corner])
		_island.add_child(BoardArt.port(port["marker"], corners, port["port"]))
	_stands_signature = ""


## Adds, replaces and removes pieces until they equal `board`.
func sync(board: SiBoard, geometry: BoardGeometry) -> void:
	_sync_buildings(board, geometry)
	_sync_roads(board, geometry)
	var center := geometry.tile_centers[board.robber]
	_show("robber", "tile %d" % board.robber, func() -> Node3D: return BoardArt.robber(center))


## One stand per seat around the island; the seat on the move is raised and every pending seat lit.
func sync_stands(view: SiPlayerView, geometry: BoardGeometry) -> void:
	var pending := HudText.pending_seats(view)
	var signature := "%d %d %s" % [view.players.size(), view.current, pending]
	if signature == _stands_signature:
		return
	_stands_signature = signature
	for child in _stands.get_children():
		_stands.remove_child(child)
		child.queue_free()
	_pending_stands.clear()
	for seat in view.players.size():
		var placement := BoardArt.stand_placement(seat, geometry.bounds)
		var lit := pending.has(seat) or seat == view.current
		var node := BoardArt.stand(seat, placement["position"], placement["yaw"], lit)
		if seat == view.current:
			node.position.y = STAND_RAISE
		elif lit:
			_pending_stands.append(node)
		_stands.add_child(node)


## Pending stands that are not the current one breathe with the marker pulse (0.55 to 1).
func set_pulse(pulse: float) -> void:
	for node in _pending_stands:
		node.position.y = STAND_PULSE_RAISE * (pulse - 0.55) / 0.45


## Whether some stand moves with the pulse, so the board has to keep processing.
func has_pulsing_stands() -> bool:
	return not _pending_stands.is_empty()


## Height of the stand of `seat`, for tests.
func stand_height(seat: int) -> float:
	return (_stands.get_child(seat) as Node3D).position.y


## Where a piece stands for a table position in hex units; the motion layer starts and ends its ghosts here.
func rest_point(point: Vector2) -> Vector3:
	return Vector3(point.x, BoardArt.SURFACE_HEIGHT, point.y)


## Where the robber stands on the tile with this centre.
func robber_point(tile_center: Vector2) -> Vector3:
	return rest_point(tile_center + BoardArt.ROBBER_OFFSET)


## The static piece node of a key (`c<corner>`, `e<edge>`, `robber`), or null.
func node_of(key: String) -> Node3D:
	var entry: Variant = _shown.get(key)
	return null if entry == null else entry["node"]


## Number of piece nodes, for tests.
func piece_count() -> int:
	return _pieces.get_child_count()


## Number of nodes under the island (tiles, ports, sea), for tests.
func island_count() -> int:
	return _island.get_child_count()


func _sync_buildings(board: SiBoard, geometry: BoardGeometry) -> void:
	for corner in board.buildings.size():
		var building := board.buildings[corner]
		var point := geometry.corner_points[corner]
		var key := "c%d" % corner
		if building == null:
			_remove(key)
		elif building.kind == SiBuildingKind.CITY:
			_show(key, "city %d" % building.seat, func() -> Node3D: return BoardArt.city(building.seat, point))
		else:
			_show(key, "settlement %d" % building.seat, func() -> Node3D: return BoardArt.settlement(building.seat, point))


func _sync_roads(board: SiBoard, geometry: BoardGeometry) -> void:
	for edge in board.roads.size():
		var seat: Variant = board.roads[edge]
		var key := "e%d" % edge
		if seat == null:
			_remove(key)
			continue
		var corners := board.edges[edge].corners
		var start := geometry.corner_points[corners[0]]
		var end := geometry.corner_points[corners[1]]
		_show(key, "road %d" % seat, func() -> Node3D: return BoardArt.road(seat, start, end))


func _show(key: String, signature: String, make: Callable) -> void:
	var entry: Variant = _shown.get(key)
	if entry != null and entry["signature"] == signature:
		return
	_remove(key)
	var node: Node3D = make.call()
	_pieces.add_child(node)
	_shown[key] = {"node": node, "signature": signature}


func _remove(key: String) -> void:
	var entry: Variant = _shown.get(key)
	if entry == null:
		return
	_shown.erase(key)
	var node := entry["node"] as Node3D
	_pieces.remove_child(node)
	node.queue_free()
