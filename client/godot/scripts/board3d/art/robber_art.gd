class_name RobberArt
extends RefCounted
## The robber: a faceted dark clay pawn with a bulbous head and a pale collar so it reads on dark terrain.
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
	var profile := PackedVector2Array([Vector2(0.17, 0.0), Vector2(0.15, 0.05), Vector2(0.1, 0.12), Vector2(0.07, 0.25), Vector2(0.0, 0.27)])
	result.add_lathe(profile, Transform3D.IDENTITY, body, 0.5, 8)
	var ring := PackedVector2Array([Vector2(0.075, 0.255), Vector2(0.095, 0.285), Vector2(0.0, 0.29)])
	result.add_lathe(ring, Transform3D.IDENTITY, collar, 0.8, 8)
	var head := Transform3D(Basis.from_scale(Vector3(0.1, 0.105, 0.1)), Vector3(0.0, 0.345, 0.0))
	result.add_sphere(head, body, 0.7, 6)
	return result
