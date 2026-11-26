class_name HudText
extends RefCounted
## Names, colours and readable lines for the HUD: resources, cards, phases and every `SiEvent`.

const CARD_NAMES := {
	"Knight": "Knight",
	"RoadBuilding": "Road building",
	"YearOfPlenty": "Year of plenty",
	"Monopoly": "Monopoly",
	"VictoryPoint": "Victory point",
}


static func seat_color(seat: int) -> Color:
	return Palette.seat_color(seat)


static func resource_color(resource: String) -> Color:
	return Palette.resource_color(resource)


static func seat_name(seat: int, own_seat: int) -> String:
	if seat == own_seat:
		return "You"
	return "Seat %d" % (seat + 1)


## The seat as the object of a sentence: "you" instead of "You".
static func seat_object(seat: int, own_seat: int) -> String:
	return "you" if seat == own_seat else seat_name(seat, own_seat)


static func card_name(card: String) -> String:
	return str(CARD_NAMES.get(card, card))


## "2 Wood, 1 Ore" from counts in the order of `SiResource.VALUES`.
static func counts(resources: Array[int]) -> String:
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


static func phase_text(phase: SiPhase, own_seat: int) -> String:
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
		return "%s won" % seat_name((phase as SiPhaseFinished).winner, own_seat)
	return "Waiting"


## One readable log line per event; `own_seat` turns that seat into "You".
static func event_line(event: SiEvent, own_seat: int) -> String:
	var line := _turn_line(event, own_seat)
	if line.is_empty():
		line = _building_line(event, own_seat)
	if line.is_empty():
		line = _resource_line(event, own_seat)
	if line.is_empty():
		line = _trade_line(event, own_seat)
	if line.is_empty():
		line = _card_line(event, own_seat)
	if line.is_empty():
		line = str(event.to_dict().get("type", "Something happened"))
	return line


static func _turn_line(event: SiEvent, own_seat: int) -> String:
	if event is SiEventTurnStarted:
		var started := (event as SiEventTurnStarted).seat
		return "Your turn" if started == own_seat else "%s's turn" % seat_name(started, own_seat)
	if event is SiEventTurnEnded:
		return "%s ended the turn" % seat_name((event as SiEventTurnEnded).seat, own_seat)
	if event is SiEventDiceRolled:
		var dice := event as SiEventDiceRolled
		return "%s rolled %d + %d = %d" % [seat_name(dice.seat, own_seat), dice.first, dice.second, dice.first + dice.second]
	if event is SiEventPhaseChanged:
		return "Phase: %s" % phase_text((event as SiEventPhaseChanged).phase, own_seat)
	if event is SiEventGameWon:
		var won := event as SiEventGameWon
		return "%s won with %d points" % [seat_name(won.seat, own_seat), won.points]
	if event is SiEventRobberMoved:
		return "%s moved the robber" % seat_name((event as SiEventRobberMoved).seat, own_seat)
	return ""


static func _building_line(event: SiEvent, own_seat: int) -> String:
	if event is SiEventSettlementPlaced:
		return "%s built a settlement" % seat_name((event as SiEventSettlementPlaced).seat, own_seat)
	if event is SiEventRoadPlaced:
		return "%s built a road" % seat_name((event as SiEventRoadPlaced).seat, own_seat)
	if event is SiEventCityBuilt:
		return "%s built a city" % seat_name((event as SiEventCityBuilt).seat, own_seat)
	if event is SiEventLongestRoadChanged:
		var road := event as SiEventLongestRoadChanged
		if road.holder == null:
			return "Nobody holds the longest road"
		return "Longest road (%d): %s" % [road.length, seat_name(int(road.holder), own_seat)]
	if event is SiEventLargestArmyChanged:
		var army := event as SiEventLargestArmyChanged
		if army.holder == null:
			return "Nobody holds the largest army"
		return "Largest army (%d knights): %s" % [army.knights, seat_name(int(army.holder), own_seat)]
	return ""


static func _resource_line(event: SiEvent, own_seat: int) -> String:
	if event is SiEventResourcesProduced:
		var produced := event as SiEventResourcesProduced
		return "%s received %s" % [seat_name(produced.seat, own_seat), counts(produced.resources)]
	if event is SiEventResourcesPaid:
		var paid := event as SiEventResourcesPaid
		return "%s paid %s" % [seat_name(paid.seat, own_seat), counts(paid.resources)]
	if event is SiEventCardsDiscarded:
		var discarded := event as SiEventCardsDiscarded
		return "%s discarded %s" % [seat_name(discarded.seat, own_seat), counts(discarded.resources)]
	if event is SiEventResourceStolen:
		return _stolen_line(event as SiEventResourceStolen, own_seat)
	if event is SiEventMonopolyTaken:
		var monopoly := event as SiEventMonopolyTaken
		return "%s took all %s (%d)" % [seat_name(monopoly.seat, own_seat), monopoly.resource, monopoly.amount]
	if event is SiEventYearOfPlentyTaken:
		var plenty := event as SiEventYearOfPlentyTaken
		return "%s took %s from the bank" % [seat_name(plenty.seat, own_seat), counts(plenty.resources)]
	return ""


static func _stolen_line(stolen: SiEventResourceStolen, own_seat: int) -> String:
	var thief := seat_name(stolen.thief, own_seat)
	var victim := seat_object(stolen.victim, own_seat)
	# Only thief and victim learn the resource; the others see a hidden card.
	if stolen.resource == null:
		return "%s stole a card from %s" % [thief, victim]
	return "%s stole 1 %s from %s" % [thief, str(stolen.resource), victim]


static func _trade_line(event: SiEvent, own_seat: int) -> String:
	if event is SiEventBankTraded:
		var bank := event as SiEventBankTraded
		return "%s traded %s for %s with the bank" % [seat_name(bank.seat, own_seat), counts(bank.gave), counts(bank.received)]
	if event is SiEventTradeOffered:
		var offered := event as SiEventTradeOffered
		var addressed := "everyone" if offered.to == null else seat_object(int(offered.to), own_seat)
		var verb := "offer" if offered.seat == own_seat else "offers"
		return "%s %s %s for %s to %s" % [seat_name(offered.seat, own_seat), verb, counts(offered.give), counts(offered.receive), addressed]
	if event is SiEventTradeAnswered:
		var answered := event as SiEventTradeAnswered
		return "%s %s the offer" % [seat_name(answered.seat, own_seat), "accepted" if answered.accepted else "rejected"]
	if event is SiEventTradeCompleted:
		var completed := event as SiEventTradeCompleted
		return "%s traded %s for %s with %s" % [seat_name(completed.seat, own_seat), counts(completed.gave), counts(completed.received), seat_object(completed.with, own_seat)]
	if event is SiEventTradeCancelled:
		return "%s withdrew the offer" % seat_name((event as SiEventTradeCancelled).seat, own_seat)
	return ""


static func _card_line(event: SiEvent, own_seat: int) -> String:
	if event is SiEventDevelopmentCardBought:
		var bought := event as SiEventDevelopmentCardBought
		# The card is only told to its buyer.
		if bought.card == null:
			return "%s bought a development card" % seat_name(bought.seat, own_seat)
		return "%s bought a development card: %s" % [seat_name(bought.seat, own_seat), card_name(str(bought.card))]
	if event is SiEventDevelopmentCardPlayed:
		var played := event as SiEventDevelopmentCardPlayed
		return "%s played %s" % [seat_name(played.seat, own_seat), card_name(played.card)]
	return ""
