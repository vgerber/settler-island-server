class_name TableArt
extends RefCounted
## The walnut table top and the seat stands. The table top is at y = 0 (the mesh hangs below); the water hexes
## (`WaterArt`) and the land slabs (`HexSlabArt`) stand on it.
## x/z are the board's 2D x/y in hex units, the island centred on the origin.

const TABLE_HALF_WIDTH := 10.5
const TABLE_HALF_DEPTH := 7.4
const TABLE_THICKNESS := 0.6
## The seat stand is a long low tray with a coloured inlay; the inlay mesh sits `INLAY_LIFT` above the base mesh.
const STAND_HALF_WIDTH := 0.95
const STAND_HALF_DEPTH := 0.3
const STAND_HEIGHT := 0.12
const INLAY_LIFT := 0.1

## The dice tray: a wooden floor in a raised rim; dice rest on the floor top.
const TRAY_HALF_WIDTH := 0.8
const TRAY_HALF_DEPTH := 0.475
const TRAY_FLOOR := 0.05
const TRAY_RIM_HEIGHT := 0.12
const TRAY_RIM_WIDTH := 0.07

## Moulding rows for the table rim: [inset from the edge, height, shade].
const TABLE_MOULDING := [[0.5, 0.004, 0.9], [0.4, 0.07, 0.95], [0.2, 0.08, 1.0], [0.1, 0.04, 0.9]]
## The frame around a seat stand's inlay.
const STAND_MOULDING := [[0.105, 0.122, 0.85], [0.085, 0.137, 1.0], [0.045, 0.137, 0.95], [0.03, 0.12, 0.8]]

static var _meshes: Dictionary = {}


static func table() -> ArrayMesh:
	return _mesh("table", _build_table)


static func seat_stand_base() -> ArrayMesh:
	return _mesh("stand_base", _build_stand_base)


## White clay; tint it with `ClayMaterials.piece(seat)`.
static func seat_stand_inlay() -> ArrayMesh:
	return _mesh("stand_inlay", _build_stand_inlay)


## Ivory frame under the inlay of the dark seat, so its dark colour reads on the walnut stand.
static func seat_stand_rim() -> ArrayMesh:
	return _mesh("stand_rim", _build_stand_rim)


static func dice_tray() -> ArrayMesh:
	return _mesh("dice_tray", _build_dice_tray)


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
	result.add_slab(outline, TABLE_THICKNESS, 0.16, top, side, ClayPalette.shade(top, 0.5), 0.8, 1, 32, TABLE_THICKNESS)
	_add_planks(result, top)
	_add_moulding(result, outline, ClayPalette.shade(top, 1.25), TABLE_MOULDING, 32)


## Table-top boards along x: alternating shades with dark seams between them, kept inside the moulding.
static func _add_planks(result: ClayBuilder, top: Color) -> void:
	var count := 16
	var pitch := TABLE_HALF_DEPTH * 2.0 / count
	for index in count:
		var depth_low := -TABLE_HALF_DEPTH + pitch * index
		var depth_high := depth_low + pitch
		var depth_far := maxf(absf(depth_low), absf(depth_high))
		var reach := TABLE_HALF_WIDTH * pow(maxf(1.0 - pow(depth_far / TABLE_HALF_DEPTH, 6.0), 0.0), 1.0 / 6.0) - TABLE_MOULDING[0][0] - 0.3
		var shade: float = [1.0, 0.94, 1.05, 0.97, 1.02][index % 5]
		var half := Vector3(reach, 0.002, pitch * 0.5 - 0.012)
		result.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0015, depth_low + pitch * 0.5)), half, ClayPalette.shade(top, shade), 1.0)


## A raised border: `rows` run from the inside out as [inset, height, shade]; the outline is `outline(angle, inset)`.
static func _add_moulding(result: ClayBuilder, outline: Callable, color: Color, rows: Array, columns: int) -> void:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	for row: Array in rows:
		for column in columns:
			var angle := TAU * column / columns
			var radius: float = outline.call(angle, row[0])
			points.append(Vector3(cos(angle) * radius, row[1], sin(angle) * radius))
			colors.append(ClayPalette.shade(color, row[2]))
	var normals := ClayBuilder.grid_normals(points, rows.size(), columns)
	result.add_surface(points, normals, colors, rows.size(), columns, true)


