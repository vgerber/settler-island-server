class_name BoardPulses
extends MotionLayer
## What the dice do to the board: after the throw lands, the chips of the rolled number pulse and their tiles hop.
## The robber's tile produces nothing and stays still; a 7 pulses nothing.

const CHIP_SCALE := 1.25
const CHIP_SECONDS := 0.13
const TILE_HOP := 0.05

var scene: BoardScene = null
## Tiles and chips a pulse touched, reset by `finish_all` when a tween was cut short.
var _tiles: Array[Node3D] = []
var _chips: Array[Node3D] = []


func finish_all() -> void:
	super.finish_all()
	for tile in _tiles:
		if is_instance_valid(tile):
			tile.position.y = 0.0
	for chip in _chips:
		if is_instance_valid(chip):
			chip.scale = Vector3.ONE
	_tiles.clear()
	_chips.clear()


## Pulses the producing tiles of a roll once the dice rest.
func dice(event: SiEventDiceRolled) -> void:
	var sum := event.first + event.second
	var board := player.shown_view.board
	for index in board.tiles.size():
		var number: Variant = board.tiles[index].number
		if number != null and int(number) == sum and index != board.robber:
			_pulse(scene.tile_node(index))


func _pulse(tile: Node3D) -> void:
	var delay := DiceTray.TOTAL_MILLISECONDS / 1000.0
	_tiles.append(tile)
	var hop := _tween()
	hop.tween_interval(delay)
	hop.tween_property(tile, "position:y", TILE_HOP, CHIP_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hop.tween_property(tile, "position:y", 0.0, CHIP_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var chip := tile.get_node_or_null("Chip") as Node3D
	if chip == null:
		return
	_chips.append(chip)
	var grow := _tween()
	grow.tween_interval(delay)
	grow.tween_property(chip, "scale", Vector3.ONE * CHIP_SCALE, CHIP_SECONDS)
	grow.tween_property(chip, "scale", Vector3.ONE, CHIP_SECONDS)
