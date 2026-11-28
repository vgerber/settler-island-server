extends SceneTree
## Renders the whole 3D table UI as one scene around the real board: a standard island from the board fixtures,
## the real `BoardScene` with pieces and stands, the dice tray, the real `CameraRig` default view, and every
## fixture of `OwnSideArt`, `SeatStationArt` and `BankArt` at its place of the layout map
## (doc/design/hud-drafts/crafted-table.md). Three states (turn, trade offer, menus and game over) at the default
## camera, plus close-ups. The stills go to `<output directory>/table_<renderer>_<size>_<shot>.png`.
## Needs a window, quits by itself.
## Usage: godot --path client/godot --position 200,200 --rendering-method gl_compatibility \
##   -s tools/table_ui_gallery.gd -- <output directory> [<board fixtures.json>] [<width>x<height>]
## The fixtures come from `cargo test -p settler_island_client_generator` (target/tmp/godot-board-fixtures.json).

const SETTLE_FRAMES := 10
const CREAM := Color("#F3EADB")
const INK := Color("#231C17")
const BOLD_FONT := "res://theme/fonts/Bitter-Bold.res"
const LABEL_FONT := "res://theme/fonts/AtkinsonHyperlegible-Bold.res"
## The local seat stands at the front, nearest the camera.
const OWN_SEAT := 0
const REFERENCE := Vector2(1600.0, 900.0)
## Fixtures stand this far above the sea hexes, clear of the swell of their surface.
const SEA_LIFT := 0.012
## The opponents' hand trays and supply racks are the own side's models at this scale.
const OPPONENT_SCALE := 0.55
## Count chips and knight shields lie on the stand's island edge, in front of the tray.
const CHIP_Z := 0.26
## Opponent plates are bigger than the stand's own scale so their names read at the table's far edges.
const OPPONENT_PLATE_SCALE := 1.4
## Distance of a side plate from the middle of its stand, along the table's z.
const SIDE_PLATE_GAP := 1.35
## Resource cards that pay for a piece, for the mini cards on the rack ledges.
const COSTS := {
	"road": [SiResource.CLAY, SiResource.WOOD],
	"settlement": [SiResource.CLAY, SiResource.WOOD, SiResource.SHEEP, SiResource.WHEAT],
	"city": [SiResource.WHEAT, SiResource.WHEAT, SiResource.ORE, SiResource.ORE, SiResource.ORE],
}
## Pieces still in the own rack: the rest stand on the board.
const OWN_SUPPLY := {"road": 10, "settlement": 3, "city": 3}
const HAND_COUNTS := [2, 3, 1, 2, 2]
const BANK_PILES: Array[int] = [16, 17, 8, 15, 18, 23]
## Screen anchors in reference pixels (1600x900) of the layout map.
const ANCHORS := {
	"sign": Vector2(270.0, 105.0),
	"awards": Vector2(1490.0, 140.0),
	"bank": Vector2(1484.0, 612.0),
	"token": Vector2(1400.0, 520.0),
	"bell": Vector2(1525.0, 800.0),
	"mat": Vector2(190.0, 665.0),
	"settings": Vector2(190.0, 665.0),
	"ledger": Vector2(1290.0, 105.0),
	"title": Vector2(485.0, 95.0),
	"hand": Vector2(450.0, 855.0),
	"rack": Vector2(905.0, 858.0),
	"plate": Vector2(140.0, 790.0),
}
## Seat stations: name, points, hand cards, development cards, knights, supply left (roads, settlements, cities).
const STATIONS := {
	1: {"name": "Bot 2", "points": "8", "hand": 8, "development": 2, "knights": 1, "supply": [11, 3, 3]},
	2: {"name": "Bot 3", "points": "6", "hand": 5, "development": 1, "knights": 2, "supply": [12, 4, 3]},
	3: {"name": "Bot 1", "points": "5", "hand": 7, "development": 0, "knights": 0, "supply": [10, 3, 4]},
}

