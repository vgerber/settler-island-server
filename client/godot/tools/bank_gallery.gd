extends SceneTree
## Renders stills of the bank, trade and menu fixtures (`BankArt`) on a small island: the bank rack with
## card piles, the trade token, an open trade mat with cards and two buttons, the
## settings board, both ledgers and the game-over sign with `Label3D` texts. The stills go to
## `<output directory>/bank_<renderer>_<shot>.png` at 1600x900; the triangle counts are printed. Needs a window,
## quits by itself.
## Usage: godot --path client/godot --position 200,200 --rendering-method gl_compatibility \
##   -s tools/bank_gallery.gd -- <output directory>

const SIZE := Vector2i(1600, 900)
const SETTLE_FRAMES := 8
const SQUARE_ROOT_OF_THREE := 1.7320508
const FIELD_OF_VIEW := 38.0
const PITCH := deg_to_rad(55.0)
const TILES := [[0, 0, "Desert", 0], [1, 0, "Clay", 6], [0, 1, "Wood", 8], [-1, 1, "Sheep", 11], [-1, 0, "Wheat", 12], [0, -1, "Ore", 2]]
## Pile heights per bay: clay, wood, sheep, wheat, ore, development deck (empty).
const PILE_HEIGHTS: Array[int] = [19, 12, 6, 17, 3, 8]
const CREAM_TEXT := Color("#F3EADB")
const BOLD_FONT := "res://theme/fonts/Bitter-Bold.res"
const LABEL_FONT := "res://theme/fonts/AtkinsonHyperlegible-Bold.res"

var _viewport: SubViewport
var _camera: Camera3D
var _world: Node3D
var _output_directory := ""
var _renderer := ""
var _shots: Array[Dictionary] = []
var _frames_left := -1
var _exit_code := 0


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty():
		push_error("usage: -s tools/bank_gallery.gd -- <output directory>")
		quit(1)
		return
	_output_directory = arguments[0]
	DirAccess.make_dir_recursive_absolute(_output_directory)
	_renderer = RenderingServer.get_current_rendering_method()
	_build_viewport()
	_build_scene()
	_print_triangle_counts()
	var sea := WaterArt.HEIGHT
	_shots = [
		_shot("overview", Vector3(0.0, 0.0, 0.5), 17.0, PITCH),
		_shot("rack", Vector3(5.4, sea + 0.1, -1.0), 3.4, PITCH),
		_shot("token", Vector3(-3.6, sea + 0.02, -1.2), 0.6, PITCH),
		_shot("mat", Vector3(-4.8, sea + 0.05, 3.3), 3.0, PITCH),
		_shot("settings", Vector3(4.8, sea + 0.05, 3.2), 3.2, PITCH),
		_shot("ledger", Vector3(-6.3, sea + 0.05, -2.5), 3.4, PITCH),
		_shot("sign", Vector3(0.0, sea + 0.4, -4.1), 3.4, PITCH),
	]


func _shot(shot_name: String, target: Vector3, distance: float, pitch: float) -> Dictionary:
	return {"name": shot_name, "target": target, "distance": distance, "pitch": pitch}


func _process(_delta: float) -> bool:
	if _frames_left > 0:
		_frames_left -= 1
		return false
	if _frames_left == 0:
		_save(_shots.pop_front())
		_frames_left = -1
	if _shots.is_empty():
		quit(_exit_code)
		return true
	_next_shot()
	return false


func _next_shot() -> void:
	var shot: Dictionary = _shots[0]
	var target: Vector3 = shot["target"]
	var pitch: float = shot["pitch"]
	_camera.position = target + Vector3(0.0, sin(pitch), cos(pitch)) * float(shot["distance"])
	_camera.look_at(target)
	_frames_left = SETTLE_FRAMES


func _save(shot: Dictionary) -> void:
	var path := _output_directory.path_join("bank_%s_%s.png" % [_renderer_name(), shot["name"]])
	var error := _viewport.get_texture().get_image().save_png(path)
	print("saved %s (%d)" % [path, error])
	if error != OK:
		push_error("bank_gallery: saving %s failed (%d)" % [path, error])
		_exit_code = 1


func _renderer_name() -> String:
	return "compatibility" if _renderer == "gl_compatibility" else _renderer


func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_world = Node3D.new()
	_viewport.add_child(_world)
	_camera = Camera3D.new()
	_camera.fov = FIELD_OF_VIEW
	_camera.current = true
	_viewport.add_child(_camera)


