class_name Picking
extends RefCounted
## Analytic picking: no colliders, a target is hit when the pixel is within its projected world radius (at least
## `MIN_PIXELS`, the 40x40 touch target) and nearest wins, like `Board._target_at`.

## Pick radius around a corner or edge target, in hex units (as in the 2D board).
const WORLD_RADIUS := 0.32
## Pick radius around a tile centre, in hex units.
const TILE_WORLD_RADIUS := 0.8
const MIN_PIXELS := 20.0

var _rig: CameraRig


func _init(rig: CameraRig) -> void:
	_rig = rig


## The pixel of a target, in the board's local pixels.
func screen_point(target: BoardTarget) -> Vector2:
	return _rig.project(surface_point(target.point))


func pick(candidates: Array[BoardTarget], pixel: Vector2) -> BoardTarget:
	var best: BoardTarget = null
	var best_distance := INF
	for target in candidates:
		var distance := pixel.distance_to(screen_point(target))
		if distance <= radius_pixels(target) and distance < best_distance:
			best = target
			best_distance = distance
	return best


## The world radius as seen from the camera, never below the touch minimum.
func radius_pixels(target: BoardTarget) -> float:
	var world := TILE_WORLD_RADIUS if target.kind == BoardTarget.Kind.TILE else WORLD_RADIUS
	var centre := surface_point(target.point)
	# One radius to the camera's right on the table plane.
	var right := _rig.camera.global_basis.x * Vector3(1.0, 0.0, 1.0)
	var projected := _rig.project(centre).distance_to(_rig.project(centre + right.normalized() * world))
	return maxf(projected, MIN_PIXELS)


static func surface_point(point: Vector2) -> Vector3:
	return Vector3(point.x, PlaceholderArt.SURFACE_HEIGHT, point.y)
