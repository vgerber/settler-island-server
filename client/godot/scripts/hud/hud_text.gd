class_name HudText
extends RefCounted
## Names, colours and readable lines for the HUD: resources, cards, phases and every `SiEvent`.

static var build_names := {
	SiActionBuildRoad: "road",
	SiActionBuildSettlement: "settlement",
	SiActionBuildCity: "city",
}

const CARD_NAMES := {
	SiDevelopmentCard.KNIGHT: "Knight",
	SiDevelopmentCard.ROAD_BUILDING: "Road building",
	SiDevelopmentCard.YEAR_OF_PLENTY: "Year of plenty",
	SiDevelopmentCard.MONOPOLY: "Monopoly",
	SiDevelopmentCard.VICTORY_POINT: "Victory point",
}


static func card_name(card: String) -> String:
	return str(CARD_NAMES.get(card, card))


## "2 Wood, 1 Ore" from counts in the order of `SiResource.VALUES`.
static func counts(resources: Array) -> String:
	var parts: PackedStringArray = []
	for index in mini(resources.size(), SiResource.VALUES.size()):
		if resources[index] > 0:
			parts.append("%d %s" % [resources[index], SiResource.VALUES[index]])
	if parts.is_empty():
		return "nothing"
	return ", ".join(parts)


static func total(resources: Array[int]) -> int:
	var sum := 0
	for count in resources:
		sum += count
	return sum


static func setup_round_number(round: String) -> int:
	return 2 if round == SiSetupRound.SECOND else 1


static func phase_text(phase: SiPhase, names: SeatNames) -> String:
	if phase is SiPhaseSetupSettlement:
		return "Setup round %d: place a settlement" % setup_round_number((phase as SiPhaseSetupSettlement).round)
	if phase is SiPhaseSetupRoad:
		return "Setup round %d: place a road" % setup_round_number((phase as SiPhaseSetupRoad).round)
	if phase is SiPhaseRoll:
		return "Roll the dice"
	if phase is SiPhaseMain:
		return "Build, trade or end the turn"
	if phase is SiPhaseDiscard:
		return "Rolled a 7: discarding"
	if phase is SiPhaseMoveRobber:
		return "Move the robber"
	if phase is SiPhaseSteal:
		return "Choose whom to rob"
	if phase is SiPhaseRoadBuilding:
		return "Road building: %d free roads left" % (phase as SiPhaseRoadBuilding).roads_left
	if phase is SiPhaseTradeOffered:
		return "A trade is on the table"
	if phase is SiPhaseFinished:
		return "%s won" % names.subject((phase as SiPhaseFinished).winner)
	return "Waiting"


## The one or two words of the phase for the top bar.
static func phase_name(phase: SiPhase) -> String:
	if phase is SiPhaseSetupSettlement or phase is SiPhaseSetupRoad:
		return "Setup"
	if phase is SiPhaseRoll:
		return "Roll"
	if phase is SiPhaseMain:
		return "Main"
	if phase is SiPhaseDiscard:
		return "Discard"
	if phase is SiPhaseMoveRobber:
		return "Robber"
	if phase is SiPhaseSteal:
		return "Steal"
	if phase is SiPhaseRoadBuilding:
		return "Road building"
	if phase is SiPhaseTradeOffered:
		return "Trade"
	return "Game over"


## The seats the game waits for. Display only: the legal actions decide what anyone may do.
static func pending_seats(view: SiPlayerView) -> Array[int]:
	var pending: Array[int] = []
	if view.phase is SiPhaseFinished:
		return pending
	if view.phase is SiPhaseDiscard:
		for owed in (view.phase as SiPhaseDiscard).owed:
			if owed.cards > 0:
				pending.append(owed.seat)
		return pending
	if view.phase is SiPhaseTradeOffered:
		return _unanswered(view.phase as SiPhaseTradeOffered, view.players.size())
	pending.append(view.current)
	return pending


## The addressed seats that have not answered the open offer.
static func _unanswered(trade: SiPhaseTradeOffered, seat_count: int) -> Array[int]:
	var open: Array[int] = []
	var offer := trade.offer
	for seat in seat_count:
		var addressed := seat != offer.offerer and (offer.addressed == null or int(offer.addressed) == seat)
		var answered := offer.answers.any(func(answer: Array) -> bool: return int(answer[0]) == seat)
		if addressed and not answered:
			open.append(seat)
	return open


