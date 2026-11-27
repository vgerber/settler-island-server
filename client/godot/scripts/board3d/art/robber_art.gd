class_name RobberArt
extends RefCounted
## The robber: a soft dark clay pawn with a bulbous head and a pale collar so it reads on dark terrain.
## Origin at the base centre; stands about 0.4 tall. `ClayMaterials.robber()` gives it a cream rim.

const HEIGHT := 0.42

static var _mesh: ArrayMesh = null


static func robber() -> ArrayMesh:
	if _mesh == null:
		_mesh = builder().to_mesh()
	return _mesh


static func builder() -> ClayBuilder:
	var body := ClayPalette.mute(Palette.ROBBER)
	var collar := ClayPalette.mute(Palette.CREAM_MUTED)
	var result := ClayBuilder.new()
	var profile := PackedVector2Array(
		[
			Vector2(0.0, 0.0),
			Vector2(0.15, 0.0),
			Vector2(0.17, 0.025),
			Vector2(0.15, 0.05),
			Vector2(0.115, 0.1),
			Vector2(0.085, 0.17),
			Vector2(0.07, 0.24),
			Vector2(0.075, 0.27),
			Vector2(0.0, 0.28),
		]
	)
	result.add_lathe(profile, Transform3D.IDENTITY, body, 0.5, 20)
	var ring := PackedVector2Array([Vector2(0.062, 0.268), Vector2(0.09, 0.275), Vector2(0.09, 0.292), Vector2(0.06, 0.3)])
	result.add_lathe(ring, Transform3D.IDENTITY, collar, 0.8, 20)
	var head := Transform3D(Basis.from_scale(Vector3(0.1, 0.105, 0.1)), Vector3(0.0, 0.345, 0.0))
	result.add_sphere(head, body, 0.7, 18)
	return result