var _viewport: SubViewport
var _rig := CameraRig.new()
var _closeup_camera := Camera3D.new()
var _scene := BoardScene.new()
var _geometry: BoardGeometry
var _layout: TableLayout
var _fixtures := Node3D.new()
var _message: Dictionary = {}
var _output_directory := ""
var _size := Vector2i(1600, 900)
var _renderer := ""
var _shots: Array[Dictionary] = []
var _frames_left := -1
var _exit_code := 0
var _built := false
var _state := ""


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty():
		push_error("usage: -s tools/table_ui_gallery.gd -- <output directory> [<fixtures.json>] [<width>x<height>]")
		quit(1)
		return
	_output_directory = arguments[0]
	DirAccess.make_dir_recursive_absolute(_output_directory)
	_renderer = RenderingServer.get_current_rendering_method()
	var fixtures_path := arguments[1] if arguments.size() > 1 else "res://../../target/tmp/godot-board-fixtures.json"
	if arguments.size() > 2:
		var parts := arguments[2].split("x")
		_size = Vector2i(int(parts[0]), int(parts[1]))
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixtures_path))
	_message = (fixtures["middle"] as Dictionary).duplicate(true)
	_message["type"] = "GameStarted"
	_build_viewport()


## The player view of a state: the turn, a trade offer from seat 1, or a finished game won by seat 1.
func _view_for(state: String) -> SiPlayerView:
	var message := _message.duplicate(true)
	var view: Dictionary = message["view"]
	view["current"] = OWN_SEAT
	view["own"]["hand"] = HAND_COUNTS
	view["phase"] = {"type": "Main"}
	if state == "trade":
		view["current"] = 1
		view["phase"] = {"type": "TradeOffered", "offer": {"offerer": 1, "give": [0, 2, 0, 0, 0], "receive": [0, 0, 0, 1, 0], "answers": [[2, false]], "addressed": null}}
	if state == "menus":
		view["current"] = 1
		view["phase"] = {"type": "Finished", "winner": 1}
	return (SiServerMessage.from_dict(message) as SiServerMessageGameStarted).view


func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = _size
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_viewport.add_child(_scene)
	_fixtures.name = "Fixtures"
	_viewport.add_child(_fixtures)
	_viewport.add_child(_rig)
	_closeup_camera.fov = CameraRig.FIELD_OF_VIEW
	_viewport.add_child(_closeup_camera)


func _build_board() -> void:
	var view := _view_for("turn")
	_geometry = BoardGeometry.new(view.board)
	_scene.build(view.board, _geometry)
	_scene.sync(view.board, _geometry)
	_layout = TableLayout.new(_scene, _geometry)
	var tray := MeshInstance3D.new()
	tray.mesh = TableArt.dice_tray()
	tray.material_override = ClayMaterials.terrain()
	tray.position = _layout.tray_center()
	_viewport.add_child(tray)
	for index in 2:
		var die := MeshInstance3D.new()
		die.mesh = DieArt.die()
		die.material_override = ClayMaterials.terrain()
		die.transform = Transform3D(DieArt.orientation([3, 5][index], 0.3 + index), _layout.dice_rest(index))
		_viewport.add_child(die)
	_rig.set_viewport_size(Vector2(_size))
	_rig.frame(_geometry)
	_rig.camera.current = true


func _plan_shots() -> Array[Dictionary]:
	return [
		{"name": "turn", "state": "turn"},
		{"name": "trade", "state": "trade"},
		{"name": "menus", "state": "menus"},
		{"name": "closeup_own", "state": "turn", "look": "hand", "distance": 4.2},
		{"name": "closeup_rack", "state": "turn", "look": "rack", "distance": 3.2},
		{"name": "closeup_opponent", "state": "trade", "look": "left", "distance": 4.4},
		{"name": "closeup_bank", "state": "turn", "look": "bank", "distance": 4.4},
		{"name": "closeup_trade", "state": "trade", "look": "mat", "distance": 4.0},
		{"name": "closeup_menus", "state": "menus", "look": "settings", "distance": 4.2},
	]


