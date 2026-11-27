class_name TableArt
extends RefCounted
## The walnut table top, the sea sheet on it and the seat stands. The table top is at y = 0 (the mesh hangs below),
## the sea sheet rests on it with its top at `SEA_LEVEL`, the hex slabs stand in the sheet (`HexSlabArt.HEIGHT`).
## x/z are the board's 2D x/y in hex units, the island centred on the origin.

const TABLE_HALF_WIDTH := 10.5
const TABLE_HALF_DEPTH := 7.4
const TABLE_THICKNESS := 0.6
const SEA_HALF_WIDTH := 6.3
const SEA_HALF_DEPTH := 5.4
const SEA_LEVEL := 0.06
## The seat stand is a long low tray with a coloured inlay; the inlay mesh sits `INLAY_LIFT` above the base mesh.
const STAND_HALF_WIDTH := 0.95
const STAND_HALF_DEPTH := 0.3
const STAND_HEIGHT := 0.12
const INLAY_LIFT := 0.1

static var _meshes: Dictionary = {}


static func table() -> ArrayMesh:
	return _mesh("table", _build_table)


static func sea() -> ArrayMesh:
	return _mesh("sea", _build_sea)


static func seat_stand_base() -> ArrayMesh:
	return _mesh("stand_base", _build_stand_base)


## White clay; tint it with `ClayMaterials.piece(seat)`.
static func seat_stand_inlay() -> ArrayMesh:
	return _mesh("stand_inlay", _build_stand_inlay)


static func _mesh(key: String, build: Callable) -> ArrayMesh:
	if not _meshes.has(key):
		var result := ClayBuilder.new()
		build.call(result)
		_meshes[key] = result.to_mesh()
	return _meshes[key]


## Distance to a rounded rectangle (a superellipse of exponent `exponent`) with the given half sizes.
static func rounded_rectangle(angle: float, inset: float, half_width: float, half_depth: float, exponent: float) -> float:
	var along_x := absf(cos(angle)) / (half_width - inset)
	var along_z := absf(sin(angle)) / (half_depth - inset)
	return 1.0 / pow(pow(along_x, exponent) + pow(along_z, exponent), 1.0 / exponent)


static func _build_table(result: ClayBuilder) -> void:
	var top := ClayPalette.mute(Palette.TABLE).lightened(0.1)
	var side := ClayPalette.shade(top, 0.75)
	var outline := rounded_rectangle.bind(TABLE_HALF_WIDTH, TABLE_HALF_DEPTH, 6.0)
	result.add_slab(outline, TABLE_THICKNESS, 0.16, top, side, ClayPalette.shade(top, 0.5), 0.8, 1, 96, TABLE_THICKNESS)


## Greys only: `sea.gdshader` takes the water colour from its uniforms and the red channel as AO.
static func _build_sea(result: ClayBuilder) -> void:
	var outline := rounded_rectangle.bind(SEA_HALF_WIDTH, SEA_HALF_DEPTH, 3.2)
	result.add_slab(outline, SEA_LEVEL, 0.035, Color.WHITE, Color(0.85, 0.85, 0.85), Color(0.6, 0.6, 0.6), 0.8, 30, 120)


static func _build_stand_base(result: ClayBuilder) -> void:
	var wood := ClayPalette.mute(Palette.TABLE_PANEL_BORDER).lightened(0.08)
	var outline := rounded_rectangle.bind(STAND_HALF_WIDTH, STAND_HALF_DEPTH, 4.0)
	result.add_slab(outline, STAND_HEIGHT, 0.05, wood, ClayPalette.shade(wood, 0.82), ClayPalette.shade(wood, 0.55), 0.78, 1, 48)


static func _build_stand_inlay(result: ClayBuilder) -> void:
	var outline := rounded_rectangle.bind(STAND_HALF_WIDTH - 0.12, STAND_HALF_DEPTH - 0.1, 4.0)
	var white := Color(0.94, 0.94, 0.94)
	result.add_slab(outline, 0.04, 0.02, white, ClayPalette.shade(white, 0.85), ClayPalette.shade(white, 0.6), 0.8, 1, 48, -INLAY_LIFT)
