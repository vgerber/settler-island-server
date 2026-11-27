class_name ClayMaterials
extends RefCounted
## Cached `ShaderMaterial`s of the clay kit. The look is made for the Compatibility renderer with faked depth
## (baked vertex AO in the meshes, `BlobShadow`, rim light). With Forward+ (`graphics_quality` High) the board
## adds an `Environment` on top: SSAO (radius about 0.4 hex, intensity 1.2), glow, and soft directional shadows;
## none of that is needed here, and the materials look the same under both.

const CLAY_SHADER := "res://shaders/clay.gdshader"
const WATER_SHADER := "res://shaders/water.gdshader"
## Rim colours: light on dark pieces, dark on light ones (the outline rule of visual-style.md).
const RIM_LIGHT := Palette.KEYLINE
const RIM_DARK := Palette.OUTLINE

## Brightness of the inlay of a seat that is not on the move.
const STAND_DIM := 0.5
## Brightness of the tile under the robber (design: 60%).
const TILE_DIM := 0.6

static var _cache: Dictionary = {}


## Plain clay: the vertex colours decide (terrain, props, chips, dice, piers).
static func terrain() -> ShaderMaterial:
	return _clay("terrain", Color.WHITE, 0.0, RIM_LIGHT, 0.022)


## A seat's pieces: the muted seat colour with the rim of its outline rule.
static func piece(seat_index: int) -> ShaderMaterial:
	var rim := RIM_DARK if seat_index % Palette.SEAT_COLORS.size() == Palette.IVORY_SEAT else RIM_LIGHT
	return _clay("piece%d" % seat_index, ClayPalette.seat(seat_index), 0.7, rim, 0.018)


## The robber is dark, so it gets a light rim.
static func robber() -> ShaderMaterial:
	return _clay("robber", Color.WHITE, 0.8, RIM_LIGHT, 0.018)


## Dice and chips: light stock, a faint dark rim helps them stand off the tiles.
static func stock() -> ShaderMaterial:
	return _clay("stock", Color.WHITE, 0.28, RIM_DARK, 0.018)


## The inlay of a seat stand: the seat colour, dimmed unless the seat is lit (current or pending).
static func stand(seat_index: int, lit: bool) -> ShaderMaterial:
	var rim := RIM_DARK if seat_index % Palette.SEAT_COLORS.size() == Palette.IVORY_SEAT else RIM_LIGHT
	var tint := ClayPalette.seat(seat_index)
	return _clay("stand%d%s" % [seat_index, lit], tint if lit else ClayPalette.shade(tint, STAND_DIM), 0.7, rim, 0.018)


## The tile the robber stands on: the terrain clay at `TILE_DIM` of its brightness.
static func dimmed_terrain() -> ShaderMaterial:
	return _clay("terrain_dim", Color.WHITE * TILE_DIM, 0.0, RIM_LIGHT, 0.022)


static func table() -> ShaderMaterial:
	return _clay("table", Color.WHITE, 0.0, RIM_LIGHT, 0.02, 0.06)


## Water hexes: one material, the shader varies colour and bob per instance.
static func water() -> ShaderMaterial:
	if not _cache.has("water"):
		var material := ShaderMaterial.new()
		material.shader = load(WATER_SHADER)
		material.set_shader_parameter("deep_color", ClayPalette.mute(Palette.SEA))
		material.set_shader_parameter("crest_color", ClayPalette.mute(Palette.WAVE))
		_cache["water"] = material
	return _cache["water"]


static func _clay(
	key: String, tint: Color, rim_strength: float, rim_color: Color, fingerprint: float, grain := 0.0
) -> ShaderMaterial:
	if not _cache.has(key):
		var material := ShaderMaterial.new()
		material.shader = load(CLAY_SHADER)
		material.set_shader_parameter("tint", tint)
		material.set_shader_parameter("rim_strength", rim_strength)
		material.set_shader_parameter("rim_color", rim_color)
		material.set_shader_parameter("fingerprint_strength", fingerprint)
		material.set_shader_parameter("grain_strength", grain)
		material.set_shader_parameter("convert_vertex_color", RenderingServer.get_current_rendering_method() != "gl_compatibility")
		_cache[key] = material
	return _cache[key]