func _process(_delta: float) -> bool:
	if not _built:
		# The nodes are in the tree only after the first frame, which the camera rig's fit needs.
		_built = true
		_build_board()
		_shots = _plan_shots()
		_begin_shot()
		return false
	if _frames_left > 0:
		_frames_left -= 1
		return false
	_save(_shots.pop_front())
	if _shots.is_empty():
		quit(_exit_code)
		return true
	_begin_shot()
	return false


## Sets the state and the camera of the first shot; its picture is taken after the settle frames.
func _begin_shot() -> void:
	var shot: Dictionary = _shots[0]
	if shot["state"] != _state:
		_build_state(shot["state"])
	_closeup_camera.current = shot.has("look")
	_rig.camera.current = not shot.has("look")
	if shot.has("look"):
		var target := _look_target(shot["look"])
		var pitch := deg_to_rad(CameraRig.DEFAULT_PITCH)
		_closeup_camera.position = target + Vector3(0.0, sin(pitch), cos(pitch)) * float(shot["distance"])
		_closeup_camera.look_at(target)
	_frames_left = SETTLE_FRAMES


func _look_target(look: String) -> Vector3:
	match look:
		"left":
			return _scene_point(_stand_position(1)) + Vector3(0.4, 0.0, 0.0)
		"settings":
			return _anchor_point("settings") + Vector3(0.0, 0.0, -0.3)
		_:
			return _anchor_point(look)


func _build_state(state: String) -> void:
	_state = state
	for child in _fixtures.get_children():
		_fixtures.remove_child(child)
		child.queue_free()
	var view := _view_for(state)
	_scene.sync_stands(view, _geometry)
	_build_own_side(state)
	for seat: int in STATIONS:
		_build_station(seat, state)
	_build_awards()
	_build_bank()
	if state == "trade":
		_build_trade_mat()
	if state == "menus":
		_build_menus()


## The world point on the sea plane under a reference pixel, seen through the default camera.
func _ground(reference_pixel: Vector2) -> Vector3:
	var pixel := reference_pixel * Vector2(_size) / REFERENCE
	var camera := _rig.camera
	var origin := camera.project_ray_origin(pixel)
	var direction := camera.project_ray_normal(pixel)
	var height := WaterArt.HEIGHT + SEA_LIFT
	return origin + direction * ((height - origin.y) / direction.y)


func _anchor_point(anchor: String) -> Vector3:
	return _ground(ANCHORS[anchor])


func _scene_point(position: Vector3) -> Vector3:
	return Vector3(position.x, WaterArt.HEIGHT + SEA_LIFT, position.z)


func _stand_position(seat: int) -> Vector3:
	return BoardArt.stand_placement(seat, _geometry.bounds)["position"]


func _frame(position: Vector3, yaw := 0.0, scale := 1.0) -> Node3D:
	var frame := Node3D.new()
	frame.position = position
	frame.rotation.y = yaw
	frame.scale = Vector3.ONE * scale
	_fixtures.add_child(frame)
	return frame


func _mesh(parent: Node3D, mesh: Mesh, material: Material, transform := Transform3D.IDENTITY) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.transform = transform
	parent.add_child(instance)
	return instance


func _shadow(parent: Node3D, half_extent: Vector2, strength := 0.4) -> void:
	var shadow := BlobShadow.create(1.0, strength)
	shadow.scale = Vector3(half_extent.x * 2.4, 1.0, half_extent.y * 2.4)
	parent.add_child(shadow)


func _label(parent: Node3D, text: String, transform: Transform3D, height: float, color := CREAM, bold := true) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = load(BOLD_FONT if bold else LABEL_FONT)
	label.font_size = 96
	label.pixel_size = height / 96.0
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.transform = transform
	parent.add_child(label)
	return label


## A transform laying a label flat (facing up) at `point`.
static func _flat(point: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), point)


func _chip_label(parent: Node3D, chip: Transform3D, text: String) -> void:
	var transform := chip
	transform.origin += chip.basis.y * (SeatStationArt.CHIP_TOP + 0.003)
	transform.basis *= SeatStationArt.label_basis()
	_label(parent, text, transform, 0.085, INK)


