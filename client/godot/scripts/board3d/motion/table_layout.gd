class_name TableLayout
extends RefCounted
## Where things happen on the table, in world units: the dice tray at the near edge, a stand point per seat around
## the island (the local seat nearest the camera) and the bank deck. Built from the scene and the board geometry.

const EDGE_MARGIN := 0.35
const TRAY_SIZE := Vector2(1.7, 0.95)
## Offset of the tray centre from the bounds corner; the tray reaches past the island on the right.
const TRAY_INSET := Vector2(-0.3, 1.0)

var geometry: BoardGeometry
var own_seat := 0
var seat_count := 1
var _scene: BoardScene


func _init(scene: BoardScene, board_geometry: BoardGeometry, local_seat: int, seats: int) -> void:
	_scene = scene
	geometry = board_geometry
	own_seat = local_seat
	seat_count = maxi(seats, 1)


func corner(index: int) -> Vector3:
	return _scene.rest_point(geometry.corner_points[index])


func tile(index: int) -> Vector3:
	return _scene.rest_point(geometry.tile_centers[index])


func robber(tile_index: int) -> Vector3:
	return _scene.robber_point(geometry.tile_centers[tile_index])


func center() -> Vector3:
	return _scene.rest_point(geometry.bounds.get_center())


## Where the stand of `seat` is: on the ring around the island, the local seat at the near edge.
func seat_point(seat: int) -> Vector3:
	var angle := TAU * float(posmod(seat - own_seat, seat_count)) / seat_count
	var half := geometry.bounds.size / 2.0
	var offset := Vector2(sin(angle) * (half.x + EDGE_MARGIN), cos(angle) * (half.y + EDGE_MARGIN))
	return _scene.rest_point(geometry.bounds.get_center() + offset)


## The dice tray centre, on the top of the water hexes in the near right corner of the table, where the hex island leaves the sea free and the
## camera still sees it (the island fills the slot, so the very edge below it would be cut off).
func tray_center() -> Vector3:
	var corner := geometry.bounds.end - Vector2(TRAY_INSET.x, TRAY_INSET.y)
	return Vector3(corner.x, WaterArt.HEIGHT, corner.y)


## The bank deck, at the far left corner of the table.
func deck_point() -> Vector3:
	return _scene.rest_point(geometry.bounds.position + Vector2(-EDGE_MARGIN, EDGE_MARGIN))
