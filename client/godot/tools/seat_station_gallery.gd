extends SceneTree
## Renders stills of the seat-station fixtures (`SeatStationArt`): a small island with full stations for three
## opponents at the seat stand positions, the award board and a lineup of parts, from the default camera and in
## close-ups. The stills go to `<output directory>/seat_<renderer>_<shot>.png` at 1600x900 and the triangle counts
## of every mesh are printed. Needs a window, quits by itself.
## Usage: godot --path client/godot --position 200,200 --rendering-method gl_compatibility \
##   -s tools/seat_station_gallery.gd -- <output directory>

const SIZE := Vector2i(1600, 900)
const SETTLE_FRAMES := 8
const SQUARE_ROOT_OF_THREE := 1.7320508
const FIELD_OF_VIEW := 38.0
const PITCH := deg_to_rad(55.0)
const TILES := [
	[0, 0, "Desert", 0],
	[1, 0, "Clay", 6],
	[0, 1, "Wood", 8],
	[-1, 1, "Sheep", 11],
	[-1, 0, "Wheat", 12],
	[0, -1, "Ore", 2],
	[1, -1, "Wood", 5],
]
const BOT_STAND_DISTANCE := 1.6
## [position, yaw, seat, name, points, hand cards, development cards, knights, roads, settlements and cities left].
const STATIONS := [
	[Vector3(0.0, 0.0, -WaterArt.HALF_DEPTH - BOT_STAND_DISTANCE), 0.0, 1, "Bot 3", "7", 6, 2, 2, [11, 3, 3], WAITING_TOKEN],
	[Vector3(-WaterArt.HALF_WIDTH - BOT_STAND_DISTANCE, 0.0, 0.0), PI * 0.5, 2, "Bot 2", "4", 8, 0, 1, [15, 5, 4], ""],
	[Vector3(WaterArt.HALF_WIDTH + BOT_STAND_DISTANCE, 0.0, 0.0), -PI * 0.5, 3, "Bot 1", "10", 3, 1, 0, [6, 1, 0], ""],
]
const WAITING_TOKEN := SeatStationArt.WAITING
const LINEUP_ORIGIN := Vector3(0.0, 0.0, 6.3)
const FONT_TITLE := "res://theme/fonts/Bitter-Bold.res"
const FONT_LABEL := "res://theme/fonts/AtkinsonHyperlegible-Bold.res"

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
		push_error("usage: -s tools/seat_station_gallery.gd -- <output directory>")
		quit(1)
		return
	_output_directory = arguments[0]
	DirAccess.make_dir_recursive_absolute(_output_directory)
	_renderer = RenderingServer.get_current_rendering_method()
	_build_viewport()
	_build_scene()
	_print_triangle_counts()
	var top: Vector3 = STATIONS[0][0]
	var left: Vector3 = STATIONS[1][0]
	var right: Vector3 = STATIONS[2][0]
	_shots = [
		_shot("default", Vector3(0.0, 0.0, 0.3), 24.0, PITCH),
		_shot("top_station", top + Vector3(0.0, 0.1, 0.35), 5.4, PITCH),
		_shot("left_station", left + Vector3(0.35, 0.1, 0.0), 5.4, PITCH),
		_shot("right_station", right + Vector3(-0.35, 0.1, 0.0), 5.4, PITCH),
		_shot("plate_close", top + SeatStationArt.PLATE_OFFSET + Vector3(0.0, 0.1, 0.0), 1.7, PITCH),
		_shot("holder_close", top + SeatStationArt.HOLDER_OFFSET + Vector3(0.0, 0.1, 0.0), 2.0, PITCH),
		_shot("supply_close", top + SeatStationArt.RACK_OFFSET, 2.4, PITCH),
		_shot("parts", LINEUP_ORIGIN + Vector3(1.0, 0.1, 0.0), 4.6, PITCH),
		_shot("awards_close", LINEUP_ORIGIN + Vector3(-3.0, 0.05, 0.0), 2.2, PITCH),
		_shot("tokens_close", LINEUP_ORIGIN + Vector3(0.6, 0.0, 0.0), 1.1, deg_to_rad(60.0)),
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
	var path := _output_directory.path_join("seat_%s_%s.png" % [_renderer_name(), shot["name"]])
	var error := _viewport.get_texture().get_image().save_png(path)
	print("saved %s (%d)" % [path, error])
	if error != OK:
		push_error("seat_station_gallery: saving %s failed (%d)" % [path, error])
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
	_add_mesh(_world, TableArt.table(), ClayMaterials.table(), Transform3D.IDENTITY)
	var land: Array[Vector2] = []
	for tile: Array in TILES:
		var position := _tile_position(tile[0], tile[1])
		land.append(Vector2(position.x, position.z))
		_add_tile(tile[0], tile[1], tile[2], tile[3])
	_world.add_child(BoardArt.water(WaterArt.cells(land)))
	for station: Array in STATIONS:
		_add_station(station)
	_add_lineup()


func _tile_position(q: int, r: int) -> Vector3:
	return Vector3(SQUARE_ROOT_OF_THREE * (q + r / 2.0), 0.0, 1.5 * r)


func _add_tile(q: int, r: int, terrain: String, number: int) -> void:
	var centre := _tile_position(q, r)
	_add_mesh(_world, HexSlabArt.slab(terrain), ClayMaterials.terrain(), Transform3D(Basis.IDENTITY, centre))
	var top := Transform3D(Basis.IDENTITY, centre + Vector3(0.0, HexSlabArt.HEIGHT, 0.0))
	_add_mesh(_world, TerrainPropsArt.props(terrain, q, r), ClayMaterials.terrain(), top)
	if number > 0:
		_add_mesh(_world, ChipArt.chip(number), ClayMaterials.stock(), top)


func _add_mesh(parent: Node3D, mesh: Mesh, material: Material, transform: Transform3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.transform = transform
	parent.add_child(instance)
	return instance


func _add_label(parent: Node3D, text: String, transform: Transform3D, height: float, color: Color, font_path: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = load(font_path)
	label.font_size = 96
	label.pixel_size = height / 96.0
	label.modulate = color
	label.shaded = false
	label.double_sided = false
	label.transform = transform
	parent.add_child(label)


## One seat station in its own frame, rotated to face the island.
func _add_station(station: Array) -> void:
	var frame := Node3D.new()
	frame.position = station[0]
	frame.rotation.y = station[1]
	_world.add_child(frame)
	var seat: int = station[2]
	_add_mesh(frame, TableArt.seat_stand_base(), ClayMaterials.terrain(), Transform3D.IDENTITY)
	_add_mesh(frame, TableArt.seat_stand_inlay(), ClayMaterials.piece(seat), Transform3D.IDENTITY)
	_add_plate(frame, seat, station[3], station[4], station[9])
	_add_hand(frame, seat, station[5], station[6], station[7])
	_add_supply(frame, seat, station[8])


func _add_plate(frame: Node3D, seat: int, player_name: String, points: String, token: String) -> void:
	var plate := Transform3D(Basis.IDENTITY, SeatStationArt.PLATE_OFFSET)
	_add_mesh(frame, SeatStationArt.name_plate(), ClayMaterials.terrain(), plate)
	_add_mesh(frame, SeatStationArt.name_plate_stripe(), ClayMaterials.piece(seat), plate)
	var label := SeatStationArt.plate_surface(SeatStationArt.PLATE_LABEL_X)
	label.origin += label.basis.y * 0.003
	label.basis *= SeatStationArt.label_basis()
	_add_label(frame, player_name, label, 0.1, SeatStationArt.CREAM, FONT_TITLE)
	var chip := SeatStationArt.plate_surface(SeatStationArt.PLATE_CHIP_X)
	_add_mesh(frame, SeatStationArt.points_chip(), ClayMaterials.stock(), chip)
	_add_chip_label(frame, chip, points)
	if token != "":
		var disc := SeatStationArt.plate_surface(SeatStationArt.PLATE_TOKEN_X)
		_add_mesh(frame, SeatStationArt.token(token), ClayMaterials.stock(), disc)


func _add_chip_label(frame: Node3D, chip: Transform3D, text: String) -> void:
	var transform := chip
	transform.origin += chip.basis.y * (SeatStationArt.CHIP_TOP + 0.003)
	transform.basis *= SeatStationArt.label_basis()
	_add_label(frame, text, transform, 0.085, SeatStationArt.INK, FONT_TITLE)


func _add_hand(frame: Node3D, seat: int, hand: int, development: int, knights: int) -> void:
	var holder := Transform3D(Basis.IDENTITY, SeatStationArt.HOLDER_OFFSET)
	_add_mesh(frame, SeatStationArt.card_holder(), ClayMaterials.terrain(), holder)
	for index in hand:
		_add_mesh(frame, SeatStationArt.card_back(), ClayMaterials.stock(), holder * SeatStationArt.card_slot(index))
	for index in development:
		_add_mesh(frame, SeatStationArt.dev_card_back(), ClayMaterials.stock(), holder * SeatStationArt.dev_slot(index))
	_add_count_chip(frame, SeatStationArt.count_chip(), SeatStationArt.COUNT_CHIP_OFFSET, str(hand))
	if development > 0:
		_add_count_chip(frame, SeatStationArt.dev_count_chip(), SeatStationArt.DEV_CHIP_OFFSET, str(development))
	for index in knights:
		_add_mesh(frame, SeatStationArt.knight_shield(), ClayMaterials.piece(seat), SeatStationArt.shield_slot(index))


func _add_count_chip(frame: Node3D, mesh: Mesh, offset: Vector3, text: String) -> void:
	var chip := Transform3D(Basis(Vector3.RIGHT, SeatStationArt.PLATE_TILT), offset)
	_add_mesh(frame, mesh, ClayMaterials.stock(), chip)
	_add_chip_label(frame, chip, text)


## The rack on the table in front of the stand with the pieces that are left: `left` is [roads, settlements, cities].
func _add_supply(frame: Node3D, seat: int, left: Array) -> void:
	var rack := Transform3D(Basis.IDENTITY, SeatStationArt.RACK_OFFSET)
	_add_mesh(frame, SeatStationArt.mini_supply(), ClayMaterials.terrain(), rack)
	var kinds := [SeatStationArt.ROAD, SeatStationArt.SETTLEMENT, SeatStationArt.CITY]
	var meshes := [PieceArt.road(), PieceArt.settlement(), PieceArt.city()]
	for kind_index in kinds.size():
		for index in left[kind_index]:
			_add_mesh(frame, meshes[kind_index], ClayMaterials.piece(seat), rack * SeatStationArt.supply_slot(kinds[kind_index], index))


## Tokens, chips, a shield, card backs and the award board on the free table in front of the bottom seat.
func _add_lineup() -> void:
	var board := Transform3D(Basis.IDENTITY, LINEUP_ORIGIN + Vector3(-3.0, 0.0, 0.0))
	_add_mesh(_world, SeatStationArt.award_board(), ClayMaterials.terrain(), board)
	_add_mesh(_world, SeatStationArt.award_plaque(SeatStationArt.LONGEST_ROAD), ClayMaterials.terrain(), board * SeatStationArt.award_socket(SeatStationArt.LONGEST_ROAD))
	for kind in [SeatStationArt.LONGEST_ROAD, SeatStationArt.LARGEST_ARMY]:
		var text := "Longest road" if kind == SeatStationArt.LONGEST_ROAD else "Largest army"
		var label := board * SeatStationArt.award_label(kind)
		label.basis *= SeatStationArt.label_basis()
		_add_label(_world, text, label, 0.07, SeatStationArt.CREAM, FONT_LABEL)
	var kinds := [SeatStationArt.WAITING, SeatStationArt.ACCEPTED, SeatStationArt.DECLINED, SeatStationArt.OFFERING, SeatStationArt.DISCARD]
	for index in kinds.size():
		var position := LINEUP_ORIGIN + Vector3(-0.2 + index * 0.2, 0.0, 0.0)
		_add_mesh(_world, SeatStationArt.token(kinds[index]), ClayMaterials.stock(), Transform3D(Basis.IDENTITY, position))
	var tilt := Basis(Vector3.RIGHT, SeatStationArt.PLATE_TILT)
	_add_chip_on_table(SeatStationArt.points_chip(), LINEUP_ORIGIN + Vector3(1.2, 0.0, 0.0), "7", tilt)
	_add_chip_on_table(SeatStationArt.count_chip(), LINEUP_ORIGIN + Vector3(1.45, 0.0, 0.0), "6", tilt)
	_add_chip_on_table(SeatStationArt.dev_count_chip(), LINEUP_ORIGIN + Vector3(1.7, 0.0, 0.0), "2", tilt)
	for seat in 4:
		var place := Transform3D(tilt, LINEUP_ORIGIN + Vector3(2.1 + seat * 0.2, 0.0, 0.0))
		_add_mesh(_world, SeatStationArt.knight_shield(), ClayMaterials.piece(seat), place)
	_add_mesh(_world, SeatStationArt.card_back(), ClayMaterials.stock(), Transform3D(Basis.IDENTITY, LINEUP_ORIGIN + Vector3(3.0, 0.0, 0.0)))
	_add_mesh(_world, SeatStationArt.dev_card_back(), ClayMaterials.stock(), Transform3D(Basis.IDENTITY, LINEUP_ORIGIN + Vector3(3.5, 0.0, 0.0)))


func _add_chip_on_table(mesh: Mesh, position: Vector3, text: String, tilt: Basis) -> void:
	var chip := Transform3D(tilt, position)
	_add_mesh(_world, mesh, ClayMaterials.stock(), chip)
	var transform := chip
	transform.origin += chip.basis.y * (SeatStationArt.CHIP_TOP + 0.003)
	transform.basis *= SeatStationArt.label_basis()
	_add_label(_world, text, transform, 0.085, SeatStationArt.INK, FONT_TITLE)


func _print_triangle_counts() -> void:
	var meshes := {
		"name_plate": SeatStationArt.name_plate(),
		"name_plate_stripe": SeatStationArt.name_plate_stripe(),
		"points_chip": SeatStationArt.points_chip(),
		"count_chip": SeatStationArt.count_chip(),
		"card_holder": SeatStationArt.card_holder(),
		"card_back": SeatStationArt.card_back(),
		"knight_shield": SeatStationArt.knight_shield(),
		"mini_supply": SeatStationArt.mini_supply(),
		"award_board": SeatStationArt.award_board(),
	}
	for kind in [SeatStationArt.WAITING, SeatStationArt.ACCEPTED, SeatStationArt.DECLINED, SeatStationArt.OFFERING, SeatStationArt.DISCARD]:
		meshes["token_" + kind] = SeatStationArt.token(kind)
	for mesh_name: String in meshes:
		var mesh: ArrayMesh = meshes[mesh_name]
		var indices: PackedInt32Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
		print("triangles %s: %d" % [mesh_name, indices.size() / 3])
