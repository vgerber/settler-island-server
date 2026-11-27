class_name WinCelebration
extends MotionLayer
## The end of a game: the stand of the winner rises and a handful of flat low poly confetti pieces fly up from it
## and fall over the table. The pieces are created once and reused; `BoardScene` keeps the winner's stand raised
## after the commit, so nothing here has to survive it.

const CONFETTI := 24
const RISE_SECONDS := 0.5
const CONFETTI_SECONDS := 2.0
const LAUNCH_SPEED := 3.2
const GRAVITY := 4.0
const SPREAD := 1.2
const PIECE_SIZE := Vector3(0.07, 0.012, 0.05)

var scene: BoardScene = null
var _pieces: Array[MeshInstance3D] = []
var _launch := Vector3.ZERO


func _init() -> void:
	name = "WinCelebration"
	var shape := BoxMesh.new()
	shape.size = PIECE_SIZE
	var colors: Array[Color] = [ClayPalette.seat(0), ClayPalette.seat(1), ClayPalette.seat(2), ClayPalette.EAR_GOLD]
	for index in CONFETTI:
		var piece := MeshInstance3D.new()
		piece.mesh = shape
		piece.material_override = _unshaded(colors[index % colors.size()])
		piece.visible = false
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pieces.append(piece)
		add_child(piece)


## Confetti pieces flying now, for tests.
func confetti_in_air() -> int:
	return _pieces.filter(func(piece: MeshInstance3D) -> bool: return piece.visible).size()


func finish_all() -> void:
	super.finish_all()
	for piece in _pieces:
		piece.visible = false


func win(event: SiEventGameWon) -> void:
	finish_all()
	var stand := scene.stand_node(event.seat)
	if stand == null:
		return
	_launch = layout.seat_point(event.seat)
	var tween := _tween()
	tween.tween_method(_raise.bind(event.seat), stand.position.y, BoardScene.WIN_RAISE, RISE_SECONDS)
	var fall := _tween()
	fall.tween_method(_scatter, 0.0, CONFETTI_SECONDS, CONFETTI_SECONDS)
	fall.tween_callback(finish_all)


func _raise(height: float, seat: int) -> void:
	var stand := scene.stand_node(seat)
	if stand != null:
		stand.position.y = height


## The pieces at `seconds`: thrown up in a fan around the stand, each turning on its own, falling to the table.
func _scatter(seconds: float) -> void:
	for index in _pieces.size():
		var salt := float(index) + 1.0
		var angle := fposmod(sin(salt * 12.9898) * 43758.5453, 1.0) * TAU
		var power := 0.4 + fposmod(sin(salt * 78.233) * 12345.678, 1.0) * 0.6
		var velocity := Vector3(cos(angle) * SPREAD * power, LAUNCH_SPEED * (0.6 + 0.4 * power), sin(angle) * SPREAD * power)
		var position := _launch + velocity * seconds - Vector3(0.0, GRAVITY * seconds * seconds / 2.0, 0.0)
		var piece := _pieces[index]
		piece.visible = position.y > BoardArt.SURFACE_HEIGHT
		piece.position = position
		piece.rotation = Vector3(salt * 1.3, salt * 2.1, salt * 0.7) * seconds * 3.0


static func _unshaded(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