func _build_scene() -> void:
	TableLight.add_to(_world)
	_add_mesh(TableArt.table(), ClayMaterials.table(), Vector3.ZERO)
	_add_water()
	for tile: Array in TILES:
		_add_tile(tile[0], tile[1], tile[2], tile[3])
	var sea := WaterArt.HEIGHT
	_add_rack(Vector3(5.4, sea, -1.0))
	_add_token(Vector3(-3.6, sea, -1.2))
	_add_mat(Vector3(-4.8, sea, 3.3))
	_add_settings(Vector3(4.8, sea, 3.2))
	_add_ledgers(Vector3(-6.3, sea, -2.5))
	_add_sign(Vector3(0.0, sea, -4.1))


func _print_triangle_counts() -> void:
	var meshes := {
		"bank_rack": BankArt.bank_rack(),
		"trade_token": BankArt.trade_token(),
		"trade_mat": BankArt.trade_mat(),
		"wood_button": BankArt.wood_button(),
		"settings_board": BankArt.settings_board(),
		"slider_knob": BankArt.slider_knob(),
		"toggle_knob": BankArt.toggle_knob(),
		"ledger_closed": BankArt.ledger(false),
		"ledger_open": BankArt.ledger(true),
		"title_sign": BankArt.title_sign(),
	}
	for mesh_name: String in meshes:
		var mesh: ArrayMesh = meshes[mesh_name]
		var indices: PackedInt32Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
		print("triangles %s: %d" % [mesh_name, indices.size() / 3])


func _add_water() -> void:
	var land: Array[Vector2] = []
	for tile: Array in TILES:
		var position := _tile_position(tile[0], tile[1])
		land.append(Vector2(position.x, position.z))
	_world.add_child(BoardArt.water(WaterArt.cells(land)))


func _add_mesh(mesh: Mesh, material: Material, position: Vector3, yaw := 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.rotation.y = yaw
	_world.add_child(instance)
	return instance


func _tile_position(q: int, r: int) -> Vector3:
	return Vector3(SQUARE_ROOT_OF_THREE * (q + r / 2.0), 0.0, 1.5 * r)


func _add_tile(q: int, r: int, terrain: String, number: int) -> void:
	var centre := _tile_position(q, r)
	_add_mesh(HexSlabArt.slab(terrain), ClayMaterials.terrain(), centre)
	var top := centre + Vector3(0.0, HexSlabArt.HEIGHT, 0.0)
	_add_mesh(TerrainPropsArt.props(terrain, q, r), ClayMaterials.terrain(), top)
	if number > 0:
		_add_mesh(ChipArt.chip(number), ClayMaterials.stock(), top)


func _add_shadow(parent: Node3D, half_extent: Vector2, strength := 0.4) -> void:
	var shadow := BlobShadow.create(1.0, strength)
	shadow.scale = Vector3(half_extent.x * 2.4, 1.0, half_extent.y * 2.4)
	parent.add_child(shadow)


func _add_label(parent: Node3D, text: String, placement: Transform3D, size: float, bold := false, color := CREAM_TEXT) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = load(BOLD_FONT if bold else LABEL_FONT)
	label.font_size = 64
	label.pixel_size = size / 64.0
	label.modulate = color
	label.outline_size = 0
	label.transform = placement
	parent.add_child(label)


## A label lying flat (facing up) at `point`, optionally inside the parent's own frame.
static func _flat(point: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), point)


## Cards stacked on `base`, slightly turned so the pile reads as a heap.
func _add_pile(parent: Node3D, base: Vector3, count: int, mesh: Mesh) -> void:
	for index in count:
		var yaw := 0.05 * sin(index * 2.3)
		var position := base + Vector3(0.006 * sin(index * 1.7), index * CardArt.THICKNESS, 0.0)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = ClayMaterials.stock()
		instance.position = position
		instance.rotation.y = yaw
		parent.add_child(instance)


func _fixture(mesh: Mesh, material: Material, position: Vector3, shadow_extent: Vector2) -> Node3D:
	var instance := _add_mesh(mesh, material, position)
	_add_shadow(instance, shadow_extent)
	return instance


func _add_rack(origin: Vector3) -> void:
	var rack := _fixture(BankArt.bank_rack(), ClayMaterials.terrain(), origin, Vector2(BankArt.RACK_HALF_WIDTH, BankArt.RACK_HALF_DEPTH))
	for index in BankArt.BAY_COUNT:
		_add_pile(rack, BankArt.pile_point(index), PILE_HEIGHTS[index], _bay_mesh(index))


func _bay_mesh(index: int) -> Mesh:
	var resource := BankArt.bay_resource(index)
	return CardArt.dev_back() if resource.is_empty() else CardArt.resource_card(resource)


func _add_token(origin: Vector3) -> void:
	_fixture(BankArt.trade_token(), ClayMaterials.terrain(), origin, Vector2(0.07, 0.07))


