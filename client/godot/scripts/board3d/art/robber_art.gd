class_name RobberArt
extends RefCounted
## The robber: a hooded, cloaked figure on a round base, in dark clay with a pale hem, belt and eyes so it reads
## on dark terrain. Origin at the base centre; stands about 0.43 tall, the face looks toward +z (the camera).
## `ClayMaterials.robber()` gives it a cream rim.

const HEIGHT := 0.43

static var _mesh: ArrayMesh = null


static func robber() -> ArrayMesh:
	if _mesh == null:
		_mesh = builder().to_mesh()
	return _mesh


static func builder() -> ClayBuilder:
	var cloth := ClayPalette.mute(Palette.ROBBER)
	var pale := ClayPalette.mute(Palette.CREAM_MUTED)
	var result := ClayBuilder.new()
	_add_base(result, ClayPalette.shade(cloth, 1.35))
	_add_cloak(result, cloth, pale)
	_add_hood(result, cloth, pale)
	_add_staff(result, ClayPalette.mute(Palette.PIER_TIE), pale)
	return result


static func _add_base(result: ClayBuilder, stone: Color) -> void:
	var plate := PackedVector2Array([Vector2(0.19, 0.0), Vector2(0.19, 0.018), Vector2(0.165, 0.032), Vector2(0.0, 0.032)])
	result.add_lathe(plate, Transform3D.IDENTITY, stone, 0.6, 8)


static func _add_cloak(result: ClayBuilder, cloth: Color, pale: Color) -> void:
	var cloak := PackedVector2Array([Vector2(0.15, 0.03), Vector2(0.125, 0.12), Vector2(0.085, 0.21), Vector2(0.09, 0.27), Vector2(0.0, 0.285)])
	result.add_lathe(cloak, Transform3D.IDENTITY, cloth, 0.55, 8)
	var hem := PackedVector2Array([Vector2(0.153, 0.03), Vector2(0.153, 0.05), Vector2(0.145, 0.055)])
	result.add_lathe(hem, Transform3D.IDENTITY, pale, 0.75, 8)
	var belt := PackedVector2Array([Vector2(0.108, 0.135), Vector2(0.108, 0.155), Vector2(0.1, 0.16)])
	result.add_lathe(belt, Transform3D.IDENTITY, ClayPalette.shade(pale, 0.8), 0.9, 8)
	var shoulders := PackedVector2Array([Vector2(0.1, 0.255), Vector2(0.105, 0.275), Vector2(0.07, 0.3)])
	result.add_lathe(shoulders, Transform3D.IDENTITY, ClayPalette.shade(cloth, 1.25), 0.85, 8)


## A round hood with a point leaning back, a dark face opening and two pale eyes.
static func _add_hood(result: ClayBuilder, cloth: Color, pale: Color) -> void:
	var head := Transform3D(Basis.from_scale(Vector3(0.105, 0.11, 0.105)), Vector3(0.0, 0.345, 0.0))
	result.add_sphere(head, ClayPalette.shade(cloth, 1.15), 0.75, 8)
	var tip_basis := Basis(Vector3.RIGHT, -0.5)
	var cone := PackedVector2Array([Vector2(0.085, 0.0), Vector2(0.05, 0.06), Vector2(0.0, 0.12)])
	result.add_lathe(cone, Transform3D(tip_basis, Vector3(0.0, 0.37, -0.01)), ClayPalette.shade(cloth, 1.15), 0.8, 8)
	var face := Transform3D(Basis.from_scale(Vector3(0.062, 0.07, 0.04)), Vector3(0.0, 0.335, 0.075))
	result.add_sphere(face, Color(0.05, 0.04, 0.05), 1.0, 6)
	for side in [-1.0, 1.0]:
		var eye := Transform3D(Basis.IDENTITY, Vector3(side * 0.024, 0.34, 0.108))
		result.add_box(eye, Vector3(0.011, 0.007, 0.004), pale, 1.0)


static func _add_staff(result: ClayBuilder, wood: Color, pale: Color) -> void:
	result.add_box(Transform3D(Basis.IDENTITY, Vector3(0.15, 0.2, 0.04)), Vector3(0.012, 0.2, 0.012), ClayPalette.shade(wood, 1.4), 0.7)
	result.add_sphere(Transform3D(Basis.from_scale(Vector3.ONE * 0.026), Vector3(0.15, 0.42, 0.04)), pale, 0.9, 6)