# Own side: hand tray, supply rack, plate, bell, prompt sign.

func _build_own_side(state: String) -> void:
	_build_hand()
	_build_supply_rack()
	_build_own_plate()
	_build_bell(state == "trade")
	_build_prompt_sign(state)


func _build_hand() -> void:
	var tray := _frame(_anchor_point("hand"))
	_mesh(tray, OwnSideArt.hand_tray(), ClayMaterials.terrain())
	_shadow(tray, Vector2(OwnSideArt.HAND_HALF_WIDTH, 0.4))
	for slot in SiResource.VALUES.size():
		for layer in int(HAND_COUNTS[slot]):
			var lift := Transform3D(Basis.IDENTITY, Vector3(0.012 * layer, CardArt.THICKNESS * layer, -0.05 * layer))
			_mesh(tray, CardArt.resource_card(SiResource.VALUES[slot]), ClayMaterials.stock(), OwnSideArt.hand_slot(slot) * lift)
		_add_hand_count(tray, slot, int(HAND_COUNTS[slot]))
	# Development cards: two knights stacked, a victory point card, and the card bought this turn, lying lower.
	var development := [["Knight", 0, 0.0, 0.0], ["Knight", 1, 0.0, 0.0], ["VictoryPoint", 0, 0.22, 0.0], ["Monopoly", 0, 0.44, 0.06]]
	for entry: Array in development:
		var layer: int = entry[1]
		var offset := Transform3D(Basis.IDENTITY, Vector3(-0.22 + float(entry[2]) + 0.012 * layer, CardArt.THICKNESS * layer, float(entry[3]) - 0.05 * layer))
		_mesh(tray, CardArt.development_card(entry[0]), ClayMaterials.stock(), OwnSideArt.hand_slot(5) * offset)
	_add_dev_count(tray, 2)


func _add_dev_count(tray: Node3D, count: int) -> void:
	var corner := OwnSideArt.hand_slot(5) * Transform3D(Basis.IDENTITY, Vector3(-0.22 + CardArt.HALF.x - 0.02, 0.03 + CardArt.THICKNESS, -CardArt.HALF.y - 0.05))
	_mesh(tray, SeatStationArt.dev_count_chip(), ClayMaterials.stock(), corner)
	_chip_label(tray, corner, str(count))


## The count chip at the top-right corner of a stack, lying on the slope.
func _add_hand_count(tray: Node3D, slot: int, count: int) -> void:
	var corner := OwnSideArt.hand_slot(slot) * Transform3D(Basis.IDENTITY, Vector3(CardArt.HALF.x - 0.02 + 0.012 * count, 0.03 + CardArt.THICKNESS * count, -CardArt.HALF.y - 0.05 * count))
	_mesh(tray, SeatStationArt.count_chip(), ClayMaterials.stock(), corner)
	_chip_label(tray, corner, str(count))


func _build_supply_rack() -> void:
	var rack := _frame(_anchor_point("rack"))
	_mesh(rack, OwnSideArt.supply_rack(), ClayMaterials.terrain())
	_shadow(rack, Vector2(OwnSideArt.RACK_HALF_WIDTH, OwnSideArt.RACK_HALF_DEPTH))
	var meshes := {"road": PieceArt.road(), "settlement": PieceArt.settlement(), "city": PieceArt.city()}
	for kind: String in OwnSideArt.RACK_ROWS:
		var count: int = OwnSideArt.RACK_ROWS[kind]["count"]
		for index in range(count - int(OWN_SUPPLY[kind]), count):
			_mesh(rack, meshes[kind], ClayMaterials.piece(OWN_SEAT), OwnSideArt.supply_piece(kind, index))
		_add_cost_cards(rack, kind)


