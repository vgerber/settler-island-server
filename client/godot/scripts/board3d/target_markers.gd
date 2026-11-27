class_name TargetMarkers
extends Node3D
## Gold rings for the legal targets and the ghost piece of the hovered one. Unshaded, drawn over everything (no
## depth test) so tall pieces never hide a ring; a dark outline keeps the shape readable without the colour.

const GOLD := Color("#F2C14E")
const OUTLINE := Color("#231C17")
const LIFT := 0.04
const HOVER_SCALE := 1.3
const GHOST_ALPHA := 0.55

var _gold := _overlay_material(GOLD, 11)
var _outline := _overlay_material(OUTLINE, 10)
var _ghost_material := _overlay_material(Color.WHITE, 9)
var _rings: Dictionary = {}
var _board: SiBoard = null
var _geometry: BoardGeometry = null
var _ghost: Node3D = null


## Shows a ring for each target; `pulse` is the brightness, set again on each frame.
func show_targets(targets: Array[BoardTarget], board: SiBoard, geometry: BoardGeometry) -> void:
	_board = board
	_geometry = geometry
	for ring: Node3D in _rings.values():
		ring.queue_free()
		remove_child(ring)
	_rings.clear()
	for target in targets:
		var ring := _ring_for(target)
		_rings[target] = ring
		add_child(ring)


func set_pulse(pulse: float) -> void:
	_gold.albedo_color.a = pulse
	_outline.albedo_color.a = pulse


## Brightens the ring of `target` and shows the piece it would place in seat colour; null clears both.
func show_hover(target: BoardTarget, seat: int) -> void:
	for ring: Node3D in _rings.values():
		ring.scale = Vector3.ONE
	if _ghost != null:
		_ghost.queue_free()
		remove_child(_ghost)
		_ghost = null
	if target == null or not _rings.has(target):
		return
	(_rings[target] as Node3D).scale = Vector3.ONE * HOVER_SCALE
	_ghost = _ghost_for(target, seat)
	_ghost_material.albedo_color = Palette.SEAT_COLORS[seat]
	_ghost_material.albedo_color.a = GHOST_ALPHA
	_make_translucent(_ghost)
	add_child(_ghost)


func ring_count() -> int:
	return _rings.size()


func _ring_for(target: BoardTarget) -> Node3D:
	var ring := Node3D.new()
	ring.position = Picking.surface_point(target.point) + Vector3.UP * LIFT
	match target.kind:
		BoardTarget.Kind.CORNER:
			ring.add_child(_torus(0.15, 0.31, _outline))
			ring.add_child(_torus(0.19, 0.27, _gold))
		BoardTarget.Kind.EDGE:
			ring.rotation.y = -_edge_direction(target).angle()
			ring.add_child(_bar(Vector3(0.62, 0.02, 0.2), _outline))
			ring.add_child(_bar(Vector3(0.54, 0.03, 0.12), _gold))
		BoardTarget.Kind.TILE:
			ring.add_child(_torus(0.7, 0.86, _outline))
			ring.add_child(_torus(0.74, 0.82, _gold))
	return ring


## Edge targets hold only the midpoint; the edge runs between the two corners of the action's edge.
func _edge_direction(target: BoardTarget) -> Vector2:
	var corners := _board.edges[target.action.get("edge")].corners
	return _geometry.corner_points[corners[1]] - _geometry.corner_points[corners[0]]


func _ghost_for(target: BoardTarget, seat: int) -> Node3D:
	match target.kind:
		BoardTarget.Kind.TILE:
			return BoardArt.robber(target.point, false)
		BoardTarget.Kind.EDGE:
			var direction := _edge_direction(target)
			return BoardArt.road(seat, target.point - direction / 2.0, target.point + direction / 2.0, false)
		_:
			if target.action is SiActionBuildCity:
				return BoardArt.city(seat, target.point, false)
			return BoardArt.settlement(seat, target.point, false)


func _make_translucent(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = _ghost_material
	for child in node.get_children():
		_make_translucent(child)


func _torus(inner: float, outer: float, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 24
	mesh.ring_segments = 4
	return _instance(mesh, material, 0.5 * (outer - inner))


func _bar(size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _instance(mesh, material, 0.0)


func _instance(mesh: Mesh, material: StandardMaterial3D, squash: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A torus is as tall as its tube is thick; flatten it onto the table.
	if squash > 0.0:
		instance.scale.y = 0.05 / squash
	return instance


static func _overlay_material(color: Color, priority: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = priority
	return material
