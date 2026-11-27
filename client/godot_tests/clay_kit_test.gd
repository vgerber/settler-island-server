extends SceneTree
## Runs inside a copy of the game project: every clay kit builder returns a non-empty mesh, props depend only on the
## tile coordinates (and stay clear of the chip and the tile edge), the number chip colours 6 and 8 as hot, and the
## dice face table turns every value to the top with exactly that many pips on that face.
## Usage: godot --headless --path <copy of client/godot> -s clay_kit_test.gd

const PROP_RING_LIMIT := 0.86
const YAWS := [0.0, 0.7, 2.1, -1.3]

var _failures: PackedStringArray = []


func _init() -> void:
	_check_meshes_are_not_empty()
	_check_props_are_deterministic()
	_check_props_stay_on_the_tile()
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
	_expect_mesh(TableArt.sea(), "sea")
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
