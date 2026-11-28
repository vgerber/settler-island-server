extends SceneTree
## Runs inside a copy of the game project: every clay kit builder returns a non-empty mesh, props depend only on the
## tile coordinates (and stay clear of the chip and the tile edge), the number chip colours 6 and 8 as hot, and the
## dice face table turns every value to the top with exactly that many pips on that face.
## Usage: godot --headless --path <copy of client/godot> -s clay_kit_test.gd

const PROP_RING_LIMIT := 0.86
## Low poly: no mesh of the kit exceeds its triangle budget (the lead's rule: faceted, few segments).
const BUDGET_SLAB := 600
const BUDGET_PROPS := 2700 # straight wheat rows (2.6k) are the costliest tile; 19 tiles stay near 24k triangles
const BUDGET_CHIP := 400
const BUDGET_PIECE := 700
const BUDGET_ROBBER := 600
const BUDGET_DIE := 300
const BUDGET_PORT := 900
const BUDGET_TABLE := 1500
const BUDGET_WATER := 200
const BUDGET_TILE := 3100
const YAWS := [0.0, 0.7, 2.1, -1.3]

var _failures: PackedStringArray = []


func _init() -> void:
	_check_meshes_are_not_empty()
	_check_props_are_deterministic()
	_check_props_stay_on_the_tile()
	_check_triangle_budgets()
	_check_flat_shading()
	_check_water_cells()
	_check_hot_numbers()
	_check_dice_faces()
	if _failures.is_empty():
		SiTestSupport.finish(self, 0, "CLAY_KIT_OK")
		return
	SiTestSupport.finish(self, 1, "CLAY_KIT_FAILED %s" % "; ".join(_failures))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_mesh(mesh: ArrayMesh, label: String) -> void:
	_expect(mesh != null and mesh.get_surface_count() == 1, "%s has no surface" % label)
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var arrays := mesh.surface_get_arrays(0)
	_expect((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 3, "%s has no vertices" % label)
	_expect((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0, "%s has no triangles" % label)


func _check_meshes_are_not_empty() -> void:
	for terrain in HexSlabArt.terrains():
		_expect_mesh(HexSlabArt.slab(terrain), "slab %s" % terrain)
		_expect_mesh(TerrainPropsArt.props(terrain, 2, -1), "props %s" % terrain)
	for number in range(2, 13):
		_expect_mesh(ChipArt.chip(number), "chip %d" % number)
	_expect_mesh(PortArt.pier(), "pier")
	_expect_mesh(PortArt.flag(3, ""), "flag 3:1")
	for resource in SiResource.VALUES:
		_expect_mesh(PortArt.flag(2, resource), "flag 2:1 %s" % resource)
	_expect_mesh(RobberArt.robber(), "robber")
	_expect_mesh(PieceArt.road(), "road")
	_expect_mesh(PieceArt.settlement(), "settlement")
	_expect_mesh(PieceArt.city(), "city")
	_expect_mesh(DieArt.die(), "die")
	_expect_mesh(TableArt.table(), "table")
	_expect_mesh(WaterArt.hex(), "water hex")
	_expect_mesh(TableArt.seat_stand_base(), "seat stand base")
	_expect_mesh(TableArt.seat_stand_inlay(), "seat stand inlay")
	for seat in 4:
		_expect(ClayMaterials.piece(seat) != null, "material of seat %d" % seat)


func _check_props_are_deterministic() -> void:
	for terrain in HexSlabArt.terrains():
		var first := TerrainPropsArt.builder(terrain, 3, -2)
		var second := TerrainPropsArt.builder(terrain, 3, -2)
		_expect(first.same_geometry_as(second), "props of %s differ between two builds of one tile" % terrain)
		var elsewhere := TerrainPropsArt.builder(terrain, -1, 4)
		_expect(not first.same_geometry_as(elsewhere), "props of %s ignore the tile coordinates" % terrain)


## Props stay off the number chip in the middle and inside the slab: a mound or tree on the chip hides the number.
func _check_props_stay_on_the_tile() -> void:
	for terrain in HexSlabArt.terrains():
		for tile in [Vector2i(0, 0), Vector2i(1, -1), Vector2i(-2, 1), Vector2i(2, 2)]:
			var mesh := TerrainPropsArt.props(terrain, tile.x, tile.y)
			var reach := 0.0
			for point: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				reach = maxf(reach, Vector2(point.x, point.z).length())
			_expect(reach <= PROP_RING_LIMIT, "props of %s at %s reach %.2f" % [terrain, tile, reach])


func _check_hot_numbers() -> void:
	for number in range(2, 13):
		var hot := ChipArt.builder(number).count_vertices(
			func(_position: Vector3, color: Color) -> bool: return color.is_equal_approx(Palette.HOT_NUMBER)
		)
		var expected_hot := number == 6 or number == 8
		_expect((hot > 0) == expected_hot, "chip %d hot colour: %d vertices" % [number, hot])


func _check_dice_faces() -> void:
	var seen: Array[int] = []
	for value in range(1, 7):
		var normal: Vector3 = DieArt.FACE_NORMALS[value]
		for yaw: float in YAWS:
			var top := DieArt.orientation(value, yaw) * normal
			_expect(top.is_equal_approx(Vector3.UP), "die value %d does not land face up at yaw %.1f: %s" % [value, yaw, top])
		_expect(_pips_on_face(normal) == value, "die face %d carries %d pips" % [value, _pips_on_face(normal)])
		var opposite: int = DieArt.FACE_NORMALS.find_key(-normal)
		_expect(opposite + value == 7, "opposite of %d is %d" % [value, opposite])
		seen.append(value)
	_expect(seen.size() == DieArt.FACE_NORMALS.size(), "face table has %d entries" % DieArt.FACE_NORMALS.size())


func _pips_on_face(normal: Vector3) -> int:
	var vertices := DieArt.builder().count_vertices(
		func(position: Vector3, color: Color) -> bool:
			return DieArt.is_pip_color(color) and position.dot(normal) > DieArt.HALF
	)
	return vertices / StrokeFont.disc_vertex_count(DieArt.PIP_SEGMENTS)


func _triangles(mesh: ArrayMesh) -> int:
	return (mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3


func _expect_budget(mesh: ArrayMesh, budget: int, label: String) -> void:
	var count := _triangles(mesh)
	_expect(count <= budget, "%s has %d triangles, budget %d" % [label, count, budget])
	print("TRIANGLES %s %d" % [label, count])


func _check_triangle_budgets() -> void:
	for terrain in HexSlabArt.terrains():
		_expect_budget(HexSlabArt.slab(terrain), BUDGET_SLAB, "slab %s" % terrain)
		_expect_budget(TerrainPropsArt.props(terrain, 2, -1), BUDGET_PROPS, "props %s" % terrain)
		var number := 8 if terrain != HexSlabArt.DESERT else 0
		var tile := _triangles(HexSlabArt.slab(terrain)) + _triangles(TerrainPropsArt.props(terrain, 2, -1))
		tile += _triangles(ChipArt.chip(number)) if number > 0 else 0
		_expect(tile <= BUDGET_TILE, "tile %s has %d triangles, budget %d" % [terrain, tile, BUDGET_TILE])
	for number in range(2, 13):
		_expect_budget(ChipArt.chip(number), BUDGET_CHIP, "chip %d" % number)
	_expect_budget(PieceArt.road(), BUDGET_PIECE, "road")
	_expect_budget(PieceArt.settlement(), BUDGET_PIECE, "settlement")
	_expect_budget(PieceArt.city(), BUDGET_PIECE, "city")
	_expect_budget(RobberArt.robber(), BUDGET_ROBBER, "robber")
	_expect_budget(DieArt.die(), BUDGET_DIE, "die")
	_expect_budget(PortArt.pier(), BUDGET_PORT, "pier")
	_expect_budget(PortArt.flag(3, ""), BUDGET_PORT, "flag")
	_expect_budget(TableArt.table(), BUDGET_TABLE, "table")
	_expect_budget(TableArt.seat_stand_base(), BUDGET_TABLE, "stand base")
	_expect_budget(TableArt.seat_stand_inlay(), BUDGET_TABLE, "stand inlay")
	_expect_budget(WaterArt.hex(), BUDGET_WATER, "water hex")


## Flat shading: every triangle's three vertices carry one and the same normal, and it is the face normal.
func _check_flat_shading() -> void:
	for mesh: ArrayMesh in [PieceArt.settlement(), PieceArt.road(), HexSlabArt.slab("Wood"), RobberArt.robber(), DieArt.die()]:
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for triangle in indices.size() / 3:
			var first := indices[triangle * 3]
			var second := indices[triangle * 3 + 1]
			var third := indices[triangle * 3 + 2]
			var face := -(vertices[second] - vertices[first]).cross(vertices[third] - vertices[first]).normalized()
			# Godot stores normals compressed, so compare with a tolerance.
			var flat := normals[first].dot(face) > 0.99 and normals[second].dot(face) > 0.99 and normals[third].dot(face) > 0.99
			if not flat:
				_failures.append("triangle %d of a kit mesh is not flat" % triangle)
				break


## The water fills the free lattice cells around the land and never overlaps a land tile.
func _check_water_cells() -> void:
	var land: Array[Vector2] = [Vector2.ZERO, Vector2(BoardGeometry.SQUARE_ROOT_OF_THREE, 0.0)]
	var cells := WaterArt.cells(land)
	_expect(cells.size() > 30, "only %d water cells" % cells.size())
	for cell in cells:
		_expect(not land.has(cell), "water on land tile %s" % cell)
	_expect(cells.has(Vector2(-BoardGeometry.SQUARE_ROOT_OF_THREE, 0.0)), "no water next to the land")
