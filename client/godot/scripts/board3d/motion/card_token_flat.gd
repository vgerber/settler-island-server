class_name CardTokenFlat
extends Panel
## The 2D half of a card flight into or out of the HUD hand: the card flies as a flat token for the first or last
## stretch, right over the slot the 3D card projects to.

const TOKEN_SIZE := Vector2(36.0, 50.0)

var in_use := false
var _style := StyleBoxFlat.new()


func _init() -> void:
	top_level = true
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = TOKEN_SIZE
	_style.set_border_width_all(2)
	_style.border_color = Palette.OUTLINE
	_style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", _style)


func show_face(face: int) -> void:
	_style.bg_color = Palette.resource_color(SiResource.VALUES[face]) if face >= 0 else CardToken3D.BACK_COLOR


## Centres the token on a global pixel.
func place(center: Vector2) -> void:
	global_position = center - size / 2.0
	visible = true


func release() -> void:
	visible = false
	in_use = false