static func _build_stand_base(result: ClayBuilder) -> void:
	var wood := ClayPalette.mute(Palette.TABLE_PANEL_BORDER).lightened(0.08)
	var outline := rounded_rectangle.bind(STAND_HALF_WIDTH, STAND_HALF_DEPTH, 4.0)
	result.add_slab(outline, STAND_HEIGHT, 0.05, wood, ClayPalette.shade(wood, 0.82), ClayPalette.shade(wood, 0.55), 0.78, 1, 24)
	_add_moulding(result, outline, ClayPalette.shade(wood, 1.3), STAND_MOULDING, 24)


static func _build_stand_inlay(result: ClayBuilder) -> void:
	var outline := rounded_rectangle.bind(STAND_HALF_WIDTH - 0.12, STAND_HALF_DEPTH - 0.1, 4.0)
	var white := Color(0.94, 0.94, 0.94)
	result.add_slab(outline, 0.04, 0.02, white, ClayPalette.shade(white, 0.85), ClayPalette.shade(white, 0.6), 0.8, 1, 24, -INLAY_LIFT)


static func _build_stand_rim(result: ClayBuilder) -> void:
	var outline := rounded_rectangle.bind(STAND_HALF_WIDTH - 0.07, STAND_HALF_DEPTH - 0.06, 4.0)
	var ivory := ClayPalette.mute(Palette.KEYLINE)
	result.add_slab(outline, 0.036, 0.015, ivory, ClayPalette.shade(ivory, 0.85), ClayPalette.shade(ivory, 0.6), 0.8, 1, 24, -INLAY_LIFT)


static func _build_dice_tray(result: ClayBuilder) -> void:
	var wood := ClayPalette.mute(Palette.PIER).lightened(0.05)
	var floor_wood := ClayPalette.shade(wood, 0.82)
	var floor_half := Vector3(TRAY_HALF_WIDTH, TRAY_FLOOR / 2.0, TRAY_HALF_DEPTH)
	result.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, TRAY_FLOOR / 2.0, 0.0)), floor_half, floor_wood, 0.6)
	for seam in [-0.24, 0.0, 0.24]:
		var strip := Transform3D(Basis.IDENTITY, Vector3(0.0, TRAY_FLOOR + 0.001, seam))
		result.add_box(strip, Vector3(TRAY_HALF_WIDTH - TRAY_RIM_WIDTH, 0.001, 0.004), ClayPalette.shade(floor_wood, 0.6), 1.0)
	var rim_y := TRAY_RIM_HEIGHT / 2.0 + TRAY_FLOOR / 2.0
	var long_half := Vector3(TRAY_HALF_WIDTH, TRAY_RIM_HEIGHT / 2.0, TRAY_RIM_WIDTH / 2.0)
	var short_half := Vector3(TRAY_RIM_WIDTH / 2.0, TRAY_RIM_HEIGHT / 2.0, TRAY_HALF_DEPTH - TRAY_RIM_WIDTH)
	for side in [-1.0, 1.0]:
		var along := Vector3(0.0, rim_y, side * (TRAY_HALF_DEPTH - TRAY_RIM_WIDTH / 2.0))
		result.add_box(Transform3D(Basis.IDENTITY, along), long_half, wood, 0.7)
		var across := Vector3(side * (TRAY_HALF_WIDTH - TRAY_RIM_WIDTH / 2.0), rim_y, 0.0)
		result.add_box(Transform3D(Basis.IDENTITY, across), short_half, ClayPalette.shade(wood, 0.92), 0.7)
		for end in [-1.0, 1.0]:
			var corner := Vector3(side * (TRAY_HALF_WIDTH - 0.02), TRAY_RIM_HEIGHT / 2.0 + TRAY_FLOOR / 2.0 + 0.012, end * (TRAY_HALF_DEPTH - 0.02))
			result.add_box(Transform3D(Basis.IDENTITY, corner), Vector3(0.05, TRAY_RIM_HEIGHT / 2.0 + 0.012, 0.05), ClayPalette.shade(wood, 1.15), 0.7)