## The cost of a piece as mini cards standing on the ledge in front of its row.
func _add_cost_cards(rack: Node3D, kind: String) -> void:
	var costs: Array = COSTS[kind]
	var ledge := OwnSideArt.supply_ledge(kind)
	var turn := Basis(Vector3.RIGHT, OwnSideArt.COST_CARD_LEAN).scaled_local(Vector3.ONE * OwnSideArt.COST_CARD_SCALE)
	for index in costs.size():
		var foot := ledge + Vector3((index - (costs.size() - 1) * 0.5) * OwnSideArt.COST_CARD_PITCH, 0.0, 0.0)
		_mesh(rack, CardArt.resource_card(costs[index]), ClayMaterials.stock(), Transform3D(turn, foot))


func _build_own_plate() -> void:
	var frame := _frame(_anchor_point("plate"), 0.0, 1.25)
	_add_plate(frame, OWN_SEAT, "Lin", "7", "")


func _build_bell(covered: bool) -> void:
	var bell := _frame(_anchor_point("bell"))
	_mesh(bell, OwnSideArt.bell(), ClayMaterials.terrain())
	_shadow(bell, Vector2(0.4, 0.4))
	if covered:
		_mesh(bell, OwnSideArt.bell_cover(), ClayMaterials.terrain(), Transform3D(Basis.IDENTITY, Vector3(0.0, OwnSideArt.BELL_BASE_HEIGHT, 0.0)))
		return
	var plate := Transform3D(Basis(Vector3.RIGHT, SeatStationArt.PLATE_TILT), Vector3(0.0, 0.0, 0.5))
	_label(bell, "End turn", plate * _flat(Vector3(0.0, 0.01, 0.0)), 0.1)


func _build_prompt_sign(state: String) -> void:
	var text := {"turn": "Place a road", "trade": "Answer Bot 2's trade", "menus": "Game over"}[state] as String
	var seat := OWN_SEAT if state == "turn" else 1
	var board := _frame(_anchor_point("sign"))
	_mesh(board, OwnSideArt.prompt_sign(), ClayMaterials.terrain())
	_mesh(board, OwnSideArt.prompt_sign_tab(), ClayMaterials.piece(seat))
	_shadow(board, Vector2(1.2, 0.5))
	var label := _label(board, text, OwnSideArt.sign_text(), 0.22)
	label.width = OwnSideArt.SIGN_TEXT_WIDTH / label.pixel_size


# Seat stations of the opponents.

func _build_station(seat: int, state: String) -> void:
	var data: Dictionary = STATIONS[seat]
	var position := _stand_position(seat)
	position.y = BoardScene.WIN_RAISE if state == "menus" and seat == 1 else 0.0
	var frame := _frame(position, _station_yaw(seat))
	_add_opponent_hand(frame, data)
	_add_opponent_rack(frame, seat, data["supply"])
	for index in int(data["knights"]):
		var shield := SeatStationArt.shield_slot(index)
		shield.origin.z = CHIP_Z
		_mesh(frame, SeatStationArt.knight_shield(), ClayMaterials.piece(seat), shield)
	# Plates on the side stands face the camera, above the tray; the back plate sits toward the island.
	var plate_position := position
	if seat != 2:
		plate_position += Vector3(0.0, 0.0, -SIDE_PLATE_GAP) - SeatStationArt.PLATE_OFFSET * OPPONENT_PLATE_SCALE
	var plate := _frame(plate_position, 0.0, OPPONENT_PLATE_SCALE)
	_add_plate(plate, seat, data["name"], data["points"], _station_token(seat, state))