func _add_mat(origin: Vector3) -> void:
	var mat := _fixture(BankArt.trade_mat(), ClayMaterials.terrain(), origin, Vector2(BankArt.MAT_HALF_WIDTH, BankArt.MAT_HALF_DEPTH))
	_add_pile(mat, BankArt.mat_card_point(-1) + Vector3(-0.1, 0.0, 0.0), 1, CardArt.resource_card(SiResource.WOOD))
	_add_pile(mat, BankArt.mat_card_point(-1) + Vector3(0.1, 0.0, 0.0), 1, CardArt.resource_card(SiResource.WOOD))
	_add_pile(mat, BankArt.mat_card_point(1), 1, CardArt.resource_card(SiResource.WHEAT))
	_add_label(mat, "Bot 2 gives", _flat(Vector3(-BankArt.MAT_HALF_X, BankArt.MAT_FELT + 0.002, BankArt.MAT_LABEL_Z)), 0.1)
	_add_label(mat, "You give", _flat(Vector3(BankArt.MAT_HALF_X, BankArt.MAT_FELT + 0.002, BankArt.MAT_LABEL_Z)), 0.1)
	_add_button(mat, -1, BankArt.ButtonKind.TEAL, "Accept")
	_add_button(mat, 1, BankArt.ButtonKind.EMBER, "Decline")


func _add_button(mat: Node3D, side: int, kind: BankArt.ButtonKind, text: String) -> void:
	var point := BankArt.mat_button_point(side)
	var button := MeshInstance3D.new()
	button.mesh = BankArt.wood_button(kind)
	button.material_override = ClayMaterials.terrain()
	button.position = point
	mat.add_child(button)
	_add_label(button, text, _flat(Vector3(0.0, BankArt.BUTTON_TOP + 0.002, 0.0)), 0.1, true)


func _add_settings(origin: Vector3) -> void:
	var board := _fixture(BankArt.settings_board(), ClayMaterials.terrain(), origin, Vector2(BankArt.BOARD_HALF_WIDTH, BankArt.BOARD_HALF_DEPTH))
	var top := BankArt.BOARD_TOP + 0.002
	_add_label(board, "Settings", _flat(Vector3(0.0, top + 0.004, BankArt.BOARD_TITLE_Z)), 0.15, true)
	var names := ["Volume", "Animation speed", "Quality", "Colour-blind aid", "Clean view"]
	for index in names.size():
		var row_z: float = BankArt.BOARD_ROW_Z[index]
		_add_label(board, names[index], _flat(Vector3(BankArt.BOARD_LABEL_X + 0.4, top, row_z)), 0.09)
	var values := [0.8, 0.5, 0.0]
	for index in 3:
		_add_knob(board, BankArt.slider_knob(), BankArt.slider_point(index, values[index]))
	_add_knob(board, BankArt.toggle_knob(), BankArt.toggle_point(0, true))
	_add_knob(board, BankArt.toggle_knob(), BankArt.toggle_point(1, false))


func _add_knob(board: Node3D, mesh: Mesh, point: Vector3) -> void:
	var knob := MeshInstance3D.new()
	knob.mesh = mesh
	knob.material_override = ClayMaterials.terrain()
	knob.position = point
	board.add_child(knob)


func _add_ledgers(origin: Vector3) -> void:
	var closed := _fixture(BankArt.ledger(false), ClayMaterials.terrain(), origin + Vector3(-1.0, 0.0, -0.5), Vector2(0.33, 0.43))
	_add_label(closed, "History", _flat(Vector3(0.03, BankArt.CLOSED_COVER_TOP + 0.007, 0.0)), 0.08, true, BankArt.WALNUT_DARK)
	var open := _fixture(BankArt.ledger(true), ClayMaterials.terrain(), origin + Vector3(0.6, 0.0, 0.5), Vector2(0.66, 0.43))
	var left := ["Lin: rolled 8", "got 1 ore", "built a road", "Bot 2: rolled 5"]
	var right := ["Bot 3: rolled 11", "got 2 wood", "bought a card", "Lin: rolled 6"]
	for side in [-1, 1]:
		var lines: Array = left if side < 0 else right
		for index in lines.size():
			var flat := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.0, -0.28 + index * 0.18))
			_add_label(open, lines[index], BankArt.ledger_page_transform(side) * flat, 0.065, false, Palette.INK)


func _add_sign(origin: Vector3) -> void:
	var sign_board := _fixture(BankArt.title_sign(), ClayMaterials.terrain(), origin, Vector2(0.75, 0.2))
	_add_label(sign_board, "Bot 2 wins", BankArt.sign_face(), 0.3, true)
