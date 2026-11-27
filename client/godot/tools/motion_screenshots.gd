extends SceneTree
## Stills of the 3D motion: the dice in the air and on the tray, a settlement drop, the robber hop and cards in
## flight over the table, on a board built from the `GameStarted` fixtures of the Rust tests. Needs a window.
## Usage: godot --path client/godot --position 200,200 -s tools/motion_screenshots.gd -- <fixtures.json> <output dir>

const SIZE := Vector2i(1600, 900)
const SLOT := Vector2(1260.0, 676.0)

var _board: Board3D = null
var _client := SiClient.new()
var _output := ""
var _begun := false


func _process(_delta: float) -> bool:
	if _begun:
		return false
	_begun = true
	_run()
	return false


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	_output = arguments[1]
	DirAccess.make_dir_recursive_absolute(_output)
	root.size = SIZE
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	var started := SiServerMessage.from_dict(fixtures["middle"]) as SiServerMessageGameStarted
	_board = Board3D.new()
	root.add_child(_board)
	_board.size = SLOT
	_board.hand_slot = func(_resource: String) -> Vector2: return Vector2(520.0, 800.0)
	var player := EventPlayer.new()
	_board.add_child(player)
	player.bind(GameState.new(_client, started))
	_board.bind(player)
	player.speed_factor = 1.0
	await create_timer(0.5).timeout
	await _dice_shots(player)
	await _piece_shots(player)
	await _card_shots(player)
	quit(0)


func _dice_shots(player: EventPlayer) -> void:
	var dice := SiEventDiceRolled.new()
	dice.seat = (player.seat + 1) % player.shown_view.players.size()
	dice.first = 4
	dice.second = 2
	player.event_started.emit(dice)
	await create_timer(0.25).timeout
	_shoot("dice_air")
	await create_timer(0.8).timeout
	_shoot("dice_rest")


func _piece_shots(player: EventPlayer) -> void:
	var board := player.shown_view.board
	var settlement := SiEventSettlementPlaced.new()
	settlement.seat = player.seat
	settlement.corner = board.buildings.find(null)
	player.event_started.emit(settlement)
	var robber := SiEventRobberMoved.new()
	robber.seat = player.seat
	robber.tile = (board.robber + 2) % board.tiles.size()
	player.event_started.emit(robber)
	await create_timer(0.2).timeout
	_shoot("pieces_mid")
	await create_timer(0.6).timeout


func _card_shots(player: EventPlayer) -> void:
	var counts: Array[int] = [2, 1, 2, 1, 2]
	var produced := SiEventResourcesProduced.new()
	produced.seat = player.seat
	produced.resources = counts
	player.event_started.emit(produced)
	var other := SiEventResourcesPaid.new()
	other.seat = (player.seat + 1) % player.shown_view.players.size()
	other.resources = counts
	player.event_started.emit(other)
	await create_timer(0.25).timeout
	_shoot("cards_mid")
	await create_timer(0.7).timeout


func _shoot(shot_name: String) -> void:
	var path := "%s/motion_%s.png" % [_output, shot_name]
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)
