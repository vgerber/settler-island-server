class_name HudGlow
extends RefCounted
## The active-seat marking of a seat panel: a 3 px border in the seat colour and a slow breathing glow, faster
## for a bot ("thinking"). Other panels dim to 85 %. The loop is a tween owned by the panel; with animations off
## the active panel just stays at full brightness.

const BREATH_SECONDS := 1.2
const BOT_BREATH_SECONDS := 0.6
const DIMMED := Color(0.85, 0.85, 0.85)
const GLOW_META := &"glow_tween"


## Marks `panel` as the active seat or not. `breathing` false (animations off) keeps it still.
static func apply(panel: PanelContainer, seat: int, active: bool, bot: bool, breathing: bool) -> void:
	_stop(panel)
	panel.remove_theme_stylebox_override("panel")
	if not active:
		panel.modulate = DIMMED
		return
	panel.modulate = Color.WHITE
	var bordered := panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if bordered != null:
		bordered.set_border_width_all(3)
		bordered.border_color = Palette.seat_color(seat)
		panel.add_theme_stylebox_override("panel", bordered)
	if breathing:
		_breathe(panel, BOT_BREATH_SECONDS if bot else BREATH_SECONDS)


## Two quick pulses of the panel: the turn-start cue of the own seat.
static func pulse(panel: Control) -> void:
	var tween := panel.create_tween()
	for _repeat in 2:
		tween.tween_property(panel, "modulate", Color(1.25, 1.2, 0.9), 0.125)
		tween.tween_property(panel, "modulate", Color.WHITE, 0.125)


static func _breathe(panel: Control, period: float) -> void:
	var tween := panel.create_tween().set_loops()
	tween.tween_property(panel, "modulate:a", 0.7, period / 2.0)
	tween.tween_property(panel, "modulate:a", 1.0, period / 2.0)
	panel.set_meta(GLOW_META, tween)


static func _stop(panel: Control) -> void:
	if not panel.has_meta(GLOW_META):
		return
	var running: Variant = panel.get_meta(GLOW_META)
	if running is Tween:
		(running as Tween).kill()
	panel.remove_meta(GLOW_META)
