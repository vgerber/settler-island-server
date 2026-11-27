class_name PlaceholderArt
extends RefCounted
## Flat-coloured primitives that stand in for the clay kit. Every builder takes hex-unit positions (x, y become
## world x, z) and returns a node standing on the table; the art kit replaces this file by implementing the same calls.

## Height of the tile tops; markers, picking and the camera fit rely on it.
const SURFACE_HEIGHT := 0.2
const SEA_HEIGHT := -0.05
const PIECE_HEIGHT := 0.5
const ROBBER_OFFSET := Vector2(-0.5, 0.05)

static var _materials := {}


static func sea(bounds: Rect2) -> Node3D:
	var mesh := PlaneMesh.new()
	mesh.size = bounds.size * 4.0
	return _node(mesh, Palette.SEA, Vector3(bounds.get_center().x, SEA_HEIGHT, bounds.get_center().y))


static func tile(center: Vector2, resource: Variant, number: Variant) -> Node3D:
	var slab := CylinderMesh.new()
	slab.radial_segments = 6
	slab.rings = 1
	slab.top_radius = 0.97
	slab.bottom_radius = 0.97
	slab.height = SURFACE_HEIGHT - SEA_HEIGHT
	var color := Palette.DESERT if resource == null else Palette.resource_color(resource)
	var node := _node(slab, color, _world(center, (SURFACE_HEIGHT + SEA_HEIGHT) / 2.0))
	if number != null:
		node.add_child(_chip(int(number)))
	return node


## A port badge on the water with a plank to each of its two coast corners.
static func port(marker: Vector2, coast_corners: Array[Vector2], port_kind: SiPort) -> Node3D:
	var specific := port_kind as SiPortSpecific
	var color := Palette.CARD_STOCK if specific == null else Palette.resource_color(specific.value)
	var disc := CylinderMesh.new()
	disc.top_radius = BoardGeometry.PORT_RADIUS
	disc.bottom_radius = BoardGeometry.PORT_RADIUS
	disc.height = 0.1
	var node := _node(disc, color, _world(marker, SURFACE_HEIGHT))
	node.add_child(_label("3:1" if specific == null else "2:1", 0.06, Palette.INK, 40))
	for corner in coast_corners:
		var plank := road_piece(corner, marker, Palette.OUTLINE, 0.08)
		plank.position -= node.position
		node.add_child(plank)
	return node


static func road(seat: int, start: Vector2, end: Vector2) -> Node3D:
	return road_piece(start, end, Palette.SEAT_COLORS[seat], 0.14)


static func settlement(seat: int, point: Vector2) -> Node3D:
	var node := _node(BoxMesh.new(), Palette.SEAT_COLORS[seat], _world(point, SURFACE_HEIGHT + 0.12))
	(node.mesh as BoxMesh).size = Vector3(0.26, 0.24, 0.26)
	return node


static func city(seat: int, point: Vector2) -> Node3D:
	var base := BoxMesh.new()
	base.size = Vector3(0.42, 0.26, 0.3)
	var node := _node(base, Palette.SEAT_COLORS[seat], _world(point, SURFACE_HEIGHT + 0.13))
	var tower := BoxMesh.new()
	tower.size = Vector3(0.22, 0.3, 0.22)
	var top := _node(tower, Palette.SEAT_COLORS[seat].darkened(0.2), Vector3(0.0, 0.25, 0.0))
	node.add_child(top)
	return node


## The robber stands beside the number chip of its tile, given the tile's centre.
static func robber(tile_center: Vector2) -> Node3D:
	var body := CylinderMesh.new()
	body.top_radius = 0.08
	body.bottom_radius = 0.16
	body.height = PIECE_HEIGHT - 0.1
	return _node(body, Palette.ROBBER, _world(tile_center + ROBBER_OFFSET, SURFACE_HEIGHT + body.height / 2.0))


## A flat bar between two points of the table.
static func road_piece(start: Vector2, end: Vector2, color: Color, width: float) -> Node3D:
	var bar := BoxMesh.new()
	bar.size = Vector3(start.distance_to(end) * 0.8, 0.08, width)
	var node := _node(bar, color, _world((start + end) / 2.0, SURFACE_HEIGHT + 0.05))
	node.rotation.y = -(end - start).angle()
	return node


static func _chip(number: int) -> Node3D:
	var disc := CylinderMesh.new()
	disc.top_radius = 0.3
	disc.bottom_radius = 0.3
	disc.height = 0.06
	var chip := _node(disc, Palette.PARCHMENT, Vector3(0.0, SURFACE_HEIGHT - (SURFACE_HEIGHT + SEA_HEIGHT) / 2.0 + 0.03, 0.0))
	var hot := number == 6 or number == 8
	chip.add_child(_label(str(number), 0.04, Color("#B02A22") if hot else Palette.INK, 56))
	return chip


## Text lying flat `lift` above its parent's centre.
static func _label(text: String, lift: float, color: Color, font_size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.005
	label.modulate = color
	label.shaded = false
	label.rotation_degrees.x = -90.0
	label.position.y = lift
	return label


static func _node(mesh: Mesh, color: Color, position: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(color)
	node.position = position
	return node


static func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 1.0
		_materials[color] = material
	return _materials[color]


static func _world(point: Vector2, height: float) -> Vector3:
	return Vector3(point.x, height, point.y)
