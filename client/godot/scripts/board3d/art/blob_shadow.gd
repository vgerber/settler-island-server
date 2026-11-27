class_name BlobShadow
extends RefCounted
## Soft contact shadow under a piece: a flat quad with a radial falloff (shaders/blob_shadow.gdshader). It needs
## no shadow map, so it is the shadow of the Compatibility look and also grounds pieces in Forward+. Lay it on
## the surface the piece stands on (the caller sets y; `LIFT` keeps it above the surface) and under the piece's
## node, so it follows hops and drops; scale the node for a growing shadow (the dice landing).

const SHADER_PATH := "res://shaders/blob_shadow.gdshader"
## Above the surface so the depth test passes; the shader does not write depth.
const LIFT := 0.004

static var _quad: QuadMesh = null
static var _materials: Dictionary = {}


## A shadow of `radius` (hex units) and darkness `strength` 0..1.
static func create(radius: float, strength := 0.38) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = "BlobShadow"
	instance.mesh = _unit_quad()
	instance.material_override = _material(strength)
	instance.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
	instance.position = Vector3(0.0, LIFT, 0.0)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func _unit_quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
		_quad.orientation = PlaneMesh.FACE_Y
	return _quad


static func _material(strength: float) -> ShaderMaterial:
	var key := snappedf(strength, 0.01)
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = load(SHADER_PATH)
		material.set_shader_parameter("strength", strength)
		material.render_priority = 1
		_materials[key] = material
	return _materials[key]
