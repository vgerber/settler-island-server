class_name SeatNames
extends RefCounted
## Who sits where. The game view has seats only, so names come from the last `LobbyState`; without
## one a seat is "Seat N". `subject`/`object` say "You"/"you" for the own seat, as the log needs.

var own_seat := 0
var _names: Array[String] = []
var _bots: Array[bool] = []


static func from_lobby(lobby: SiLobbyDetails, own_seat_index: int) -> SeatNames:
	var names := SeatNames.new()
	names.own_seat = own_seat_index
	if lobby == null:
		return names
	for index in lobby.seats.size():
		var occupant := lobby.seats[index]
		names._bots.append(occupant is SiSeatOccupantBot)
		if occupant is SiSeatOccupantHuman:
			names._names.append((occupant as SiSeatOccupantHuman).user.name)
		else:
			names._names.append("Bot %d" % (index + 1))
	return names


## The seat's own name, also for the own seat.
func name_of(seat: int) -> String:
	return _names[seat] if seat < _names.size() else "Seat %d" % (seat + 1)


func is_bot(seat: int) -> bool:
	return seat < _bots.size() and _bots[seat]


func subject(seat: int) -> String:
	return "You" if seat == own_seat else name_of(seat)


## The seat as the object of a sentence: "you" instead of "You".
func object(seat: int) -> String:
	return "you" if seat == own_seat else name_of(seat)
