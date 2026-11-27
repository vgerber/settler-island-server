class_name AwardArt
extends RefCounted
## The badges of the two awards: a gold six-sided medal, with a road plank on it for the longest road and crossed
## swords for the largest army. Low poly, vertex colours; they lie flat and fly over the table (`AwardBadges`).

const RADIUS := 0.24
const THICKNESS := 0.05

static var _meshes: Dictionary = {}


static func road() -> ArrayMesh:
	return _mesh("road", func(result: ClayBuilder) -> void:
		var plank := ClayPalette.WOOD_BROWN
		var top := THICKNESS
		for row in 3:
			var shade := [1.0, 0.85, 0.95][row]
			var offset := Vector3(0.0, top + 0.014, (row - 1) * 0.062)
			result.add_box(Transform3D(Basis.IDENTITY, offset), Vector3(0.15, 0.014, 0.027), ClayPalette.shade(plank, shade * 1.3), 0.8)
		for side in [-1.0, 1.0]:
			var tie := Vector3(side * 0.09, top + 0.03, 0.0)
			result.add_box(Transform3D(Basis.IDENTITY, tie), Vector3(0.016, 0.006, 0.105), ClayPalette.shade(plank, 0.9), 0.9))


static func army() -> ArrayMesh:
	return _mesh("army", func(result: ClayBuilder) -> void:
		var steel := Color("#C9CDD2")
		for sign in [-1.0, 1.0]:
			var turned := Basis(Vector3.UP, sign * PI / 4.0)
			var top := THICKNESS
			result.add_box(Transform3D(turned, Vector3(0.0, top + 0.01, 0.0) + turned * Vector3(0.03, 0.0, 0.0)), Vector3(0.125, 0.01, 0.017), steel, 0.85)
			result.add_box(Transform3D(turned, Vector3(0.0, top + 0.014, 0.0) + turned * Vector3(-0.085, 0.0, 0.0)), Vector3(0.012, 0.014, 0.05), ClayPalette.DARK_CLAY, 0.9)
			result.add_box(Transform3D(turned, Vector3(0.0, top + 0.012, 0.0) + turned * Vector3(-0.135, 0.0, 0.0)), Vector3(0.04, 0.011, 0.012), ClayPalette.WOOD_BROWN, 0.9))


static func _mesh(key: String, mark: Callable) -> ArrayMesh:
	if not _meshes.has(key):
		var result := ClayBuilder.new()
		var gold := ClayPalette.EAR_GOLD
		var medal := PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(RADIUS, 0.0), Vector2(RADIUS, THICKNESS * 0.7), Vector2(RADIUS - 0.03, THICKNESS + 0.014),
			Vector2(RADIUS - 0.06, THICKNESS), Vector2(0.0, THICKNESS),
		])
		result.add_lathe(medal, Transform3D.IDENTITY, gold, 0.8, 6)
		mark.call(result)
		_meshes[key] = result.to_mesh()
	return _meshes[key]
