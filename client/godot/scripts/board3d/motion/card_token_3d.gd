class_name CardToken3D
extends Node3D
## One pooled flying card: two flat quads, the face up and the back down. `show_face` takes a resource index, or -1
## for the back, so a token of a hidden card never holds what the viewer may not know.

const SIZE := Vector2(0.5, 0.7)
const BACK_COLOR := Color("#3B3340")

const DEV_COLORS := {
	"Knight": Color("#8E3B3B"),
	"RoadBuilding": Color("#8A6A3E"),
	"YearOfPlenty": Color("#5E8F4A"),
	"Monopoly": Color("#6B4E8F"),
	"VictoryPoint": Color("#D9B34A"),
}

static var _plane: PlaneMesh = null
static var _materials: Dictionary = {}

var in_use := false
var _top := MeshInstance3D.new()


func _init() -> void:
	visible = false
	_top.mesh = _quad()
	add_child(_top)
	var bottom := MeshInstance3D.new()
	bottom.mesh = _quad()
	bottom.material_override = _material(BACK_COLOR)
	bottom.rotation.x = PI
	bottom.position.y = -0.004
	add_child(bottom)


func show_face(face: int) -> void:
	_top.material_override = _material(Palette.resource_color(SiResource.VALUES[face]) if face >= 0 else BACK_COLOR)


## The face of a played development card, a colour per kind.
func show_dev(card: String) -> void:
	_top.material_override = _material(DEV_COLORS.get(card, BACK_COLOR))


func release() -> void:
	visible = false
	in_use = false
	transform = Transform3D.IDENTITY


static func _quad() -> PlaneMesh:
	if _plane == null:
		_plane = PlaneMesh.new()
		_plane.size = SIZE
	return _plane


static func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 1.0
		_materials[color] = material
	return _materials[color]
