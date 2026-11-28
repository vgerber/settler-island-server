extends SceneTree
## Renders stills of the card kit on the real table: a few tiles and a settlement for scale, a row of every card
## face, a row of development cards, a fanned hand of seven, a stack of backs and close-ups.
## The stills go to `<output directory>/cards_<renderer>_<shot>.png` at 1600x900. Needs a window, quits by itself.
## Usage: godot --path client/godot --position 200,200 --rendering-method gl_compatibility \
##   -s tools/card_gallery.gd -- <output directory>

const SIZE := Vector2i(1600, 900)
const SETTLE_FRAMES := 8
const SQUARE_ROOT_OF_THREE := 1.7320508
const FIELD_OF_VIEW := 38.0
const PITCH := deg_to_rad(58.0)
## The cards lie on the flat table in front of the island (z 5.2 to 6.9): rows left, hand middle, stacks right.
const ROWS_X := -3.4
const FACES_Z := 5.85
const DEV_Z := 6.55
const HAND_X := 1.4
const HAND_Z := 6.2
const STACK_X := 5.2
const STACK_Z := 6.2
const TILES := [
	[0, 0, "Desert", 0],
	[1, 0, "Clay", 6],
	[0, 1, "Wood", 8],
	[-1, 1, "Sheep", 11],
	[-1, 0, "Wheat", 12],
	[0, -1, "Ore", 2],
	[1, -1, "Wood", 5],
]
## Seat colour check: one tile per terrain, and a settlement of every seat on it.
const SWATCH_TERRAINS := ["Clay", "Wood", "Sheep", "Wheat", "Ore", "Desert"]

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
		push_error("usage: -s tools/card_gallery.gd -- <output directory>")
		quit(1)
		return
	_output_directory = arguments[0]
	DirAccess.make_dir_recursive_absolute(_output_directory)
	_renderer = RenderingServer.get_current_rendering_method()
	_build_viewport()
	_build_scene()
	_print_triangle_counts()
	_shots = [
		_shot("table", Vector3(0.0, 0.0, 4.0), 15.0, PITCH),
		_shot("faces", Vector3(ROWS_X, 0.0, 6.2), 4.4, deg_to_rad(55.0)),
		_shot("faces_low", Vector3(ROWS_X, 0.0, 6.2), 4.4, deg_to_rad(40.0)),
		_shot("hand", Vector3(HAND_X, 0.1, HAND_Z), 3.2, deg_to_rad(55.0)),
		_shot("stack", Vector3(STACK_X + 0.45, 0.1, STACK_Z), 2.6, deg_to_rad(50.0)),
		_shot("close_clay_wood", Vector3(ROWS_X - 0.92, 0.0, FACES_Z), 1.5, deg_to_rad(55.0)),
		_shot("close_sheep_wheat", Vector3(ROWS_X, 0.0, FACES_Z), 1.5, deg_to_rad(55.0)),
		_shot("close_ore_back", Vector3(ROWS_X + 0.92, 0.0, FACES_Z), 1.5, deg_to_rad(55.0)),
		_shot("close_dev_a", Vector3(ROWS_X - 0.46, 0.0, DEV_Z), 1.6, deg_to_rad(55.0)),
		_shot("close_dev_b", Vector3(ROWS_X + 0.46, 0.0, DEV_Z), 1.6, deg_to_rad(55.0)),
		_shot("overhead", Vector3(ROWS_X, 0.0, 6.2), 4.0, deg_to_rad(88.0)),
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
	var path := _output_directory.path_join("cards_%s_%s.png" % [_renderer_name(), shot["name"]])
	var error := _viewport.get_texture().get_image().save_png(path)
	print("saved %s (%d)" % [path, error])
	if error != OK:
		push_error("card_gallery: saving %s failed (%d)" % [path, error])
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
	var land: Array[Vector2] = []
	for tile: Array in TILES:
		var position := _tile_position(tile[0], tile[1])
		land.append(Vector2(position.x, position.z))
		var centre := position
		_add_mesh(HexSlabArt.slab(tile[2]), ClayMaterials.terrain(), centre)
		var top := centre + Vector3(0.0, HexSlabArt.HEIGHT, 0.0)
		_add_mesh(TerrainPropsArt.props(tile[2], tile[0], tile[1]), ClayMaterials.terrain(), top)
		_add_mesh(ChipArt.chip(tile[3]), ClayMaterials.stock(), top)
	_world.add_child(BoardArt.water(WaterArt.cells(land)))
	_add_settlement()
	_add_faces_row()
	_add_dev_row()
	_add_hand()
	_add_stack()


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


## A settlement and a chip beside the cards give the scale of the board pieces.
func _add_settlement() -> void:
	var base := Vector3(ROWS_X - 2.4, 0.0, 6.2)
	var instance := _add_mesh(PieceArt.settlement(), ClayMaterials.piece(0), base)
	instance.add_child(BlobShadow.create(0.2, 0.4))
	_add_mesh(ChipArt.chip(8), ClayMaterials.stock(), base + Vector3(-0.6, 0.0, 0.0))


func _add_card(mesh: Mesh, position: Vector3, yaw := 0.0, pitch := 0.0) -> MeshInstance3D:
	var instance := _add_mesh(mesh, ClayMaterials.stock(), position, yaw)
	instance.rotation.x = pitch
	var shadow := BlobShadow.create(0.3, 0.35)
	shadow.position = Vector3(position.x, BlobShadow.LIFT, position.z)
	_world.add_child(shadow)
	return instance


func _add_faces_row() -> void:
	var meshes: Array[Mesh] = []
	for resource in SiResource.VALUES:
		meshes.append(CardArt.resource_card(resource))
	meshes.append(CardArt.card_back())
	for index in meshes.size():
		_add_card(meshes[index], Vector3((index - (meshes.size() - 1) * 0.5) * 0.46 + ROWS_X, 0.0, FACES_Z))


func _add_dev_row() -> void:
	var meshes: Array[Mesh] = []
	for kind in SiDevelopmentCard.VALUES:
		meshes.append(CardArt.development_card(kind))
	meshes.append(CardArt.dev_back())
	for index in meshes.size():
		_add_card(meshes[index], Vector3((index - (meshes.size() - 1) * 0.5) * 0.46 + ROWS_X, 0.0, DEV_Z))


## Seven cards fanned from a pivot below the front edge, leaning toward the camera.
func _add_hand() -> void:
	var order: Array[Mesh] = [
		CardArt.resource_card(SiResource.CLAY), CardArt.resource_card(SiResource.CLAY), CardArt.resource_card(SiResource.WOOD),
		CardArt.resource_card(SiResource.SHEEP), CardArt.resource_card(SiResource.WHEAT), CardArt.resource_card(SiResource.ORE),
		CardArt.development_card(SiDevelopmentCard.KNIGHT),
	]
	for index in order.size():
		var spread := (index - 3.0) * deg_to_rad(9.0)
		var position := Vector3(HAND_X + (index - 3.0) * 0.27, 0.1 + index * 0.012, HAND_Z + absf(index - 3.0) * 0.03)
		_add_card(order[index], position, -spread, deg_to_rad(18.0))


## Backs stacked, slightly turned, like a deck or an opponent's pile.
func _add_stack() -> void:
	for index in 12:
		var position := Vector3(STACK_X, index * CardArt.THICKNESS * 1.05, STACK_Z)
		_add_card(CardArt.card_back(), position, sin(index * 1.7) * 0.08)
	for index in 6:
		var position := Vector3(STACK_X + 0.9, index * CardArt.THICKNESS * 1.05, STACK_Z)
		_add_card(CardArt.dev_back(), position, sin(index * 2.1) * 0.08)


func _print_triangle_counts() -> void:
	var meshes := {"back": CardArt.card_back(), "dev_back": CardArt.dev_back()}
	for resource in SiResource.VALUES:
		meshes[resource] = CardArt.resource_card(resource)
	for kind in SiDevelopmentCard.VALUES:
		meshes[kind] = CardArt.development_card(kind)
	for key: String in meshes:
		var mesh: ArrayMesh = meshes[key]
		var indices: PackedInt32Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
		print("triangles %s: %d" % [key, indices.size() / 3])
