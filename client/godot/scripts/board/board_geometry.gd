class_name BoardGeometry
extends RefCounted
## Positions of tiles, corners, edges and ports of one board in hex units (a hex side is 1), pointy-top.
## The neighbour directions of settler_island_game/src/coordinates.rs run clockwise on screen from
## east (y grows downwards), and corner `i` lies between neighbour `i` and `i + 1`, so corner `i`
## points at 30 + 60 * i degrees.

const SQUARE_ROOT_OF_THREE := 1.7320508
## How far a port marker sits outside its coast edge, from the edge midpoint.
const PORT_DISTANCE := 0.62
const PORT_RADIUS := 0.3

var tile_centers: Array[Vector2] = []
var corner_points: Array[Vector2] = []
var edge_midpoints: Array[Vector2] = []
## One entry per port: `{port: SiPort, corners: [int, int], marker: Vector2}`.
var ports: Array[Dictionary] = []
## Everything that is drawn, ports included.
var bounds := Rect2()


func _init(board: SiBoard) -> void:
	for tile in board.tiles:
		tile_centers.append(tile_center(tile.coordinates))
	corner_points.resize(board.corners.size())
	var placed: Array[bool] = []
	placed.resize(board.corners.size())
	for tile in board.tiles:
		_place_corners(tile, placed)
	for edge in board.edges:
		edge_midpoints.append((corner_points[edge.corners[0]] + corner_points[edge.corners[1]]) / 2.0)
	_find_ports(board)
	_measure()


static func tile_center(coordinates: SiCubeCoordinates) -> Vector2:
	return Vector2(SQUARE_ROOT_OF_THREE * (coordinates.q + coordinates.r / 2.0), 1.5 * coordinates.r)


## Corner `index` of the tile at `coordinates`.
static func tile_corner(coordinates: SiCubeCoordinates, index: int) -> Vector2:
	var angle := deg_to_rad(30.0 + 60.0 * index)
	return tile_center(coordinates) + Vector2(cos(angle), sin(angle))


## The first tile listing a corner places it; the others agree (checked in the board test).
func _place_corners(tile: SiTile, placed: Array[bool]) -> void:
	for index in tile.corners.size():
		var corner := tile.corners[index]
		if placed[corner]:
			continue
		placed[corner] = true
		corner_points[corner] = tile_corner(tile.coordinates, index)


func _find_ports(board: SiBoard) -> void:
	for edge in board.edges:
		if edge.port != null:
			_add_port(board, edge)


func _add_port(board: SiBoard, edge: SiEdge) -> void:
	var first := board.corners[edge.corners[0]]
	var coast_tile: int = _shared_tiles(first, board.corners[edge.corners[1]])[0]
	var midpoint := (corner_points[edge.corners[0]] + corner_points[edge.corners[1]]) / 2.0
	var outward := (midpoint - tile_centers[coast_tile]).normalized()
	ports.append({"port": edge.port, "corners": edge.corners, "marker": midpoint + outward * PORT_DISTANCE})


func _shared_tiles(first: SiCorner, second: SiCorner) -> Array[int]:
	var shared: Array[int] = []
	for tile in first.tiles:
		if second.tiles.has(tile):
			shared.append(tile)
	return shared


func _measure() -> void:
	bounds = Rect2(corner_points[0], Vector2.ZERO)
	for point in corner_points:
		bounds = bounds.expand(point)
	for port in ports:
		var marker: Vector2 = port["marker"]
		bounds = bounds.merge(Rect2(marker - Vector2.ONE * PORT_RADIUS, Vector2.ONE * PORT_RADIUS * 2.0))
