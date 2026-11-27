class_name PieceMotion
extends MotionLayer
## Pieces arriving: settlement and city drops, roads growing, the robber hopping. The moving piece is a ghost under
## this node; the static pieces of `BoardScene` change only at commit, where `finish_all` frees every ghost in the
## same call, so there is never a double piece. Static pieces a ghost replaces are hidden while it plays.

const DROP_HEIGHT := 0.7
const DROP_SECONDS := 0.23
const SQUASH_SECONDS := 0.06
const ROAD_SECONDS := 0.25
const ROAD_LIFT := 0.08
const CITY_SECONDS := 0.4
const CITY_SINK := 0.3
const HOP_LIFT := 0.4
const HOP_APEX := 0.3
const LIFT_SECONDS := 0.12
const ARC_SECONDS := 0.3
const FLASH_SCALE := 1.08
const FLASH_ALPHA := 0.7
const PUFFS := 6
const PUFF_SECONDS := 0.3
const PUFF_RADIUS := 0.05
const PUFF_TRAVEL := 0.25

var scene: BoardScene = null
var _ghosts: Array[Node3D] = []
var _hidden: Array[Node3D] = []
var _puff_mesh: SphereMesh = null
var _puff_material: StandardMaterial3D = null


func _init() -> void:
	name = "Ghosts"


## Ghosts alive now, for tests.
func ghost_count() -> int:
	return _ghosts.size()


func finish_all() -> void:
	super.finish_all()
	for ghost in _ghosts:
		ghost.queue_free()
		remove_child(ghost)
	_ghosts.clear()
	for node in _hidden:
		if is_instance_valid(node):
			node.visible = true
	_hidden.clear()


func settlement(event: SiEventSettlementPlaced) -> void:
	var rest := layout.corner(event.corner)
	var node := _ghost(PieceArt.settlement(), ClayMaterials.piece(event.seat), rest + Vector3(0.0, DROP_HEIGHT, 0.0))
	node.scale = Vector3.ONE * 1.25
	var tween := _tween()
	tween.tween_property(node, "position", rest, DROP_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(node, "scale", Vector3.ONE, DROP_SECONDS)
	tween.tween_callback(_dust.bind(rest))
	tween.tween_property(node, "scale", Vector3(1.0, 0.85, 1.0), SQUASH_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", Vector3.ONE, SQUASH_SECONDS)


func road(event: SiEventRoadPlaced) -> void:
	var edge := player.shown_view.board.edges[event.edge]
	var start := _network_end(event.seat, edge)
	var finish: int = edge.corners[1] if edge.corners[0] == start else edge.corners[0]
	var direction := layout.geometry.corner_points[finish] - layout.geometry.corner_points[start]
	var root := Node3D.new()
	root.position = layout.corner(start)
	root.rotation.y = atan2(-direction.y, direction.x)
	root.scale.x = 0.01
	var mesh := MeshInstance3D.new()
	mesh.mesh = PieceArt.road()
	mesh.material_override = ClayMaterials.piece(event.seat)
	mesh.position.x = direction.length() / 2.0
	root.add_child(mesh)
	_adopt(root)
	var tween := _tween()
	tween.tween_property(root, "scale:x", 1.0, ROAD_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_method(_lift.bind(mesh), 0.0, 1.0, ROAD_SECONDS)
	tween.tween_callback(_dust.bind(layout.corner(finish)))


func city(event: SiEventCityBuilt) -> void:
	var rest := layout.corner(event.corner)
	var material := ClayMaterials.piece(event.seat)
	_hide(scene.node_of("c%d" % event.corner))
	var old := _ghost(PieceArt.settlement(), material, rest)
	var tower := _ghost(PieceArt.city(), material, rest - Vector3(0.0, CITY_SINK, 0.0))
	var tween := _tween()
	tween.tween_property(tower, "position", rest, CITY_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(old, "scale", Vector3(1.15, 0.01, 1.15), CITY_SECONDS * 0.5)
	var flash := _flash_material(event.seat)
	var glow := _ghost(PieceArt.city(), flash, rest)
	glow.scale = Vector3.ONE * FLASH_SCALE
	tween.parallel().tween_property(flash, "albedo_color:a", 0.0, CITY_SECONDS).set_trans(Tween.TRANS_QUAD)


func robber(event: SiEventRobberMoved) -> void:
	var from := layout.robber(player.shown_view.board.robber)
	var to := layout.robber(event.tile)
	_hide(scene.node_of("robber"))
	var node := _ghost(RobberArt.robber(), ClayMaterials.robber(), from)
	var tween := _tween()
	tween.tween_property(node, "position:y", from.y + HOP_LIFT, LIFT_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_method(_hop.bind(node, from + Vector3(0.0, HOP_LIFT, 0.0), to), 0.0, 1.0, ARC_SECONDS)
	tween.tween_property(node, "scale", Vector3(1.0, 0.9, 1.0), SQUASH_SECONDS).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", Vector3.ONE, SQUASH_SECONDS)


## A seat-coloured, light and see-through coat that fades out over the rising city.
func _flash_material(seat: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(ClayPalette.seat(seat).lightened(0.5), FLASH_ALPHA)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _hop(progress: float, node: Node3D, from: Vector3, to: Vector3) -> void:
	var flat := from.lerp(to, smoothstep(0.0, 1.0, progress))
	node.position = Vector3(flat.x, flat.y + HOP_APEX * sin(progress * PI), flat.z)


func _lift(progress: float, mesh: MeshInstance3D) -> void:
	mesh.position.y = ROAD_LIFT * sin(progress * PI)


## The corner of the edge that touches the seat's network (a building or another road), else the first.
func _network_end(seat: int, edge: SiEdge) -> int:
	var board := player.shown_view.board
	for corner: int in edge.corners:
		var building := board.buildings[corner]
		if building != null and building.seat == seat:
			return corner
		for other: int in board.corners[corner].edges:
			if board.roads[other] != null and int(board.roads[other]) == seat:
				return corner
	return edge.corners[0]


func _ghost(mesh: Mesh, material: Material, position: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = position
	_adopt(node)
	return node


func _adopt(node: Node3D) -> void:
	add_child(node)
	_ghosts.append(node)


func _hide(node: Node3D) -> void:
	if node == null:
		return
	node.visible = false
	_hidden.append(node)


## A ring of low poly puffs that drift outwards and shrink away.
func _dust(point: Vector3) -> void:
	var tween := _tween()
	tween.set_parallel(true)
	for index in PUFFS:
		var angle := TAU * index / PUFFS
		var puff := MeshInstance3D.new()
		puff.mesh = _puff_shape()
		puff.material_override = _puff_look()
		puff.position = point + Vector3(0.0, PUFF_RADIUS, 0.0)
		_adopt(puff)
		var end := puff.position + Vector3(cos(angle), 0.0, sin(angle)) * PUFF_TRAVEL
		tween.tween_property(puff, "position", end, PUFF_SECONDS)
		tween.tween_property(puff, "scale", Vector3.ONE * 0.05, PUFF_SECONDS)


func _puff_shape() -> SphereMesh:
	if _puff_mesh == null:
		_puff_mesh = SphereMesh.new()
		_puff_mesh.radius = PUFF_RADIUS
		_puff_mesh.height = PUFF_RADIUS * 2.0
		_puff_mesh.radial_segments = 5
		_puff_mesh.rings = 3
	return _puff_mesh


func _puff_look() -> StandardMaterial3D:
	if _puff_material == null:
		_puff_material = StandardMaterial3D.new()
		_puff_material.albedo_color = Palette.CREAM_MUTED
		_puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _puff_material
