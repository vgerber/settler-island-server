class_name BoardMotion
extends Node3D
## The motion of the 3D table: dice on their tray, pieces dropping in, cards flying over the table. `Board3D`
## creates one, binds it to its `EventPlayer` and calls `commit` after each redraw; the layers listen to the
## player's events themselves. With animations off nothing moves, the dice only appear on their faces.

var dice := DiceTray.new()
var pieces := PieceMotion.new()
var cards := CardFlights.new()

var _player: EventPlayer = null
var _scene: BoardScene = null
var _layout: TableLayout = null
var _layers: Array[MotionLayer] = [dice, pieces, cards]
var _built_corners := -1
var _committed: SiPlayerView = null


func _init() -> void:
	name = "BoardMotion"
	for layer in _layers:
		add_child(layer)


func bind(event_player: EventPlayer, board_scene: BoardScene, rig: CameraRig, flat_parent: BoardView) -> void:
	_player = event_player
	_scene = board_scene
	pieces.scene = board_scene
	cards.rig = rig
	cards.attach_flat_tokens(flat_parent)
	for layer in _layers:
		layer.player = event_player
	_player.event_started.connect(_on_event)
	_player.register_consumer(finish_all, [&"DiceRolled"])


func unbind() -> void:
	_player.unregister_consumer(finish_all)


## Ends everything in motion at its end state and frees the transient nodes; dice stay on their faces.
func finish_all() -> void:
	for layer in _layers:
		layer.finish_all()


## Called after the scene equals the shown view: the static pieces now show what the ghosts showed, so the ghosts
## go in the same call. Dice and card flights are not state and play on.
func commit(geometry: BoardGeometry) -> void:
	var view := _player.shown_view
	var new_game := view.board.corners.size() != _built_corners
	_built_corners = view.board.corners.size()
	_layout = TableLayout.new(_scene, geometry, _player.seat, view.players.size())
	for layer in _layers:
		layer.layout = _layout
	dice.place(_layout, new_game)
	if view == _committed:
		return
	_committed = view
	pieces.finish_all()


func _on_event(event: SiEvent) -> void:
	if _layout == null:
		return
	if event is SiEventDiceRolled:
		dice.roll(event as SiEventDiceRolled, _player.animated())
	if not _player.animated():
		return
	if event is SiEventSettlementPlaced:
		pieces.settlement(event as SiEventSettlementPlaced)
	elif event is SiEventRoadPlaced:
		pieces.road(event as SiEventRoadPlaced)
	elif event is SiEventCityBuilt:
		pieces.city(event as SiEventCityBuilt)
	elif event is SiEventRobberMoved:
		pieces.robber(event as SiEventRobberMoved)
	cards.on_event(event)