## The own hand tray at the opponent scale on the stand, with card backs spread over the five slots and development
## backs in the plum section, and one count chip for the whole hand.
func _add_opponent_hand(frame: Node3D, data: Dictionary) -> void:
	var tray := Node3D.new()
	tray.position = Vector3(0.0, SeatStationArt.STAND_TOP, 0.0)
	tray.scale = Vector3.ONE * OPPONENT_SCALE
	frame.add_child(tray)
	_mesh(tray, OwnSideArt.hand_tray(), ClayMaterials.terrain())
	var hand := int(data["hand"])
	for slot in 5:
		var count := hand / 5 + (1 if slot < hand % 5 else 0)
		for layer in count:
			var lift := Transform3D(Basis.IDENTITY, Vector3(0.012 * layer, CardArt.THICKNESS * layer, -0.05 * layer))
			_mesh(tray, CardArt.card_back(), ClayMaterials.stock(), OwnSideArt.hand_slot(slot) * lift)
	for layer in int(data["development"]):
		var lift := Transform3D(Basis.IDENTITY, Vector3(0.012 * layer, CardArt.THICKNESS * layer, -0.05 * layer))
		_mesh(tray, CardArt.dev_back(), ClayMaterials.stock(), OwnSideArt.hand_slot(5) * lift)
	var chip := Transform3D(Basis(Vector3.RIGHT, SeatStationArt.PLATE_TILT), Vector3(-OwnSideArt.HAND_HALF_WIDTH * OPPONENT_SCALE, SeatStationArt.STAND_TOP, CHIP_Z))
	_add_count_chip(frame, SeatStationArt.count_chip(), chip.origin, str(hand))
	if int(data["development"]) > 0:
		_add_count_chip(frame, SeatStationArt.dev_count_chip(), Vector3(OwnSideArt.HAND_DEV_SLOT * OPPONENT_SCALE, SeatStationArt.STAND_TOP, CHIP_Z), str(data["development"]))


## The own supply rack at the opponent scale with their remaining pieces; the empty sockets show what is built.
func _add_opponent_rack(frame: Node3D, seat: int, left: Array) -> void:
	var rack := Node3D.new()
	# Side racks stand outside their stand; the back rack beside it, where the table edge leaves room.
	rack.position = Vector3(-2.2, 0.0, 0.0) if seat == 2 else Vector3(0.0, 0.0, -0.62)
	rack.position.y = WaterArt.HEIGHT + SEA_LIFT
	rack.scale = Vector3.ONE * OPPONENT_SCALE
	frame.add_child(rack)
	_mesh(rack, OwnSideArt.supply_rack(), ClayMaterials.terrain())
	var kinds := ["road", "settlement", "city"]
	var meshes := [PieceArt.road(), PieceArt.settlement(), PieceArt.city()]
	for kind_index in kinds.size():
		var count: int = OwnSideArt.RACK_ROWS[kinds[kind_index]]["count"]
		for index in range(count - int(left[kind_index]), count):
			_mesh(rack, meshes[kind_index], ClayMaterials.piece(seat), OwnSideArt.supply_piece(kinds[kind_index], index))


## The stations face the island: left toward +x, right toward -x, back and front toward +z.
func _station_yaw(seat: int) -> float:
	return [0.0, PI / 2.0, 0.0, -PI / 2.0][seat]


func _station_token(seat: int, state: String) -> String:
	if state != "trade":
		return ""
	return {1: SeatStationArt.OFFERING, 2: SeatStationArt.DECLINED, 3: SeatStationArt.WAITING}.get(seat, "")


func _add_plate(frame: Node3D, seat: int, player_name: String, points: String, token: String) -> void:
	var plate := Transform3D(Basis.IDENTITY, SeatStationArt.PLATE_OFFSET)
	_mesh(frame, SeatStationArt.name_plate(), ClayMaterials.terrain(), plate)
	_mesh(frame, SeatStationArt.name_plate_stripe(), ClayMaterials.piece(seat), plate)
	var label := SeatStationArt.plate_surface(SeatStationArt.PLATE_LABEL_X)
	label.origin += label.basis.y * 0.003
	label.basis *= SeatStationArt.label_basis()
	_label(frame, player_name, label, 0.1)
	var chip := SeatStationArt.plate_surface(SeatStationArt.PLATE_CHIP_X)
	_mesh(frame, SeatStationArt.points_chip(), ClayMaterials.stock(), chip)
	_chip_label(frame, chip, points)
	if token != "":
		_mesh(frame, SeatStationArt.token(token), ClayMaterials.stock(), SeatStationArt.plate_surface(SeatStationArt.PLATE_TOKEN_X))


