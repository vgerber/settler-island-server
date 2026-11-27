extends SceneTree
## Renders stills of the clay kit: a small island with every terrain, chips, ports, the robber, pieces of every
## kind for every seat and two dice, a swatch row (every seat on every terrain) and a close-up of the pieces.
## The stills go to `<output directory>/clay_<renderer>_<shot>.png` at 1600x900; the renderer comes from the
## command line, so run it once per renderer. Needs a window, quits by itself.
## Usage: godot --path client/godot --position 200,200 --rendering-method gl_compatibility \
##   -s tools/clay_gallery.gd -- <output directory>
## (and `--rendering-method forward_plus` for the High look)

const SIZE := Vector2i(1600, 900)
const SETTLE_FRAMES := 8
const SQUARE_ROOT_OF_THREE := 1.7320508
const FIELD_OF_VIEW := 38.0
const PITCH := deg_to_rad(58.0)
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
		push_error("usage: -s tools/clay_gallery.gd -- <output directory>")
		quit(1)
		return
	_output_directory = arguments[0]
	DirAccess.make_dir_recursive_absolute(_output_directory)
	_renderer = RenderingServer.get_current_rendering_method()
	_build_viewport()
	_build_scene()
	_shots = [
		_shot("island", Vector3(0.0, 0.0, 0.3), 10.5, PITCH),
		_shot("table", Vector3(0.0, 0.0, 0.8), 17.0, PITCH),
		_shot("swatches", Vector3(0.0, 0.0, 9.0), 7.5, deg_to_rad(52.0)),
		_shot("pieces", Vector3(0.0, 0.1, 4.5), 4.2, deg_to_rad(50.0)),
		_shot("house_close", Vector3(-1.65, 0.15, 4.25), 1.8, deg_to_rad(45.0)),
		_shot("dice_close", Vector3(-7.65, 0.1, 3.25), 1.6, deg_to_rad(55.0)),
		_shot("chips_close", Vector3(1.8, 0.1, 0.0), 3.4, deg_to_rad(52.0)),
		_shot("robber_close", Vector3(0.0, 0.2, 0.0), 1.1, deg_to_rad(52.0)),
		_shot("pier_close", Vector3(3.05, 0.1, 0.0), 2.0, deg_to_rad(52.0)),
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
	var path := _output_directory.path_join("clay_%s_%s.png" % [_renderer_name(), shot["name"]])
	var error := _viewport.get_texture().get_image().save_png(path)
	print("saved %s (%d)" % [path, error])
	if error != OK:
		push_error("clay_gallery: saving %s failed (%d)" % [path, error])
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
	_add_environment()
	_add_mesh(TableArt.table(), ClayMaterials.table(), Vector3.ZERO)
	_add_water()
	for tile: Array in TILES:
		_add_tile(tile[0], tile[1], tile[2], tile[3])
	_add_pieces_on_island()
	_add_ports()
	_add_lineup(Vector3(0.0, 0.0, 4.5))
	_add_swatches(Vector3(0.0, 0.0, 9.0))
	_add_stands()
	_add_dice()


## Water hexes on every free lattice cell around the gallery island (the lineup and ports stand on them).
func _add_water() -> void:
	var land: Array[Vector2] = []
	for tile: Array in TILES:
		var position := _tile_position(tile[0], tile[1])
		land.append(Vector2(position.x, position.z))
	_world.add_child(BoardArt.water(WaterArt.cells(land)))


func _add_environment() -> void:
	TableLight.add_to(_world)


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


func _add_tile(q: int, r: int, terrain: String, number: int, origin := Vector3.ZERO) -> void:
	var centre := _tile_position(q, r) + origin
	_add_mesh(HexSlabArt.slab(terrain), ClayMaterials.terrain(), centre)
	var top := centre + Vector3(0.0, HexSlabArt.HEIGHT, 0.0)
	_add_mesh(TerrainPropsArt.props(terrain, q, r), ClayMaterials.terrain(), top)
	if number > 0:
		_add_mesh(ChipArt.chip(number), ClayMaterials.stock(), top)


## The 2D position of corner `index` of the tile (angles as in BoardGeometry), on the slab top.
func _corner(q: int, r: int, index: int, origin := Vector3.ZERO) -> Vector3:
	var angle := deg_to_rad(30.0 + 60.0 * index)
	var offset := Vector3(cos(angle), 0.0, sin(angle))
	return _tile_position(q, r) + offset + origin + Vector3(0.0, HexSlabArt.HEIGHT, 0.0)


func _add_piece(mesh: Mesh, seat: int, position: Vector3, yaw := 0.0) -> void:
	var instance := _add_mesh(mesh, ClayMaterials.piece(seat), position, yaw)
	var shadow := BlobShadow.create(0.2 if mesh != PieceArt.road() else 0.26, 0.4)
	instance.add_child(shadow)


func _add_pieces_on_island() -> void:
	for index in TILES.size():
		var tile: Array = TILES[index]
		var q: int = tile[0]
		var r: int = tile[1]
		_add_piece(PieceArt.settlement(), index % 4, _corner(q, r, 4))
		_add_piece(PieceArt.city(), (index + 1) % 4, _corner(q, r, 2), deg_to_rad(15.0))
		var road_centre := (_corner(q, r, 0) + _corner(q, r, 1)) * 0.5
		_add_piece(PieceArt.road(), (index + 2) % 4, road_centre, deg_to_rad(-60.0))
	var robber := _add_mesh(RobberArt.robber(), ClayMaterials.robber(), _tile_position(0, 0) + Vector3(0.0, HexSlabArt.HEIGHT, 0.0))
	robber.add_child(BlobShadow.create(0.22, 0.45))


func _add_ports() -> void:
	_add_port(1, 0, 0.0, 3, "")
	_add_port(-1, 1, 120.0, 2, SiResource.SHEEP)
	_add_port(0, -1, 240.0, 2, SiResource.ORE)


## A pier at the edge of tile (q, r) in direction `degrees` (edge midpoints lie at 0, 60, ... degrees).
func _add_port(q: int, r: int, degrees: float, ratio: int, resource: String) -> void:
	var angle := deg_to_rad(degrees)
	var edge := _tile_position(q, r) + Vector3(cos(angle), 0.0, sin(angle)) * (HexSlabArt.APOTHEM)
	_add_mesh(PortArt.pier(resource), ClayMaterials.terrain(), edge, atan2(-sin(angle), cos(angle)))
	var tip := edge + Vector3(cos(angle), 0.0, sin(angle)) * (PortArt.PIER_LENGTH - 0.08)
	_add_mesh(PortArt.flag(ratio, resource), ClayMaterials.terrain(), tip + Vector3(0.0, PortArt.DECK_HEIGHT, 0.0))


## Every seat's settlement, city and road in rows on the water, with chips, the robber and a die beside them.
func _add_lineup(origin: Vector3) -> void:
	for seat in 4:
		var x := (seat - 1.5) * 1.1
		_add_piece(PieceArt.settlement(), seat, origin + Vector3(x, WaterArt.HEIGHT, -0.5))
		_add_piece(PieceArt.city(), seat, origin + Vector3(x, WaterArt.HEIGHT, 0.2), deg_to_rad(20.0))
		_add_piece(PieceArt.road(), seat, origin + Vector3(x, WaterArt.HEIGHT, 0.7))
	_add_mesh(ChipArt.chip(6), ClayMaterials.stock(), origin + Vector3(-3.2, WaterArt.HEIGHT, 0.0))
	_add_mesh(ChipArt.chip(10), ClayMaterials.stock(), origin + Vector3(-3.2, WaterArt.HEIGHT, 0.7))
	_add_mesh(ChipArt.chip(4), ClayMaterials.stock(), origin + Vector3(3.2, WaterArt.HEIGHT, 0.0))
	_add_mesh(RobberArt.robber(), ClayMaterials.robber(), origin + Vector3(3.2, WaterArt.HEIGHT, 0.7))


## One slab per terrain with a settlement of every seat on the front and the back corners.
func _add_swatches(origin: Vector3) -> void:
	for index in SWATCH_TERRAINS.size():
		var terrain: String = SWATCH_TERRAINS[index]
		var centre := origin + Vector3((index - 2.5) * 2.0, 0.0, 0.0)
		_add_mesh(HexSlabArt.slab(terrain), ClayMaterials.terrain(), centre)
		var top := centre + Vector3(0.0, HexSlabArt.HEIGHT, 0.0)
		_add_mesh(TerrainPropsArt.props(terrain, index, 3), ClayMaterials.terrain(), top)
		for seat in 4:
			var angle := deg_to_rad(30.0 + 60.0 * (seat + 1))
			_add_piece(PieceArt.settlement(), seat, top + Vector3(cos(angle), 0.0, sin(angle)) * 0.8)


func _add_stands() -> void:
	var placements := [
		[Vector3(0.0, 0.0, WaterArt.HALF_DEPTH + 1.6), 0.0, 0],
		[Vector3(0.0, 0.0, -WaterArt.HALF_DEPTH - 1.6), 0.0, 1],
		[Vector3(-WaterArt.HALF_WIDTH - 1.6, 0.0, 0.0), PI * 0.5, 2],
		[Vector3(WaterArt.HALF_WIDTH + 1.6, 0.0, 0.0), PI * 0.5, 3],
	]
	for placement: Array in placements:
		var position: Vector3 = placement[0]
		_add_mesh(TableArt.seat_stand_base(), ClayMaterials.terrain(), position, placement[1])
		_add_mesh(TableArt.seat_stand_inlay(), ClayMaterials.piece(placement[2]), position, placement[1])


func _add_dice() -> void:
	var rest := Vector3(0.0, DieArt.HALF, 0.0)
	var dice := [[Vector3(-7.9, 0.0, 3.0), 3, 0.5], [Vector3(-7.4, 0.0, 3.5), 5, 1.2]]
	for die: Array in dice:
		var instance := _add_mesh(DieArt.die(), ClayMaterials.stock(), die[0] + rest)
		instance.basis = DieArt.orientation(die[1], die[2])
		var shadow := BlobShadow.create(0.28, 0.4)
		shadow.position = die[0] + Vector3(0.0, BlobShadow.LIFT, 0.0)
		_world.add_child(shadow)
