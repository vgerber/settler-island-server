class_name HudLegal
extends RefCounted
## Questions the HUD asks of the legal actions: what may the own seat do now, and which picks lead to a legal action.

var _state: GameState


func _init(game_state: GameState) -> void:
	_state = game_state


func has(script: Script) -> bool:
	return not _state.legal_of(script).is_empty()


## Offers are not among the legal actions (their contents are free); the server accepts them in the own
## Main phase, which is when ending the turn is legal. A server-side `can_offer_trade` would replace this.
func can_offer_trade() -> bool:
	var own := _state.view.own
	return has(SiActionEndTurn) and own != null and HudText.total(own.hand) > 0


## The distinct values of `property` among the legal actions of `script` that match `filter`.
func distinct(script: Script, property: String, filter: Dictionary) -> Array[String]:
	var values: Array[String] = []
	for action in _state.legal_of(script):
		if matches(action, filter) and not values.has(str(action.get(property))):
			values.append(str(action.get(property)))
	return values


## The legal action of `script` whose properties equal `filter`, or null.
func find(script: Script, filter: Dictionary) -> SiAction:
	for action in _state.legal_of(script):
		if matches(action, filter):
			return action
	return null


func matches(action: SiAction, filter: Dictionary) -> bool:
	for property: String in filter:
		if str(action.get(property)) != str(filter[property]):
			return false
	return true


## The server's rate for `resource` from the own view (4, or 3 and 2 with ports).
func bank_rate(resource: String) -> int:
	return _state.view.own.bank_rates[SiResource.VALUES.find(resource)]