## What a seat is doing right now, for its panel: "" when it is not pending.
static func status_text(view: SiPlayerView, seat: int, names: SeatNames) -> String:
	if not pending_seats(view).has(seat):
		return ""
	if view.phase is SiPhaseDiscard:
		for owed in (view.phase as SiPhaseDiscard).owed:
			if owed.seat == seat:
				return "discarding %d" % owed.cards
	if view.phase is SiPhaseTradeOffered:
		return "answering trade"
	if view.phase is SiPhaseRoll:
		return "rolling"
	if view.phase is SiPhaseSetupSettlement or view.phase is SiPhaseSetupRoad:
		return "placing"
	return "thinking" if names.is_bot(seat) else "playing"


## One line for the own seat: what to do now, or whom to wait for.
static func prompt(state: GameState, names: SeatNames, armed: Script) -> String:
	var legal := HudLegal.new(state)
	var view := state.view
	if state.is_finished():
		return "The game is over"
	if armed != null:
		return "Place a %s (Esc to cancel)" % build_names[armed]
	var forced := _forced_prompt(state, legal)
	if not forced.is_empty():
		return forced
	if legal.has(SiActionRollDice):
		return "Roll the dice (Space)"
	if legal.has(SiActionEndTurn):
		return "Build or trade, then end the turn"
	return _waiting_prompt(view, names)


static func _forced_prompt(state: GameState, legal: HudLegal) -> String:
	var phase := state.view.phase
	if legal.has(SiActionPlaceSettlement):
		var second := phase is SiPhaseSetupSettlement and setup_round_number((phase as SiPhaseSetupSettlement).round) == 2
		return "Place your second settlement: it yields its neighbours' resources" if second else "Place your first settlement"
	if legal.has(SiActionPlaceRoad):
		return "Place a road next to your new settlement"
	if legal.has(SiActionMoveRobber):
		return "Move the robber"
	if phase is SiPhaseRoadBuilding and legal.has(SiActionBuildRoad):
		return "Free road: %d left" % (phase as SiPhaseRoadBuilding).roads_left
	if legal.has(SiActionDiscard):
		return "Discard %d cards" % HudText.total((state.legal_of(SiActionDiscard)[0] as SiActionDiscard).resources)
	if legal.has(SiActionSteal):
		return "Choose whom to rob"
	if legal.has(SiActionAcceptTrade) or legal.has(SiActionRejectTrade):
		return "Answer the trade offer"
	if legal.has(SiActionCancelTrade):
		return "Waiting for answers: confirm a trade or withdraw"
	return ""


static func _waiting_prompt(view: SiPlayerView, names: SeatNames) -> String:
	var pending := pending_seats(view)
	if pending.size() == 1:
		return "Waiting for %s" % names.name_of(pending[0])
	return "Waiting for %d players" % pending.size()


## One readable log line per event; the own seat reads as "You".
static func event_line(event: SiEvent, names: SeatNames) -> String:
	var line := _turn_line(event, names)
	if line.is_empty():
		line = _building_line(event, names)
	if line.is_empty():
		line = _resource_line(event, names)
	if line.is_empty():
		line = _trade_line(event, names)
	if line.is_empty():
		line = _card_line(event, names)
	if line.is_empty():
		line = str(event.to_dict().get("type", "Something happened"))
	return line


static func _turn_line(event: SiEvent, names: SeatNames) -> String:
	if event is SiEventTurnStarted:
		var started := (event as SiEventTurnStarted).seat
		return "Your turn" if started == names.own_seat else "%s's turn" % names.subject(started)
	if event is SiEventTurnEnded:
		return "%s ended the turn" % names.subject((event as SiEventTurnEnded).seat)
	if event is SiEventDiceRolled:
		var dice := event as SiEventDiceRolled
		return "%s rolled %d + %d = %d" % [names.subject(dice.seat), dice.first, dice.second, dice.first + dice.second]
	if event is SiEventPhaseChanged:
		return "Phase: %s" % phase_text((event as SiEventPhaseChanged).phase, names)
	if event is SiEventGameWon:
		var won := event as SiEventGameWon
		return "%s won with %d points" % [names.subject(won.seat), won.points]
	if event is SiEventRobberMoved:
		return "%s moved the robber" % names.subject((event as SiEventRobberMoved).seat)
	return ""


