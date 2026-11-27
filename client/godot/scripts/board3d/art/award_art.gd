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
		result.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, THICKNESS + 0.015, 0.0)), Vector3(0.17, 0.015, 0.045), plank, 0.8))


static func army() -> ArrayMesh:
	return _mesh("army", func(result: ClayBuilder) -> void:
		for sign in [-1.0, 1.0]:
			var turned := Basis(Vector3.UP, sign * PI / 4.0)
			result.add_box(Transform3D(turned, Vector3(0.0, THICKNESS + 0.015, 0.0)), Vector3(0.17, 0.015, 0.03), ClayPalette.DARK_CLAY, 0.8))


static func _mesh(key: String, mark: Callable) -> ArrayMesh:
	if not _meshes.has(key):
		var result := ClayBuilder.new()
		var gold := ClayPalette.EAR_GOLD
		var profile := PackedVector2Array([Vector2(0.0, 0.0), Vector2(RADIUS, 0.0), Vector2(RADIUS, THICKNESS), Vector2(0.0, THICKNESS)])
		result.add_lathe(profile, Transform3D.IDENTITY, gold, 0.8, 6)
		mark.call(result)
		_meshes[key] = result.to_mesh()
	return _meshes[key]
