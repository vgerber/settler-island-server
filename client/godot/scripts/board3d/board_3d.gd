class_name Board3D
extends BoardView
## The island as a 3D table inside the board slot (doc/design/3d-interaction.md). It owns all input and picking
## itself: left click acts through the `EventPlayer` like `Board`, the camera answers to right drag (orbit), middle
## drag or shift + right drag (pan), wheel and pinch (zoom), Home (reset). The scene makes itself equal to
## `shown_view` on every commit and never needs an event.

## A right or middle drag shorter than this is a click, in pixels.
const DRAG_THRESHOLD := 6.0
const WHEEL_ZOOM := 0.9
const KEY_ROTATE_DEGREES := 15.0
const KEY_TILT_DEGREES := 5.0
const KEY_PAN_PIXELS := 40.0
const STILL_PULSE := 0.8

var camera_rig := CameraRig.new()
var scene := BoardScene.new()
var markers := TargetMarkers.new()
var motion := BoardMotion.new()

var _viewport := SubViewport.new()
var _picking := Picking.new(camera_rig)
var _hovered: BoardTarget = null
var _pulse_time := 0.0
var _drag_button := MOUSE_BUTTON_NONE
var _drag_distance := 0.0


func _ready() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(_viewport)
	_viewport.add_child(scene)
	_viewport.add_child(motion)
	_viewport.add_child(markers)
	_viewport.add_child(camera_rig)
	add_child(_reset_button())
	resized.connect(_on_resized)
	mouse_exited.connect(func() -> void: _set_hovered(null))
	set_process(false)


func _exit_tree() -> void:
	if is_instance_valid(player):
		motion.unbind()


func _process(delta: float) -> void:
	_pulse_time += delta
	var pulse := 0.775 + 0.225 * sin(_pulse_time * TAU * 0.8) if player.animated() else STILL_PULSE
	markers.set_pulse(pulse)
	scene.set_pulse(pulse)


func bind(event_player: EventPlayer) -> void:
	player = event_player
	player.committed.connect(_sync)
	motion.bind(player, scene, camera_rig, self)
	_sync()


func set_target_filter(kinds: Array[Script]) -> void:
	_filter = kinds
	if geometry != null:
		_sync()


func screen_point(target: BoardTarget) -> Vector2:
	return get_global_transform_with_canvas() * _picking.screen_point(target)


## The target under a pixel of this control, null when there is none.
func target_at(pixel: Vector2) -> BoardTarget:
	return _picking.pick(_targets, pixel)


## Makes the scene equal to the shown view; running it twice on the same view changes nothing.
func _sync() -> void:
	var board := player.shown_view.board
	if geometry == null or geometry.corner_points.size() != board.corners.size():
		geometry = BoardGeometry.new(board)
		camera_rig.set_viewport_size(size)
		camera_rig.frame(geometry)
	scene.build(board, geometry)
	scene.sync(board, geometry)
	motion.commit(geometry)
	scene.sync_stands(player.shown_view, geometry)
	_collect_targets()
	markers.show_targets(_targets, board, geometry)
	_update_hover()
	set_process(not _targets.is_empty() or scene.has_pulsing_stands())


func _on_resized() -> void:
	camera_rig.set_viewport_size(size)
	_update_hover()


func _update_hover() -> void:
	var inside := is_visible_in_tree() and Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position())
	_set_hovered(target_at(get_local_mouse_position()) if inside else null)


func _set_hovered(target: BoardTarget) -> void:
	if target == _hovered:
		return
	_hovered = target
	mouse_default_cursor_shape = Control.CURSOR_ARROW if target == null else Control.CURSOR_POINTING_HAND
	markers.show_hover(target, player.seat if player != null else 0)


func _reset_button() -> Button:
	var button := Button.new()
	button.name = "ResetViewButton"
	button.text = "Reset view"
	button.tooltip_text = "Reset the camera (Home)"
	button.custom_minimum_size = Vector2(40.0, 40.0)
	button.position = Vector2(8.0, 8.0)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_reset_camera)
	return button


func _reset_camera() -> void:
	camera_rig.reset(player != null and player.animated())
	_update_hover()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_on_motion(event as InputEventMouseMotion)
	elif event is InputEventMouseButton:
		_on_button(event as InputEventMouseButton)
	elif event is InputEventMagnifyGesture:
		camera_rig.zoom_by(1.0 / (event as InputEventMagnifyGesture).factor)
		_update_hover()
	elif event is InputEventPanGesture:
		_on_pan_gesture(event as InputEventPanGesture)


func _on_motion(motion: InputEventMouseMotion) -> void:
	if _drag_button == MOUSE_BUTTON_NONE:
		_set_hovered(target_at(motion.position))
		return
	_drag_distance += motion.relative.length()
	if _drag_distance <= DRAG_THRESHOLD:
		return
	if _drag_button == MOUSE_BUTTON_MIDDLE or motion.shift_pressed:
		camera_rig.pan_by(motion.relative)
	else:
		camera_rig.orbit(motion.relative)
	_update_hover()


func _on_button(button: InputEventMouseButton) -> void:
	if not button.pressed:
		if button.button_index == _drag_button:
			_drag_button = MOUSE_BUTTON_NONE
		return
	match button.button_index:
		MOUSE_BUTTON_LEFT:
			_click(button.position)
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			_drag_button = button.button_index
			_drag_distance = 0.0
		MOUSE_BUTTON_WHEEL_UP:
			camera_rig.zoom_by(WHEEL_ZOOM)
			_update_hover()
		MOUSE_BUTTON_WHEEL_DOWN:
			camera_rig.zoom_by(1.0 / WHEEL_ZOOM)
			_update_hover()


func _click(pixel: Vector2) -> void:
	if player == null or geometry == null:
		return
	var target := target_at(pixel)
	if target == null:
		return
	accept_event()
	player.act(target.action)


func _on_pan_gesture(gesture: InputEventPanGesture) -> void:
	if gesture.shift_pressed:
		camera_rig.pan_by(-gesture.delta * KEY_PAN_PIXELS)
	else:
		camera_rig.orbit(gesture.delta * KEY_PAN_PIXELS)
	_update_hover()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or not is_visible_in_tree() or _typing():
		return
	if not _camera_key(key):
		return
	get_viewport().set_input_as_handled()
	_update_hover()


func _typing() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit


## Applies the camera shortcut of `key`; false when the key is none.
func _camera_key(key: InputEventKey) -> bool:
	if key.shift_pressed and _pan_key(key):
		return true
	match key.keycode:
		KEY_HOME:
			_reset_camera()
		KEY_Q:
			camera_rig.rotate_by(-KEY_ROTATE_DEGREES)
		KEY_E:
			camera_rig.rotate_by(KEY_ROTATE_DEGREES)
		KEY_PAGEUP:
			camera_rig.tilt_by(KEY_TILT_DEGREES)
		KEY_PAGEDOWN:
			camera_rig.tilt_by(-KEY_TILT_DEGREES)
		KEY_EQUAL, KEY_PLUS:
			camera_rig.zoom_by(WHEEL_ZOOM)
		KEY_MINUS:
			camera_rig.zoom_by(1.0 / WHEEL_ZOOM)
		_:
			return false
	return true


func _pan_key(key: InputEventKey) -> bool:
	var step := {KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT, KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN}
	if not step.has(key.keycode):
		return false
	camera_rig.pan_by(step[key.keycode] * KEY_PAN_PIXELS)
	return true
