class_name HudActionList
extends HudDialog
## One button per legal action, e.g. the steal targets after the robber moved, each with the seat's chip.

signal chosen(action: SiAction)


## `entries` holds `[label: String, action: SiAction, seat: int]` triples.
func open(title: String, entries: Array, script: Script) -> void:
	set_title(title)
	depends_on = script
	HudUi.clear(body)
	for entry: Array in entries:
		var row := HudUi.hbox(10)
		row.add_child(HudSeatChip.new(int(entry[2]), 28.0))
		var choice := HudUi.button(str(entry[0]), _choose.bind(entry[1]))
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(choice)
		body.add_child(row)
	show()


func _choose(action: SiAction) -> void:
	hide()
	chosen.emit(action)
