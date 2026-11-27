class_name DiceTray
extends MotionLayer
## The dice and their tray at the near table edge. A throw is scripted, not simulated: the spin term shrinks to the
## identity at the end, so the dice always land on the server's faces (doc/design/3d-motion.md).

const LIFT_MILLISECONDS := 120.0
const CONTACT_MILLISECONDS := 480.0
const REBOUND_MILLISECONDS := 620.0
const TOTAL_MILLISECONDS := 700.0
const LIFT_HEIGHT := 0.6
const APEX_BONUS := 0.2
const REBOUND_HEIGHT := 0.12
const REBOUND_SLIDE := 0.03
const WOBBLE_RADIANS := 0.035
const EXTRA_TURNS := 2.5
const DIE_SPACING := 0.5
const TRAY_THICKNESS := 0.04
const SHADOW_RADIUS := 0.2

var _tray := MeshInstance3D.new()
var _dice: Array[Node3D] = []
var _meshes: Array[MeshInstance3D] = []
var _shadows: Array[MeshInstance3D] = []
var _rolls := 0
var _last: Array[Dictionary] = []


func _init() -> void:
	name = "DiceTray"
	visible = false
	var plate := BoxMesh.new()
	plate.size = Vector3(TableLayout.TRAY_SIZE.x, TRAY_THICKNESS, TableLayout.TRAY_SIZE.y)
	_tray.mesh = plate
	var felt := StandardMaterial3D.new()
	felt.albedo_color = Palette.SEA.darkened(0.55)
	felt.roughness = 1.0
	_tray.material_override = felt
	add_child(_tray)
	for index in 2:
		var die := Node3D.new()
		var mesh := MeshInstance3D.new()
		mesh.mesh = DieArt.die()
		mesh.material_override = ClayMaterials.stock()
		die.add_child(mesh)
		var shadow := BlobShadow.create(SHADOW_RADIUS)
		die.add_child(shadow)
		add_child(die)
		_dice.append(die)
		_meshes.append(mesh)
		_shadows.append(shadow)


## Places the tray for a layout; a new game hides the dice.
func place(new_layout: TableLayout, new_game: bool) -> void:
	layout = new_layout
	_tray.position = layout.tray_center() - Vector3(0.0, TRAY_THICKNESS / 2.0, 0.0)
	if new_game:
		_last.clear()
		visible = false


## The value on the top face of die `index` (for tests).
func top_value(index: int) -> int:
	var up := _meshes[index].basis.inverse() * Vector3.UP
	for value: int in DieArt.FACE_NORMALS:
		if (DieArt.FACE_NORMALS[value] as Vector3).dot(up) > 0.999:
			return value
	return 0


## Rolls the dice for `event`; without `animated` they appear at rest on their faces and nothing moves.
func roll(event: SiEventDiceRolled, animated: bool) -> void:
	finish_all()
	_rolls += 1
	_last.clear()
	for index in 2:
		_last.append(_plan(index, event.first if index == 0 else event.second, event.seat))
	visible = true
	if not animated:
		_snap()
		return
	var tween := _tween()
	tween.tween_callback(player.play_sound.bind(&"sfx_dice_shake"))
	tween.tween_method(_pose, 0.0, TOTAL_MILLISECONDS, TOTAL_MILLISECONDS / 1000.0)
	var contact := &"sfx_roll_seven" if event.first + event.second == 7 else &"sfx_dice_land"
	tween.parallel().tween_callback(player.play_sound.bind(contact)).set_delay(CONTACT_MILLISECONDS / 1000.0)
	tween.tween_callback(_snap)


func finish_all() -> void:
	super.finish_all()
	_snap()


## Start, landing, spin axis and final orientation of a die; yaw and axis come from the roll counter, so replays match.
func _plan(index: int, value: int, seat: int) -> Dictionary:
	var salt := float(_rolls * 2 + index)
	var yaw := fposmod(sin(salt * 12.9898) * 43758.5453, 1.0) * TAU
	var axis := Vector3(sin(salt * 3.1), 0.6, cos(salt * 1.7)).normalized()
	var land := layout.tray_center() + Vector3((index - 0.5) * DIE_SPACING, DieArt.HALF, 0.0)
	var start := layout.seat_point(seat) + Vector3((index - 0.5) * 0.2, DieArt.HALF, 0.0)
	return {"start": start, "land": land, "axis": axis, "final": DieArt.orientation(value, yaw)}


func _snap() -> void:
	for index in _last.size():
		_set_die(index, _last[index]["land"], _last[index]["final"])
		_shadows[index].scale = Vector3(SHADOW_RADIUS * 2.0, 1.0, SHADOW_RADIUS * 2.0)


func _pose(milliseconds: float) -> void:
	for index in _last.size():
		var plan := _last[index]
		var position := _position(plan, milliseconds)
		var spin := Basis(plan["axis"], TAU * EXTRA_TURNS * _spin_left(milliseconds))
		var wobble := Basis(Vector3.RIGHT, _wobble(milliseconds))
		_set_die(index, position, wobble * spin * (plan["final"] as Basis))
		var height := position.y - (plan["land"] as Vector3).y
		var width := SHADOW_RADIUS * 2.0 * clampf(1.2 - height, 0.4, 1.0)
		_shadows[index].scale = Vector3(width, 1.0, width)


## 1 at the throw, 0 from first contact on.
func _spin_left(milliseconds: float) -> float:
	var progress := clampf(milliseconds / CONTACT_MILLISECONDS, 0.0, 1.0)
	return (1.0 - progress) * (1.0 - progress)


func _wobble(milliseconds: float) -> float:
	if milliseconds < REBOUND_MILLISECONDS:
		return 0.0
	var progress := (milliseconds - REBOUND_MILLISECONDS) / (TOTAL_MILLISECONDS - REBOUND_MILLISECONDS)
	return WOBBLE_RADIANS * (1.0 - progress) * sin(progress * TAU * 2.0)


func _position(plan: Dictionary, milliseconds: float) -> Vector3:
	var start: Vector3 = plan["start"]
	var land: Vector3 = plan["land"]
	if milliseconds < LIFT_MILLISECONDS:
		var lift := sin(milliseconds / LIFT_MILLISECONDS * PI / 2.0)
		return start + Vector3(0.0, LIFT_HEIGHT * lift, 0.0)
	if milliseconds < CONTACT_MILLISECONDS:
		var progress := (milliseconds - LIFT_MILLISECONDS) / (CONTACT_MILLISECONDS - LIFT_MILLISECONDS)
		var flat := start.lerp(land, smoothstep(0.0, 1.0, progress))
		var height := lerpf(start.y + LIFT_HEIGHT, land.y, progress * progress) + APEX_BONUS * sin(progress * PI)
		return Vector3(flat.x, height, flat.z)
	var rebound := clampf((milliseconds - CONTACT_MILLISECONDS) / (REBOUND_MILLISECONDS - CONTACT_MILLISECONDS), 0.0, 1.0)
	var arc := sin(rebound * PI)
	return land + Vector3(REBOUND_SLIDE * arc, REBOUND_HEIGHT * arc, 0.0)


func _set_die(index: int, position: Vector3, basis: Basis) -> void:
	_dice[index].position = position
	_meshes[index].basis = basis
	var land: Vector3 = _last[index]["land"]
	_shadows[index].position = Vector3(0.0, land.y - position.y + BlobShadow.LIFT, 0.0)
