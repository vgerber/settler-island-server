class_name TableLight
extends RefCounted
## Lighting and Environment of the table, per renderer, in one place. The clay look is made for Compatibility
## (baked vertex AO, blob shadows); with Forward+ ("High" graphics quality) the same scene adds SSAO, glow and soft
## directional shadows on top. The energies are tuned so both renderers come out equally bright.

const AMBIENT_COLOR := Color("#FFE8D0")
const AMBIENT_ENERGY := 0.45
const LAMP_COLOR := Color("#FFF1DC")
const LAMP_ENERGY := 0.75
const LAMP_ROTATION := Vector3(-50.0, 35.0, 0.0)
const SSAO_RADIUS := 0.4
const SSAO_INTENSITY := 1.2
const GLOW_INTENSITY := 0.3
const SHADOW_DISTANCE := 40.0


## Whether the running renderer is Forward+, which the High look needs.
static func is_high() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"


## Adds the world environment and the lamp to `parent`.
static func add_to(parent: Node3D) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Palette.TABLE.darkened(0.5)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT_COLOR
	environment.ambient_light_energy = AMBIENT_ENERGY
	if is_high():
		environment.ssao_enabled = true
		environment.ssao_radius = SSAO_RADIUS
		environment.ssao_intensity = SSAO_INTENSITY
		environment.glow_enabled = true
		environment.glow_intensity = GLOW_INTENSITY
	var world := WorldEnvironment.new()
	world.environment = environment
	parent.add_child(world)
	var lamp := DirectionalLight3D.new()
	lamp.rotation_degrees = LAMP_ROTATION
	lamp.light_color = LAMP_COLOR
	lamp.light_energy = LAMP_ENERGY
	lamp.shadow_enabled = is_high()
	lamp.directional_shadow_max_distance = SHADOW_DISTANCE
	parent.add_child(lamp)
