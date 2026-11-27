class_name TableLayout
extends RefCounted
## Where things happen on the table, in world units: the dice tray at the near edge, a stand point per seat around
## the island (the local seat nearest the camera) and the bank deck. Built from the scene and the board geometry.

const EDGE_MARGIN := 0.35
const TRAY_SIZE := Vector2(1.6, 0.95)
const DIE_SPACING := 0.5
## Free space the tray keeps around its footprint from piers (with their flags), land tiles and stands.
const PIER_CLEARANCE := 0.4
const STAND_CLEARANCE := 0.2
const TRAY_SEARCH_STEP := 0.25
## The tray is searched for near this point: the near right corner of the island, in hex units from its bounds end.
const TRAY_WISH := Vector2(-0.5, -1.0)
## Half size of a land hex (apothem along x, circumradius along z) plus a seam.
const HEX_HALF := Vector2(0.9, 1.05)

var geometry: BoardGeometry
var _scene: BoardScene
var _tray := Vector3.INF


func _init(scene: BoardScene, board_geometry: BoardGeometry) -> void:
	_scene = scene
	geometry = board_geometry


func corner(index: int) -> Vector3:
	return _scene.rest_point(geometry.corner_points[index])


func tile(index: int) -> Vector3:
	return _scene.rest_point(geometry.tile_centers[index])


func robber(tile_index: int) -> Vector3:
	return _scene.robber_point(geometry.tile_centers[tile_index])


func center() -> Vector3:
	return _scene.rest_point(geometry.bounds.get_center())


## Where the stand of `seat` is, as the scene builds it.
func seat_point(seat: int) -> Vector3:
	var position: Vector3 = BoardArt.stand_placement(seat, geometry.bounds)["position"]
	return _scene.rest_point(Vector2(position.x, position.z))


## The dice tray centre: on the water hexes at the free spot nearest to the near right corner of the island, so
## the tray stays in view and covers no pier, flag, land tile or stand.
func tray_center() -> Vector3:
	if _tray == Vector3.INF:
		_tray = _find_tray()
	return _tray


## The ground footprint of a tray centred at `center`, in hex units.
static func tray_footprint(center: Vector2) -> Rect2:
	return Rect2(center - TRAY_SIZE / 2.0, TRAY_SIZE)


## Where die `index` rests inside the tray, on its floor.
func dice_rest(index: int) -> Vector3:
	return tray_center() + Vector3((index - 0.5) * DIE_SPACING, TableArt.TRAY_FLOOR + DieArt.HALF, 0.0)


func _find_tray() -> Vector3:
	var wish := geometry.bounds.end + TRAY_WISH
	var obstacles := _obstacles()
	var best := Vector2(INF, INF)
	var limit := Vector2(WaterArt.HALF_WIDTH, WaterArt.HALF_DEPTH) - TRAY_SIZE / 2.0
	var steps := Vector2i(ceili(limit.x / TRAY_SEARCH_STEP), ceili(limit.y / TRAY_SEARCH_STEP))
	for column in range(-steps.x, steps.x + 1):
		for row in range(-steps.y, steps.y + 1):
			var candidate := Vector2(column, row) * TRAY_SEARCH_STEP
			if candidate.distance_to(wish) >= best.distance_to(wish):
				continue
			if absf(candidate.x) <= limit.x and absf(candidate.y) <= limit.y and _is_free(tray_footprint(candidate), obstacles):
				best = candidate
	return Vector3(best.x, WaterArt.HEIGHT, best.y)


## Everything on the water the tray must keep clear of: pier points with their clearance, land and stand rects.
func _obstacles() -> Dictionary:
	var pier_points: Array[Vector2] = []
	for port in geometry.ports:
		var corners: Array = port["corners"]
		var edge := (geometry.corner_points[corners[0]] + geometry.corner_points[corners[1]]) / 2.0
		var outward := ((port["marker"] as Vector2) - edge).normalized()
		for step in 9:
			pier_points.append(edge + outward * PortArt.PIER_LENGTH * step / 8.0)
	var blocked: Array[Rect2] = []
	for center in geometry.tile_centers:
		blocked.append(Rect2(center - HEX_HALF, HEX_HALF * 2.0))
	for seat in 4:
		var placement := BoardArt.stand_placement(seat, geometry.bounds)
		var position: Vector3 = placement["position"]
		var half := Vector2(TableArt.STAND_HALF_WIDTH, TableArt.STAND_HALF_DEPTH)
		if not is_zero_approx(placement["yaw"]):
			half = Vector2(half.y, half.x)
		blocked.append(Rect2(Vector2(position.x, position.z) - half, half * 2.0).grow(STAND_CLEARANCE))
	return {"piers": pier_points, "rects": blocked}


static func _is_free(footprint: Rect2, obstacles: Dictionary) -> bool:
	var pier_zone := footprint.grow(PIER_CLEARANCE)
	for point: Vector2 in obstacles["piers"]:
		if pier_zone.has_point(point):
			return false
	for rect: Rect2 in obstacles["rects"]:
		if footprint.intersects(rect):
			return false
	return true


## The bank deck, at the far left corner of the table.
func deck_point() -> Vector3:
	return _scene.rest_point(geometry.bounds.position + Vector2(-EDGE_MARGIN, EDGE_MARGIN))
