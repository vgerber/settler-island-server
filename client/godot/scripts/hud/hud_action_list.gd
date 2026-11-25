class_name HudActionList
extends HudDialog
## One button per legal action, e.g. the steal targets after the robber moved.

signal chosen(action: SiAction)


## `entries` holds `[label: String, action: SiAction]` pairs.
func open(title: String, entries: Array, script: Script) -> void:
	set_title(title)
	depends_on = script
	HudUi.clear(body)
	for entry: Array in entries:
		body.add_child(HudUi.button(str(entry[0]), _choose.bind(entry[1])))
	show()


func _choose(action: SiAction) -> void:
	hide()
	chosen.emit(action)
