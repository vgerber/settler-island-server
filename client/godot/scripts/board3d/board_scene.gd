class_name BoardScene
extends Node3D
## The 3D contents of the table: lighting, sea, tiles and ports built once per game, and the pieces, which `sync`
## makes equal to a board without ever duplicating one (a piece is keyed by its corner or edge).

var _island := Node3D.new()
var _pieces := Node3D.new()
## Key (`c<corner>`, `e<edge>`, `robber`) to `{node, signature}`.
var _shown: Dictionary = {}
var _built_corners := -1


func _ready() -> void:
	_island.name = "Island"
	_pieces.name = "Pieces"
	add_child(_island)
	add_child(_pieces)
	_add_lighting()


## Builds the tiles and ports of a new game's board; the same layout is kept.
func build(board: SiBoard, geometry: BoardGeometry) -> void:
	if board.corners.size() == _built_corners:
		return
	_built_corners = board.corners.size()
	for child in _island.get_children() + _pieces.get_children():
		child.get_parent().remove_child(child)
		child.queue_free()
	_shown.clear()
	_island.add_child(PlaceholderArt.sea(geometry.bounds))
	for index in board.tiles.size():
		var tile := board.tiles[index]
		_island.add_child(PlaceholderArt.tile(geometry.tile_centers[index], tile.resource, tile.number))
	for port in geometry.ports:
		var corners: Array[Vector2] = []
		for corner: int in port["corners"]:
			corners.append(geometry.corner_points[corner])
		_island.add_child(PlaceholderArt.port(port["marker"], corners, port["port"]))


## Adds, replaces and removes pieces until they equal `board`.
func sync(board: SiBoard, geometry: BoardGeometry) -> void:
	_sync_buildings(board, geometry)
	_sync_roads(board, geometry)
	var center := geometry.tile_centers[board.robber]
	_show("robber", "tile %d" % board.robber, func() -> Node3D: return PlaceholderArt.robber(center))


## Where a piece stands for a table position in hex units; the motion layer starts and ends its ghosts here.
func rest_point(point: Vector2) -> Vector3:
	return Vector3(point.x, PlaceholderArt.SURFACE_HEIGHT, point.y)


## Where the robber stands on the tile with this centre.
func robber_point(tile_center: Vector2) -> Vector3:
	return rest_point(tile_center + PlaceholderArt.ROBBER_OFFSET)


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
			_show(key, "city %d" % building.seat, func() -> Node3D: return PlaceholderArt.city(building.seat, point))
		else:
			_show(key, "settlement %d" % building.seat, func() -> Node3D: return PlaceholderArt.settlement(building.seat, point))


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
		_show(key, "road %d" % seat, func() -> Node3D: return PlaceholderArt.road(seat, start, end))


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


func _add_lighting() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Palette.SEA.darkened(0.4)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#E8E4F0")
	environment.ambient_light_energy = 0.55
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var lamp := DirectionalLight3D.new()
	lamp.rotation_degrees = Vector3(-60.0, -35.0, 0.0)
	lamp.light_energy = 0.9
	add_child(lamp)