static func _building_line(event: SiEvent, names: SeatNames) -> String:
	if event is SiEventSettlementPlaced:
		return "%s built a settlement" % names.subject((event as SiEventSettlementPlaced).seat)
	if event is SiEventRoadPlaced:
		return "%s built a road" % names.subject((event as SiEventRoadPlaced).seat)
	if event is SiEventCityBuilt:
		return "%s built a city" % names.subject((event as SiEventCityBuilt).seat)
	if event is SiEventLongestRoadChanged:
		var road := event as SiEventLongestRoadChanged
		if road.holder == null:
			return "Nobody holds the longest road"
		return "Longest road (%d): %s" % [road.length, names.subject(int(road.holder))]
	if event is SiEventLargestArmyChanged:
		var army := event as SiEventLargestArmyChanged
		if army.holder == null:
			return "Nobody holds the largest army"
		return "Largest army (%d knights): %s" % [army.knights, names.subject(int(army.holder))]
	return ""


static func _resource_line(event: SiEvent, names: SeatNames) -> String:
	if event is SiEventResourcesProduced:
		var produced := event as SiEventResourcesProduced
		return "%s received %s" % [names.subject(produced.seat), counts(produced.resources)]
	if event is SiEventResourcesPaid:
		var paid := event as SiEventResourcesPaid
		return "%s paid %s" % [names.subject(paid.seat), counts(paid.resources)]
	if event is SiEventCardsDiscarded:
		var discarded := event as SiEventCardsDiscarded
		return "%s discarded %s" % [names.subject(discarded.seat), counts(discarded.resources)]
	if event is SiEventResourceStolen:
		return _stolen_line(event as SiEventResourceStolen, names)
	if event is SiEventMonopolyTaken:
		var monopoly := event as SiEventMonopolyTaken
		return "%s took all %s (%d)" % [names.subject(monopoly.seat), monopoly.resource, monopoly.amount]
	if event is SiEventYearOfPlentyTaken:
		var plenty := event as SiEventYearOfPlentyTaken
		return "%s took %s from the bank" % [names.subject(plenty.seat), counts(plenty.resources)]
	return ""


static func _stolen_line(stolen: SiEventResourceStolen, names: SeatNames) -> String:
	var thief := names.subject(stolen.thief)
	var victim := names.object(stolen.victim)
	# Only thief and victim learn the resource; the others see a hidden card.
	if stolen.resource == null:
		return "%s stole a card from %s" % [thief, victim]
	return "%s stole 1 %s from %s" % [thief, str(stolen.resource), victim]


static func _trade_line(event: SiEvent, names: SeatNames) -> String:
	if event is SiEventBankTraded:
		var bank := event as SiEventBankTraded
		return "%s traded %s for %s with the bank" % [names.subject(bank.seat), counts(bank.gave), counts(bank.received)]
	if event is SiEventTradeOffered:
		var offered := event as SiEventTradeOffered
		var addressed := "everyone" if offered.to == null else names.object(int(offered.to))
		var verb := "offer" if offered.seat == names.own_seat else "offers"
		return "%s %s %s for %s to %s" % [names.subject(offered.seat), verb, counts(offered.give), counts(offered.receive), addressed]
	if event is SiEventTradeAnswered:
		var answered := event as SiEventTradeAnswered
		return "%s %s the offer" % [names.subject(answered.seat), "accepted" if answered.accepted else "rejected"]
	if event is SiEventTradeCompleted:
		var completed := event as SiEventTradeCompleted
		return "%s traded %s for %s with %s" % [names.subject(completed.seat), counts(completed.gave), counts(completed.received), names.object(completed.with)]
	if event is SiEventTradeCancelled:
		return "%s withdrew the offer" % names.subject((event as SiEventTradeCancelled).seat)
	return ""


static func _card_line(event: SiEvent, names: SeatNames) -> String:
	if event is SiEventDevelopmentCardBought:
		var bought := event as SiEventDevelopmentCardBought
		# The card is only told to its buyer.
		if bought.card == null:
			return "%s bought a development card" % names.subject(bought.seat)
		return "%s bought a development card: %s" % [names.subject(bought.seat), card_name(str(bought.card))]
	if event is SiEventDevelopmentCardPlayed:
		var played := event as SiEventDevelopmentCardPlayed
		return "%s played %s" % [names.subject(played.seat), card_name(played.card)]
	return ""
