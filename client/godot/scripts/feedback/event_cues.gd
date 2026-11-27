class_name EventCues
extends RefCounted
## What one event means for feedback (doc/design/feedback.md): its sound hook, how long the HUD holds on it
## before the next event and whether a collapsed or unfocused stretch must still report it.

## Nominal HUD hold per event in milliseconds; events not listed take no time.
const HOLD_MILLISECONDS := {
	&"DiceRolled": 350,
	&"TurnStarted": 250,
	&"RobberMoved": 250,
	&"ResourceStolen": 250,
	&"TradeCompleted": 250,
	&"DevelopmentCardPlayed": 300,
	&"LongestRoadChanged": 250,
	&"LargestArmyChanged": 250,
	&"SettlementPlaced": 150,
	&"RoadPlaced": 150,
	&"CityBuilt": 150,
}


static func hold_milliseconds(event: SiEvent) -> int:
	return HOLD_MILLISECONDS.get(_variant(event), 0)


## The sound hook of an event, or an empty name when it has none.
static func hook(event: SiEvent, own_seat: int) -> StringName:
	if event is SiEventDiceRolled:
		var dice := event as SiEventDiceRolled
		return &"sfx_roll_seven" if dice.first + dice.second == 7 else &"sfx_dice_land"
	if event is SiEventResourceStolen:
		return _stolen_hook(event as SiEventResourceStolen, own_seat)
	if event is SiEventTradeAnswered:
		return &"sfx_trade_accept" if (event as SiEventTradeAnswered).accepted else &"sfx_trade_reject"
	if event is SiEventDevelopmentCardPlayed:
		return StringName("sfx_dev_play_" + str((event as SiEventDevelopmentCardPlayed).card).to_snake_case())
	if event is SiEventGameWon:
		return &"sfx_victory" if (event as SiEventGameWon).seat == own_seat else &"sfx_game_over"
	return _plain_hook(event)


static func _stolen_hook(stolen: SiEventResourceStolen, own_seat: int) -> StringName:
	if stolen.victim == own_seat:
		return &"sfx_stolen_from_me"
	return &"sfx_steal" if stolen.thief == own_seat else &""


static func _plain_hook(event: SiEvent) -> StringName:
	match _variant(event):
		&"SettlementPlaced": return &"sfx_place_settlement"
		&"RoadPlaced": return &"sfx_place_road"
		&"CityBuilt": return &"sfx_build_city"
		&"ResourcesProduced": return &"sfx_card_gain"
		&"ResourcesPaid": return &"sfx_pay"
		&"RobberMoved": return &"sfx_robber_move"
		&"CardsDiscarded": return &"sfx_discard"
		&"BankTraded": return &"sfx_trade_bank"
		&"TradeOffered": return &"sfx_trade_offer"
		&"TradeCompleted": return &"sfx_trade_done"
		&"TradeCancelled": return &"sfx_trade_cancel"
		&"DevelopmentCardBought": return &"sfx_dev_buy"
		&"MonopolyTaken": return &"sfx_monopoly"
		&"YearOfPlentyTaken": return &"sfx_dev_gain"
		&"LongestRoadChanged": return &"sfx_award_road"
		&"LargestArmyChanged": return &"sfx_award_army"
	return &""


## The events a digest keeps (marked M in the table of the design), for the viewer on `own_seat`.
static func must_show(event: SiEvent, own_seat: int) -> bool:
	if event is SiEventCardsDiscarded:
		return (event as SiEventCardsDiscarded).seat == own_seat
	if event is SiEventResourceStolen:
		var stolen := event as SiEventResourceStolen
		return stolen.thief == own_seat or stolen.victim == own_seat
	if event is SiEventTradeOffered:
		return addressed_to(event as SiEventTradeOffered, own_seat)
	return _variant(event) in [
		&"DiceRolled", &"RobberMoved", &"TradeCompleted", &"DevelopmentCardPlayed", &"MonopolyTaken",
		&"LongestRoadChanged", &"LargestArmyChanged", &"GameWon",
	]


## True when a seat other than the offerer is asked: the offer goes to everyone or to that seat.
static func addressed_to(offered: SiEventTradeOffered, own_seat: int) -> bool:
	return offered.seat != own_seat and (offered.to == null or int(offered.to) == own_seat)


## "DiceRolled" for a `SiEventDiceRolled`; unknown variants stay `SiEvent` and give an empty name.
static func _variant(event: SiEvent) -> StringName:
	var path: String = event.get_script().resource_path.get_file().get_basename()
	return StringName(path.trim_prefix("SiEvent"))
