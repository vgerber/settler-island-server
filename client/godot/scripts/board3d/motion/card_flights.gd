class_name CardFlights
extends MotionLayer
## Cards flying over the table: pooled 3D tokens on a Bezier curve with a flip. The own hand stays 2D, so a flight
## into or out of it hands over: a flat token flies the first or last 120 ms over the hand slot and the 3D token is
## released in the same call (doc/design/3d-motion.md, Cards).

const POOL_SIZE := 32
const FLAT_POOL_SIZE := 8
const HANDOVER_SECONDS := 0.12
const FLIGHT_SECONDS := 0.37
const STAGGER_SECONDS := 0.05
const BANK_DELAY_SECONDS := 0.15
const MAX_PER_EVENT := 12
const APEX_FACTOR := 0.25
const FLIP_TURNS := 2.0
const FLIP_SHARE := 0.4
const CARD_LIFT := 0.06
## A played development card is shown above the table front for this long, between rising and dropping.
const SHOW_SECONDS := 0.3
const SHOW_OFFSET := Vector3(0.0, 1.3, 1.6)

var rig: CameraRig = null
## The board these cards fly over; its `hand_slot` locates the HUD hand cards.
var host: BoardView = null
var _tokens: Array[CardToken3D] = []
var _flats: Array[CardTokenFlat] = []
var _flights: Array[Dictionary] = []
var _last_sum := 0


func _init() -> void:
	name = "CardFlights"
	for index in POOL_SIZE:
		var token := CardToken3D.new()
		_tokens.append(token)
		add_child(token)


## Creates the flat tokens inside `parent`, the control they fly over.
func attach_flat_tokens(parent: BoardView) -> void:
	host = parent
	for index in FLAT_POOL_SIZE:
		var flat := CardTokenFlat.new()
		_flats.append(flat)
		parent.add_child(flat)


## Flights in the air now, for tests.
func flights_in_air() -> int:
	return _flights.size()


## Pooled tokens in use now, for tests.
func tokens_in_use() -> int:
	return _tokens.filter(func(token: CardToken3D) -> bool: return token.in_use).size() \
			+ _flats.filter(func(flat: CardTokenFlat) -> bool: return flat.in_use).size()


func finish_all() -> void:
	super.finish_all()
	for token in _tokens:
		token.release()
	for flat in _flats:
		flat.release()
	_flights.clear()


func on_event(event: SiEvent) -> void:
	if event is SiEventDiceRolled:
		_last_sum = (event as SiEventDiceRolled).first + (event as SiEventDiceRolled).second
	elif event is SiEventResourcesProduced:
		_produced(event as SiEventResourcesProduced)
	elif event is SiEventResourcesPaid:
		var paid := event as SiEventResourcesPaid
		_send(paid.resources, _seat_end.bind(paid.seat), _bank_end, 0.0)
	elif event is SiEventCardsDiscarded:
		var discarded := event as SiEventCardsDiscarded
		_send(discarded.resources, _seat_end.bind(discarded.seat), _bank_end, 0.0)
	elif event is SiEventResourceStolen:
		_stolen(event as SiEventResourceStolen)
	elif event is SiEventBankTraded:
		var traded := event as SiEventBankTraded
		_send(traded.gave, _seat_end.bind(traded.seat), _bank_end, 0.0)
		_send(traded.received, _bank_end, _seat_end.bind(traded.seat), BANK_DELAY_SECONDS)
	elif event is SiEventTradeCompleted:
		var completed := event as SiEventTradeCompleted
		_send(completed.gave, _seat_end.bind(completed.seat), _seat_end.bind(completed.with), 0.0)
		_send(completed.received, _seat_end.bind(completed.with), _seat_end.bind(completed.seat), 0.0)
	elif event is SiEventYearOfPlentyTaken:
		var plenty := event as SiEventYearOfPlentyTaken
		_send(plenty.resources, _bank_end, _seat_end.bind(plenty.seat), 0.0)
	elif event is SiEventDevelopmentCardPlayed:
		_played(event as SiEventDevelopmentCardPlayed)
	elif event is SiEventMonopolyTaken:
		_monopoly(event as SiEventMonopolyTaken)
	elif event is SiEventDevelopmentCardBought:
		var bought := event as SiEventDevelopmentCardBought
		_fly(-1, _bank_end(-1), _seat_end(-1, bought.seat), 0.0)


