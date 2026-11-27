class_name HudTurnBanner
extends PanelContainer
## "Your turn": slides in from the top edge of the board, holds and leaves again. Ignores the mouse.

const SLIDE_SECONDS := 0.2
const HOLD_SECONDS := 0.9
const REST_TOP := 12.0

var _label := HudUi.label("", &"HeadingLabel")


func _init() -> void:
	theme_type_variation = &"SeatPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	hide()


## Shows `text` over the top centre of the parent; `animated` false only shows it for the hold time.
func announce(text: String, animated: bool) -> void:
	_label.text = text
	reset_size()
	var width := get_combined_minimum_size().x
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -width / 2.0
	offset_right = width / 2.0
	var above := -size.y
	position.y = above if animated else REST_TOP
	show()
	var tween := create_tween()
	if animated:
		tween.tween_property(self, "position:y", REST_TOP, SLIDE_SECONDS).set_trans(Tween.TRANS_CUBIC)
	tween.tween_interval(HOLD_SECONDS)
	if animated:
		tween.tween_property(self, "position:y", above, SLIDE_SECONDS)
	tween.tween_callback(hide)
