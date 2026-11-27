class_name HudTradeDialog
extends HudDialog
## "Trade": a bank tab and a players tab. Bank is the default when a bank trade is legal. The dialog stays
## open while trades go through and closes by itself once ending the turn is no longer legal.

signal chosen(action: SiAction)
signal offered(action: SiActionOfferTrade)

var bank := HudBankPane.new()
var players := HudTradeBuilder.new()
var _bank_tab := HudUi.button("Bank", _show_tab.bind(true), &"BuildButton")
var _players_tab := HudUi.button("Players", _show_tab.bind(false), &"BuildButton")


func _init() -> void:
	super()
	depends_on = SiActionEndTurn
	set_title("Trade")
	var tabs := HudUi.hbox(6)
	for tab: Button in [_bank_tab, _players_tab]:
		tab.toggle_mode = true
		tabs.add_child(tab)
	body.add_child(tabs)
	body.add_child(bank)
	body.add_child(players)
	buttons.add_child(HudUi.button("Close", hide))
	bank.chosen.connect(chosen.emit)
	players.offered.connect(_offer)


func open(legal: HudLegal, hand: Array[int], seats: int, names: SeatNames) -> void:
	players.open(hand, seats, names)
	bank.show_legal(legal)
	_show_tab(legal.has(SiActionBankTrade))
	show()


func refresh(legal: HudLegal) -> void:
	bank.show_legal(legal)


func _show_tab(show_bank: bool) -> void:
	_bank_tab.set_pressed_no_signal(show_bank)
	_players_tab.set_pressed_no_signal(not show_bank)
	bank.visible = show_bank
	players.visible = not show_bank


func _offer(action: SiActionOfferTrade) -> void:
	hide()
	offered.emit(action)