func _produced(event: SiEventResourcesProduced) -> void:
	var board := player.shown_view.board
	_send(event.resources, func(resource: int) -> Dictionary:
		return {"world": layout.tile(_source_tile(board, event.seat, resource))}, _seat_end.bind(event.seat), 0.0)


## The tile that gave `resource` to `seat` with the last roll, else any tile of the resource, else the first.
func _source_tile(board: SiBoard, seat: int, resource: int) -> int:
	var fallback := -1
	for index in board.tiles.size():
		var tile := board.tiles[index]
		if tile.resource != SiResource.VALUES[resource]:
			continue
		fallback = index if fallback < 0 else fallback
		if tile.number != null and int(tile.number) == _last_sum and _owns_corner(board, tile, seat):
			return index
	return maxi(fallback, 0)


func _owns_corner(board: SiBoard, tile: SiTile, seat: int) -> bool:
	for corner in tile.corners:
		var building := board.buildings[corner]
		if building != null and building.seat == seat:
			return true
	return false


## The card rises from the stand of the player to above the table front, shows its face, then drops on the deck.
func _played(event: SiEventDevelopmentCardPlayed) -> void:
	var token := _free_token()
	token.show_dev(event.card)
	token.in_use = true
	token.visible = true
	var from := layout.seat_point(event.seat)
	var show := layout.center() + SHOW_OFFSET
	var flight := {"token": token, "flat": null}
	var tween := _tween()
	flight["tween"] = tween
	_flights.append(flight)
	tween.tween_method(_move.bind(token, from, show), 0.0, 1.0, FLIGHT_SECONDS)
	tween.tween_interval(SHOW_SECONDS)
	tween.tween_method(_move.bind(token, show, layout.deck_point()), 0.0, 1.0, FLIGHT_SECONDS)
	tween.tween_callback(_land.bind(flight))


## `amount` face-up cards of the resource from the other stands to the taker; the commit fixes the true counts.
func _monopoly(event: SiEventMonopolyTaken) -> void:
	var face := SiResource.VALUES.find(event.resource)
	var victims: Array[int] = []
	for seat in player.shown_view.players.size():
		if seat != event.seat:
			victims.append(seat)
	if victims.is_empty():
		return
	for card in mini(event.amount, MAX_PER_EVENT):
		var victim := victims[card % victims.size()]
		_fly(face, _seat_end(face, victim), _seat_end(face, event.seat), card * STAGGER_SECONDS)


func _stolen(event: SiEventResourceStolen) -> void:
	var face := -1 if event.resource == null else SiResource.VALUES.find(event.resource)
	_fly(face, _seat_end(face, event.victim), _seat_end(face, event.thief), 0.0)


## One token per card of `counts` (a count per resource), staggered, at most `MAX_PER_EVENT`.
func _send(counts: Array[int], from: Callable, to: Callable, delay: float) -> void:
	var sent := 0
	for resource in mini(counts.size(), SiResource.VALUES.size()):
		for card in counts[resource]:
			if sent >= MAX_PER_EVENT:
				return
			_fly(resource, from.call(resource), to.call(resource), delay + sent * STAGGER_SECONDS)
			sent += 1


## Where cards of `face` of `seat` are: the hand slot of the local seat, else its stand.
func _seat_end(face: int, seat: int) -> Dictionary:
	if seat == player.seat and face >= 0 and host.hand_slot.is_valid():
		var slot: Vector2 = host.hand_slot.call(SiResource.VALUES[face])
		var local := host.get_global_transform_with_canvas().affine_inverse() * slot
		return {"world": rig.unproject(local, rig.depth_of(layout.center())), "slot": slot}
	return {"world": layout.seat_point(seat)}