func _add_count_chip(frame: Node3D, mesh: Mesh, offset: Vector3, text: String) -> void:
	var chip := Transform3D(Basis(Vector3.RIGHT, SeatStationArt.PLATE_TILT), offset)
	_mesh(frame, mesh, ClayMaterials.stock(), chip)
	_chip_label(frame, chip, text)


# Award board, bank and trade token.

func _build_awards() -> void:
	var board := _frame(_anchor_point("awards"))
	_mesh(board, SeatStationArt.award_board(), ClayMaterials.terrain())
	_shadow(board, Vector2(0.78, 0.4))
	for kind in [SeatStationArt.LONGEST_ROAD, SeatStationArt.LARGEST_ARMY]:
		var text := "Longest road" if kind == SeatStationArt.LONGEST_ROAD else "Largest army"
		var label := SeatStationArt.award_label(kind)
		label.basis *= SeatStationArt.label_basis()
		_label(board, text, label, 0.1, CREAM, false)
	_mesh(board, SeatStationArt.award_plaque(SeatStationArt.LONGEST_ROAD), ClayMaterials.terrain(), SeatStationArt.award_socket(SeatStationArt.LONGEST_ROAD))


func _build_bank() -> void:
	var rack := _frame(_anchor_point("bank"))
	_mesh(rack, BankArt.bank_rack(), ClayMaterials.terrain())
	_shadow(rack, Vector2(BankArt.RACK_HALF_WIDTH, BankArt.RACK_HALF_DEPTH))
	for index in BankArt.BAY_COUNT:
		var resource := BankArt.bay_resource(index)
		var mesh: Mesh = CardArt.dev_back() if resource.is_empty() else CardArt.resource_card(resource)
		_add_pile(rack, BankArt.pile_point(index), BANK_PILES[index], mesh)
	_add_bank_counts(rack)
	var token := _frame(_anchor_point("token"))
	_mesh(token, BankArt.trade_token(), ClayMaterials.terrain())
	_shadow(token, Vector2(0.08, 0.08))


## A count chip behind (top row) or in front of (bottom row) the pile of every bay, tilted toward the camera.
func _add_bank_counts(rack: Node3D) -> void:
	for index in BankArt.BAY_COUNT:
		var bay := BankArt.bay_centre(index)
		var side := -1.0 if bay.z < 0.0 else 1.0
		var chip := Transform3D(Basis(Vector3.RIGHT, SeatStationArt.PLATE_TILT), Vector3(bay.x, 0.0, bay.z + side * (BankArt.BAY_HALF_Z + 0.2)))
		var dev := BankArt.bay_resource(index).is_empty()
		_mesh(rack, SeatStationArt.dev_count_chip() if dev else SeatStationArt.count_chip(), ClayMaterials.stock(), chip)
		_chip_label(rack, chip, str(BANK_PILES[index]))


## A heap of `count` cards, each turned a little so the pile reads as cards.
func _add_pile(parent: Node3D, base: Vector3, count: int, mesh: Mesh) -> void:
	for index in count:
		var layer := base + Vector3(0.006 * sin(index * 1.7), index * CardArt.THICKNESS, 0.0)
		_mesh(parent, mesh, ClayMaterials.stock(), Transform3D(Basis(Vector3.UP, 0.05 * sin(index * 2.3)), layer))


func _build_trade_mat() -> void:
	var mat := _frame(_anchor_point("mat"))
	_mesh(mat, BankArt.trade_mat(), ClayMaterials.terrain())
	_shadow(mat, Vector2(BankArt.MAT_HALF_WIDTH, BankArt.MAT_HALF_DEPTH))
	var gives := BankArt.mat_card_point(-1)
	for index in 2:
		_mesh(mat, CardArt.resource_card(SiResource.WOOD), ClayMaterials.stock(), Transform3D(Basis.IDENTITY, gives + Vector3((index - 0.5) * 0.2, index * CardArt.THICKNESS, 0.0)))
	_mesh(mat, CardArt.resource_card(SiResource.WHEAT), ClayMaterials.stock(), Transform3D(Basis.IDENTITY, BankArt.mat_card_point(1)))
	_label(mat, "Bot 2 gives", _flat(Vector3(-BankArt.MAT_HALF_X, BankArt.MAT_FELT + 0.002, BankArt.MAT_LABEL_Z)), 0.1)
	_label(mat, "You give", _flat(Vector3(BankArt.MAT_HALF_X, BankArt.MAT_FELT + 0.002, BankArt.MAT_LABEL_Z)), 0.1)
	for side in [-1, 1]:
		_add_button(mat, side)


