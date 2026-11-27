class_name CameraRig
extends Node3D
## The table camera: a pivot at the island centre with yaw, pitch, a zoom factor on the fit distance and a limited
## pan. The distance fits the projected island into the viewport, so it follows the slot size. Projection is done
## here with the camera's own formula (vertical field of view kept), so it works without a render pass.

const FIELD_OF_VIEW := 35.0
const DEFAULT_PITCH := 55.0
const MIN_PITCH := 30.0
const MAX_PITCH := 80.0
const MIN_ZOOM := 0.6
const MAX_ZOOM := 1.5
## Furthest the pivot may move from the island centre, in hex units.
const MAX_PAN := 2.5
const MARGIN := 16.0
const FIT_STEPS := 14
const MAX_FIT_DISTANCE := 200.0
const ORBIT_DEGREES_PER_PIXEL := 0.3
const RESET_SECONDS := 0.25

var camera := Camera3D.new()
var yaw := 0.0
var pitch := DEFAULT_PITCH
## Factor on the fit distance: below 1 is closer.
var zoom := 1.0
var pan := Vector2.ZERO
## Control-local pixels of the board, the rect the island has to fit.
var viewport_size := Vector2(1260.0, 676.0)

var _center := Vector3.ZERO
var _cloud := PackedVector3Array()
var _fit_distance := 20.0
var _current := Transform3D.IDENTITY
var _tween: Tween = null


func _ready() -> void:
	camera.fov = FIELD_OF_VIEW
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.5
	camera.far = MAX_FIT_DISTANCE * 2.0
	add_child(camera)
	_apply()


## Frames the island of `geometry`: the points that must stay in view are its corners at table and piece height
## and the port badges.
func frame(geometry: BoardGeometry) -> void:
	_cloud.clear()
	for point in geometry.corner_points:
		_add_column(point)
	for port in geometry.ports:
		var marker: Vector2 = port["marker"]
		for corner in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			_add_column(marker + corner * BoardGeometry.PORT_RADIUS)
	var center := geometry.bounds.get_center()
	_center = Vector3(center.x, 0.0, center.y)
	_refit()


## A board that has no layout yet (smaller than its margins) keeps the previous size.
func set_viewport_size(new_size: Vector2) -> void:
	if new_size.x <= MARGIN * 2.0 or new_size.y <= MARGIN * 2.0:
		return
	viewport_size = new_size
	_refit()


## Control-local pixel of a world point; infinite when it is behind the camera.
func project(point: Vector3) -> Vector2:
	var local := _current.affine_inverse() * point
	if local.z >= -0.001:
		return Vector2(INF, INF)
	return viewport_size / 2.0 + Vector2(local.x, -local.y) * _pixels_per_unit(-local.z)


## Pixels of one world unit at `depth` in front of the camera.
func _pixels_per_unit(depth: float) -> float:
	return viewport_size.y / 2.0 / (tan(deg_to_rad(FIELD_OF_VIEW) / 2.0) * depth)


func is_fitted() -> bool:
	return _fits(_camera_transform(_fit_distance, 0.0, DEFAULT_PITCH, Vector2.ZERO))


func orbit(delta_pixels: Vector2) -> void:
	yaw = wrapf(yaw - delta_pixels.x * ORBIT_DEGREES_PER_PIXEL, -180.0, 180.0)
	pitch = clampf(pitch + delta_pixels.y * ORBIT_DEGREES_PER_PIXEL, MIN_PITCH, MAX_PITCH)
	_apply()


func rotate_by(degrees: float) -> void:
	yaw = wrapf(yaw + degrees, -180.0, 180.0)
	_apply()


func tilt_by(degrees: float) -> void:
	pitch = clampf(pitch + degrees, MIN_PITCH, MAX_PITCH)
	_apply()


## Moves the pivot so the table follows the cursor by `delta_pixels`.
func pan_by(delta_pixels: Vector2) -> void:
	var per_pixel := 1.0 / _pixels_per_unit(_fit_distance * zoom)
	var right := Vector2(cos(deg_to_rad(yaw)), -sin(deg_to_rad(yaw)))
	var down := Vector2(sin(deg_to_rad(yaw)), cos(deg_to_rad(yaw)))
	var moved := right * delta_pixels.x + down * delta_pixels.y / sin(deg_to_rad(pitch))
	pan = (pan - moved * per_pixel).limit_length(MAX_PAN)
	_apply()


## `factor` below 1 moves closer.
func zoom_by(factor: float) -> void:
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	_apply()


func reset(animated: bool) -> void:
	if _tween != null:
		_tween.kill()
	if not animated:
		_set_view(0.0, DEFAULT_PITCH, 1.0, Vector2.ZERO)
		return
	var from := [yaw, pitch, zoom, pan]
	_tween = create_tween()
	_tween.tween_method(func(progress: float) -> void:
		_set_view(lerpf(from[0], 0.0, progress), lerpf(from[1], DEFAULT_PITCH, progress),
				lerpf(from[2], 1.0, progress), (from[3] as Vector2).lerp(Vector2.ZERO, progress)),
			0.0, 1.0, RESET_SECONDS)


func _set_view(new_yaw: float, new_pitch: float, new_zoom: float, new_pan: Vector2) -> void:
	yaw = new_yaw
	pitch = new_pitch
	zoom = new_zoom
	pan = new_pan
	_apply()


func _add_column(point: Vector2) -> void:
	_cloud.append(Vector3(point.x, 0.0, point.y))
	_cloud.append(Vector3(point.x, PlaceholderArt.PIECE_HEIGHT, point.y))


func _refit() -> void:
	if _cloud.is_empty():
		return
	var near := 1.0
	var far := MAX_FIT_DISTANCE
	for step in FIT_STEPS:
		var middle := (near + far) / 2.0
		if _fits(_camera_transform(middle, 0.0, DEFAULT_PITCH, Vector2.ZERO)):
			far = middle
		else:
			near = middle
	_fit_distance = far
	_apply()


func _fits(view: Transform3D) -> bool:
	var inner := Rect2(Vector2.ONE * MARGIN, viewport_size - Vector2.ONE * MARGIN * 2.0)
	var saved := _current
	_current = view
	var inside := _cloud.size() > 0
	for point in _cloud:
		inside = inside and inner.has_point(project(point))
	_current = saved
	return inside


func _camera_transform(distance: float, yaw_degrees: float, pitch_degrees: float, offset: Vector2) -> Transform3D:
	var pitch_radians := deg_to_rad(pitch_degrees)
	var direction := Vector3(0.0, sin(pitch_radians), cos(pitch_radians)).rotated(Vector3.UP, deg_to_rad(yaw_degrees))
	var pivot := _center + Vector3(offset.x, 0.0, offset.y)
	return Transform3D(Basis.looking_at(-direction, Vector3.UP), pivot + direction * distance)


func _apply() -> void:
	_current = _camera_transform(_fit_distance * zoom, yaw, pitch, pan)
	camera.transform = _current
