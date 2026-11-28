class_name BoardArt
extends RefCounted
## Nodes of the table built from the clay kit (`scripts/board3d/art/`). Every builder takes hex-unit positions
## (2D x, y become world x, z) and returns a node standing on the table.

## Height of the tile tops; markers, picking and the camera fit rely on it.
const SURFACE_HEIGHT := HexSlabArt.HEIGHT
## Height the camera fit keeps in view above the table (the tallest pieces).
const PIECE_HEIGHT := 0.5
const ROBBER_OFFSET := Vector2(-0.5, 0.05)
const ROAD_SHADOW_RADIUS := 0.26
const HOUSE_SHADOW_RADIUS := 0.2
const SHADOW_STRENGTH := 0.4
## Seat stands sit this far outside the island bounds.
const STAND_GAP := 0.5


static func table() -> Node3D:
	return _mesh(TableArt.table(), ClayMaterials.table(), Vector3.ZERO)


## One MultiMesh of water hexes at `cells`.
static func water(cells: Array[Vector2]) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	# Colours are on too (all white): without them Compatibility feeds the custom data in place of the vertex colour.
	multi.use_colors = true
	multi.use_custom_data = true
	multi.mesh = WaterArt.hex()
	multi.instance_count = cells.size()
	var coast := WaterArt.coast(cells)
	for index in cells.size():
		multi.set_instance_transform(index, Transform3D(Basis.IDENTITY, _world(cells[index], 0.0)))
		# Custom data: land-edge bitmask and shoal level, read by water.gdshader.
		multi.set_instance_color(index, Color.WHITE)
		multi.set_instance_custom_data(index, Color(coast[index].x, coast[index].y, 0.0, 0.0))
	var instance := MultiMeshInstance3D.new()
	instance.name = "Water"
	instance.multimesh = multi
	instance.material_override = ClayMaterials.water()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func tile(coordinates: SiCubeCoordinates, center: Vector2, resource: Variant, number: Variant) -> Node3D:
	var terrain: String = HexSlabArt.DESERT if resource == null else str(resource)
	var node := _mesh(HexSlabArt.slab(terrain), ClayMaterials.terrain(), _world(center, 0.0))
	var top := Vector3(0.0, HexSlabArt.HEIGHT, 0.0)
	var props := _mesh(TerrainPropsArt.props(terrain, coordinates.q, coordinates.r), ClayMaterials.terrain(), top)
	props.name = "Props"
	node.add_child(props)
	if number != null:
		var chip := _mesh(ChipArt.chip(int(number)), ClayMaterials.stock(), top)
		chip.name = "Chip"
		node.add_child(chip)
	return node


## A pier from the coast edge between the two `coast_corners` out to the port `marker`, with its flag.
static func port(marker: Vector2, coast_corners: Array[Vector2], port_kind: SiPort) -> Node3D:
	var edge := (coast_corners[0] + coast_corners[1]) / 2.0
	var outward := (marker - edge).normalized()
	var node := Node3D.new()
	node.position = _world(edge, 0.0)
	var specific := port_kind as SiPortSpecific
	var resource := "" if specific == null else str(specific.value)
	var pier := _mesh(PortArt.pier(resource), ClayMaterials.terrain(), Vector3.ZERO)
	pier.rotation.y = atan2(-outward.y, outward.x)
	node.add_child(pier)
	var flag := PortArt.flag(3 if specific == null else 2, resource)
	var tip := outward * (PortArt.PIER_LENGTH - 0.08)
	# The flag is never rotated, so its text reads for the camera.
	node.add_child(_mesh(flag, ClayMaterials.terrain(), Vector3(tip.x, PortArt.DECK_HEIGHT, tip.y)))
	return node


static func road(seat: int, start: Vector2, end: Vector2, grounded := true) -> Node3D:
	var direction := end - start
	var node := _mesh(PieceArt.road(), ClayMaterials.piece(seat), _world((start + end) / 2.0, SURFACE_HEIGHT))
	node.rotation.y = atan2(-direction.y, direction.x)
	if grounded:
		node.add_child(BlobShadow.create(ROAD_SHADOW_RADIUS, SHADOW_STRENGTH))
	return node


static func settlement(seat: int, point: Vector2, grounded := true) -> Node3D:
	return _house(PieceArt.settlement(), seat, point, grounded)


static func city(seat: int, point: Vector2, grounded := true) -> Node3D:
	return _house(PieceArt.city(), seat, point, grounded)


## The robber stands beside the number chip of its tile, given the tile's centre.
static func robber(tile_center: Vector2, grounded := true) -> Node3D:
	var node := _mesh(RobberArt.robber(), ClayMaterials.robber(), _world(tile_center + ROBBER_OFFSET, SURFACE_HEIGHT))
	if grounded:
		node.add_child(BlobShadow.create(0.22, 0.45))
	return node


## A seat stand at `position` (turned by `yaw`): wooden tray with the seat colour inlaid, lit or dimmed; the plum
## seat gets an ivory rim.
static func stand(seat: int, position: Vector3, yaw: float, lit: bool) -> Node3D:
	var node := _mesh(TableArt.seat_stand_base(), ClayMaterials.terrain(), position)
	node.rotation.y = yaw
	if seat % Palette.SEAT_COLORS.size() == Palette.DARK_SEAT:
		node.add_child(_mesh(TableArt.seat_stand_rim(), ClayMaterials.terrain(), Vector3.ZERO))
	node.add_child(_mesh(TableArt.seat_stand_inlay(), ClayMaterials.stand(seat, lit), Vector3.ZERO))
	return node


## Where the stand of `seat` sits around the island `bounds`: front, left, back, right; the yaw turns the long side.
static func stand_placement(seat: int, bounds: Rect2) -> Dictionary:
	var center := bounds.get_center()
	var front := Vector3(center.x, 0.0, bounds.end.y + STAND_GAP)
	var back := Vector3(center.x, 0.0, bounds.position.y - STAND_GAP)
	var left := Vector3(bounds.position.x - STAND_GAP - 0.4, 0.0, center.y)
	var right := Vector3(bounds.end.x + STAND_GAP + 0.4, 0.0, center.y)
	var placements := [[front, 0.0], [left, PI / 2.0], [back, 0.0], [right, PI / 2.0]]
	var placement: Array = placements[seat % placements.size()]
	return {"position": placement[0], "yaw": placement[1]}


static func _house(mesh: Mesh, seat: int, point: Vector2, grounded: bool) -> Node3D:
	var node := _mesh(mesh, ClayMaterials.piece(seat), _world(point, SURFACE_HEIGHT))
	if grounded:
		node.add_child(BlobShadow.create(HOUSE_SHADOW_RADIUS, SHADOW_STRENGTH))
	return node


static func _mesh(mesh: Mesh, material: Material, position: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = position
	return node


static func _world(point: Vector2, height: float) -> Vector3:
	return Vector3(point.x, height, point.y)