func _add_button(mat: Node3D, side: int) -> void:
	var kind := BankArt.ButtonKind.TEAL if side < 0 else BankArt.ButtonKind.EMBER
	var button := _mesh(mat, BankArt.wood_button(kind), ClayMaterials.terrain(), Transform3D(Basis.IDENTITY, BankArt.mat_button_point(side)))
	_label(button, "Accept" if side < 0 else "Decline", _flat(Vector3(0.0, BankArt.BUTTON_TOP + 0.002, 0.0)), 0.1)


# Menus: settings board, ledger and the title sign.

func _build_menus() -> void:
	var board := _frame(_anchor_point("settings"))
	_mesh(board, BankArt.settings_board(), ClayMaterials.terrain())
	_shadow(board, Vector2(BankArt.BOARD_HALF_WIDTH, BankArt.BOARD_HALF_DEPTH))
	var top := BankArt.BOARD_TOP + 0.002
	_label(board, "Settings", _flat(Vector3(0.0, top + 0.004, BankArt.BOARD_TITLE_Z)), 0.15)
	var names := ["Volume", "Animation speed", "Quality", "Colour-blind aid", "Clean view"]
	for index in names.size():
		_label(board, names[index], _flat(Vector3(BankArt.BOARD_LABEL_X + 0.4, top, BankArt.BOARD_ROW_Z[index])), 0.09, CREAM, false)
	var values := [0.8, 0.5, 0.0]
	for index in 3:
		_mesh(board, BankArt.slider_knob(), ClayMaterials.terrain(), Transform3D(Basis.IDENTITY, BankArt.slider_point(index, values[index])))
	_mesh(board, BankArt.toggle_knob(), ClayMaterials.terrain(), Transform3D(Basis.IDENTITY, BankArt.toggle_point(0, true)))
	_mesh(board, BankArt.toggle_knob(), ClayMaterials.terrain(), Transform3D(Basis.IDENTITY, BankArt.toggle_point(1, false)))
	_build_ledger()
	var title := _frame(_anchor_point("title"))
	_mesh(title, BankArt.title_sign(), ClayMaterials.terrain())
	_shadow(title, Vector2(0.75, 0.2))
	_label(title, "Bot 2 wins", BankArt.sign_face(), 0.3)


func _build_ledger() -> void:
	var ledger := _frame(_anchor_point("ledger"))
	_mesh(ledger, BankArt.ledger(true), ClayMaterials.terrain())
	_shadow(ledger, Vector2(0.66, 0.43))
	var left := ["Lin: rolled 8", "got 1 ore", "built a road", "Bot 2: rolled 5"]
	var right := ["Bot 3: rolled 11", "got 2 wood", "bought a card", "Lin: rolled 6"]
	for side in [-1, 1]:
		var lines: Array = left if side < 0 else right
		for index in lines.size():
			var line := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.0, -0.28 + index * 0.18))
			_label(ledger, lines[index], BankArt.ledger_page_transform(side) * line, 0.065, Palette.INK, false)


func _save(shot: Dictionary) -> void:
	var path := _output_directory.path_join("table_%s_%dx%d_%s.png" % [_renderer_name(), _size.x, _size.y, shot["name"]])
	var error := _viewport.get_texture().get_image().save_png(path)
	print("saved %s (%d)" % [path, error])
	if error != OK:
		push_error("table_ui_gallery: saving %s failed (%d)" % [path, error])
		_exit_code = 1


func _renderer_name() -> String:
	return "compatibility" if _renderer == "gl_compatibility" else _renderer