func _bank_end(_face: int) -> Dictionary:
	return {"world": layout.deck_point()}


func _fly(face: int, from: Dictionary, to: Dictionary, delay: float) -> void:
	var token := _free_token()
	token.show_face(face)
	token.in_use = true
	var flat: CardTokenFlat = null
	if from.has("slot") or to.has("slot"):
		flat = _free_flat()
		flat.show_face(face)
		flat.in_use = true
	var flight := {"token": token, "flat": flat}
	var tween := _tween()
	flight["tween"] = tween
	_flights.append(flight)
	if delay > 0.0:
		tween.tween_interval(delay)
	if from.has("slot"):
		tween.tween_callback(flat.place.bind(from["slot"]))
		tween.tween_method(_slide.bind(flat, from["slot"], from["world"]), 0.0, 1.0, HANDOVER_SECONDS)
	tween.tween_callback(_show_3d.bind(token, flat))
	tween.tween_method(_move.bind(token, from["world"], to["world"]), 0.0, 1.0, FLIGHT_SECONDS)
	if to.has("slot"):
		tween.tween_callback(_hand_over.bind(token, flat, to["world"]))
		tween.tween_method(_slide.bind(flat, to["slot"], to["world"]), 1.0, 0.0, HANDOVER_SECONDS)
	tween.tween_callback(_land.bind(flight))


## The flat token at `progress` between the world point (as projected now) and the slot.
func _slide(progress: float, flat: CardTokenFlat, slot: Vector2, world: Vector3) -> void:
	var projected := host.get_global_transform_with_canvas() * rig.project(world)
	flat.place(slot.lerp(projected, progress))


func _show_3d(token: CardToken3D, flat: CardTokenFlat) -> void:
	token.visible = true
	if flat != null:
		flat.visible = false


func _hand_over(token: CardToken3D, flat: CardTokenFlat, world: Vector3) -> void:
	token.visible = false
	flat.place(host.get_global_transform_with_canvas() * rig.project(world))


func _land(flight: Dictionary) -> void:
	(flight["token"] as CardToken3D).release()
	if flight["flat"] != null:
		(flight["flat"] as CardTokenFlat).release()
	_flights.erase(flight)


## Quadratic Bezier with its apex a quarter of the distance up and a flip over the first part of the way.
func _move(progress: float, token: CardToken3D, from: Vector3, to: Vector3) -> void:
	var control := (from + to) / 2.0 + Vector3.UP * from.distance_to(to) * APEX_FACTOR * 2.0
	token.position = from.lerp(control, progress).lerp(control.lerp(to, progress), progress) + Vector3.UP * CARD_LIFT
	var heading := to - from
	var axis := Vector3.UP.cross(heading)
	axis = Vector3.RIGHT if axis.length() < 0.001 else axis.normalized()
	var turned := smoothstep(0.0, 1.0, clampf(progress / FLIP_SHARE, 0.0, 1.0))
	token.basis = Basis(axis, TAU * FLIP_TURNS * turned)


## A token not in use; with none left the oldest flight ends at once and gives its token up.
func _free_token() -> CardToken3D:
	for token in _tokens:
		if not token.in_use:
			return token
	var oldest := _flights[0]
	(oldest["tween"] as Tween).kill()
	_live.erase(oldest["tween"])
	_land(oldest)
	return oldest["token"]


func _free_flat() -> CardTokenFlat:
	for flat in _flats:
		if not flat.in_use:
			return flat
	var oldest: Dictionary = _flights.filter(func(flight: Dictionary) -> bool: return flight["flat"] != null)[0]
	(oldest["tween"] as Tween).kill()
	_live.erase(oldest["tween"])
	_land(oldest)
	return oldest["flat"]
