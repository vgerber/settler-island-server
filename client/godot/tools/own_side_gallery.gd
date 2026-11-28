extends SceneTree
## Renders stills of the own-side fixtures of the 3D table UI (`OwnSideArt`): a small island with the supply rack
## of one seat (some pieces used, so empty sockets show), the hand tray with placeholder cards, the bell with and
## without its cover, and the prompt sign. Prints the triangle count of every mesh. The stills go to
## `<output directory>/own_side_<renderer>_<shot>.png` at 1600x900. Needs a window, quits by itself.
## Usage: godot --path client/godot --position 200,200 --rendering-method gl_compatibility \
##   -s tools/own_side_gallery.gd -- <output directory>

const SIZE := Vector2i(1600, 900)
const SETTLE_FRAMES := 8
const SQUARE_ROOT_OF_THREE := 1.7320508
const FIELD_OF_VIEW := 38.0
const PITCH := deg_to_rad(55.0)
const SEAT := 0
const TILES := [
	[0, 0, "Desert", 0],
	[1, 0, "Clay", 6],
	[0, 1, "Wood", 8],
	[-1, 1, "Sheep", 11],
	[-1, 0, "Wheat", 12],
	[0, -1, "Ore", 2],
	[1, -1, "Wood", 5],
]
## Pieces still in the rack: the rest stand on the board, so their sockets are empty.
const SUPPLY_LEFT := {"road": 10, "settlement": 3, "city": 3}
const HAND_COUNTS := [3, 1, 2, 4, 2, 2]
const RACK_ORIGIN := Vector3(-4.2, WaterArt.HEIGHT, 3.6)
const HAND_ORIGIN := Vector3(0.0, 0.0, 5.7)
const BELL_ORIGIN := Vector3(3.8, WaterArt.HEIGHT, 4.4)
const COVERED_BELL_ORIGIN := Vector3(5.2, WaterArt.HEIGHT, 4.4)
const SIGN_ORIGIN := Vector3(-4.6, WaterArt.HEIGHT, -2.4)
const SIGN_TEXT := "Place a road"
const TEXT_COLOR := Color("#F3EADB")

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
		push_error("usage: -s tools/own_side_gallery.gd -- <output directory>")
		quit(1)
		return
	_output_directory = arguments[0]
	DirAccess.make_dir_recursive_absolute(_output_directory)
	_renderer = RenderingServer.get_current_rendering_method()
	_build_viewport()
	_build_scene()
	_print_triangles()
	_shots = [
		_shot("default", Vector3(0.0, 0.0, 1.9), 13.5, PITCH),
		_shot("rack", RACK_ORIGIN + Vector3(0.0, 0.1, -0.1), 3.9, PITCH),
		_shot("rack_close", RACK_ORIGIN + Vector3(0.0, 0.1, 0.4), 2.3, deg_to_rad(40.0)),
		_shot("hand", HAND_ORIGIN + Vector3(0.0, 0.1, 0.0), 3.8, PITCH),
		_shot("bell", (BELL_ORIGIN + COVERED_BELL_ORIGIN) * 0.5 + Vector3(0.0, 0.2, 0.0), 2.8, PITCH),
		_shot("sign", SIGN_ORIGIN + Vector3(0.0, 0.5, 0.0), 3.0, PITCH),
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
	var path := _output_directory.path_join("own_side_%s_%s.png" % [_renderer_name(), shot["name"]])
	var error := _viewport.get_texture().get_image().save_png(path)
	print("saved %s (%d)" % [path, error])
	if error != OK:
		push_error("own_side_gallery: saving %s failed (%d)" % [path, error])
		_exit_code = 1


func _renderer_name() -> String:
	return "compatibility" if _renderer == "gl_compatibility" else _renderer


func _print_triangles() -> void:
	var meshes := {
		"supply_rack": OwnSideArt.supply_rack(),
		"hand_tray": OwnSideArt.hand_tray(),
		"bell": OwnSideArt.bell(),
		"bell_cover": OwnSideArt.bell_cover(),
		"prompt_sign": OwnSideArt.prompt_sign(),
		"prompt_sign_tab": OwnSideArt.prompt_sign_tab(),
	}
	for mesh_name: String in meshes:
		var mesh: ArrayMesh = meshes[mesh_name]
		var arrays := mesh.surface_get_arrays(0)
		print("triangles %s: %d" % [mesh_name, (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3])


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
	_add_rack()
	_add_hand()
	_add_bells()
	_add_sign()


func _add_water() -> void:
	var land: Array[Vector2] = []
	for tile: Array in TILES:
		var position := _tile_position(tile[0], tile[1])
		land.append(Vector2(position.x, position.z))
	_world.add_child(BoardArt.water(WaterArt.cells(land)))


func _add_mesh(mesh: Mesh, material: Material, position: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	(parent if parent != null else _world).add_child(instance)
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


func _add_shadow(parent: Node3D, radius: float) -> void:
	parent.add_child(BlobShadow.create(radius, 0.4))


func _add_rack() -> void:
	var rack := _add_mesh(OwnSideArt.supply_rack(), ClayMaterials.terrain(), RACK_ORIGIN)
	var meshes := {"road": PieceArt.road(), "settlement": PieceArt.settlement(), "city": PieceArt.city()}
	for kind: String in OwnSideArt.RACK_ROWS:
		_fill_row(rack, kind, meshes[kind])
		_add_mini_cards(rack, kind)


## The pieces fill the sockets from the right; the first sockets stay empty.
func _fill_row(rack: Node3D, kind: String, mesh: Mesh) -> void:
	var count: int = OwnSideArt.RACK_ROWS[kind]["count"]
	for index in range(count - int(SUPPLY_LEFT[kind]), count):
		var piece := _add_mesh(mesh, ClayMaterials.piece(SEAT), Vector3.ZERO, rack)
		piece.transform = OwnSideArt.supply_piece(kind, index)


## Two or three small cards standing on the ledge in front of each row.
func _add_mini_cards(rack: Node3D, kind: String) -> void:
	var ledge := OwnSideArt.supply_ledge(kind)
	var turn := Basis(Vector3.RIGHT, OwnSideArt.COST_CARD_LEAN).scaled_local(Vector3.ONE * OwnSideArt.COST_CARD_SCALE)
	for index in 3:
		var card := _add_mesh(CardArt.resource_card(SiResource.VALUES[index]), ClayMaterials.stock(), ledge + Vector3((index - 1) * OwnSideArt.COST_CARD_PITCH, 0.0, 0.0), rack)
		card.basis = turn


func _add_hand() -> void:
	var tray := _add_mesh(OwnSideArt.hand_tray(), ClayMaterials.terrain(), HAND_ORIGIN)
	_add_shadow(tray, 1.7)
	for slot in HAND_COUNTS.size():
		for layer in int(HAND_COUNTS[slot]):
			var card := _add_mesh(CardArt.development_card("Knight") if slot > 4 else CardArt.resource_card(SiResource.VALUES[slot]), ClayMaterials.stock(), Vector3.ZERO, tray)
			card.transform = OwnSideArt.hand_slot(slot) * Transform3D(Basis.IDENTITY, Vector3(0.012 * layer, 0.016 * layer, 0.0))


func _add_bells() -> void:
	var bell := _add_mesh(OwnSideArt.bell(), ClayMaterials.terrain(), BELL_ORIGIN)
	_add_shadow(bell, 0.5)
	var covered := _add_mesh(OwnSideArt.bell(), ClayMaterials.terrain(), COVERED_BELL_ORIGIN)
	_add_shadow(covered, 0.5)
	_add_mesh(OwnSideArt.bell_cover(), ClayMaterials.terrain(), Vector3(0.0, OwnSideArt.BELL_BASE_HEIGHT, 0.0), covered)


func _add_sign() -> void:
	var board := _add_mesh(OwnSideArt.prompt_sign(), ClayMaterials.terrain(), SIGN_ORIGIN)
	_add_mesh(OwnSideArt.prompt_sign_tab(), ClayMaterials.piece(SEAT), Vector3.ZERO, board)
	_add_shadow(board, 1.2)
	var label := Label3D.new()
	label.text = SIGN_TEXT
	label.font = load("res://theme/fonts/Bitter-Bold.res")
	label.font_size = 96
	label.pixel_size = 0.003
	label.modulate = TEXT_COLOR
	label.outline_size = 0
	label.width = OwnSideArt.SIGN_TEXT_WIDTH / label.pixel_size
	label.transform = OwnSideArt.sign_text()
	board.add_child(label)
