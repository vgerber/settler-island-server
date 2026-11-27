class_name WaterArt
extends RefCounted
## The sea as hexes on the lattice of the land: one low chamfered, flat-shaded hex mesh (`water.gdshader` varies
## colour and bob per instance) in every free lattice cell of a rectangle around the island. Water tops are lower
## than land tops (`HexSlabArt.HEIGHT`), so the island stands out; piers stand on the coastal hexes. The mesh sits
## on y = 0 and is `HEIGHT` high.

const HEIGHT := 0.09
const BEVEL := 0.03
## Apothem: nearly the lattice's own (sqrt 3 / 2), so only a thin seam of table shows between hexes.
const APOTHEM := 0.86
const COLUMNS := 12
## Cells whose centre lies inside this rectangle (hex units, x and z) get water.
const HALF_WIDTH := 8.0
const HALF_DEPTH := 5.0
const CELL_EPSILON := 0.05
## Rings of the swell top as shares of the outline; the last one is the foam ring.
const SWELL_RINGS: Array[float] = [0.0, 0.5, 0.78, 0.91, 1.0]
const SWELL := 0.007
const SWELL_LIFT := 0.003
## Shoal level of a water hex next to land and of one a ring further out.
const SHOAL_NEAR := 1.0
const SHOAL_FAR := 0.45

static var _mesh: ArrayMesh = null


static func hex() -> ArrayMesh:
	if _mesh == null:
		_mesh = builder().to_mesh()
	return _mesh


static func builder() -> ClayBuilder:
	var result := ClayBuilder.new()
	var grey := Color(0.85, 0.85, 0.85)
	result.add_slab(outline, HEIGHT, BEVEL, Color.WHITE, grey, Color(0.6, 0.6, 0.6), 0.8, 1, COLUMNS)
	_add_swell_top(result)
	return result


## Rings of facets on the top, a hair above the slab's flat top. Red is the grey AO (darker in the swell's
## dips), (red minus blue) twice is the foam weight (1 on the outermost ring: the shader shows it only toward land).
## The swell fades to zero at the rim, so neighbouring hexes meet without a step.
static func _add_swell_top(result: ClayBuilder) -> void:
	var rings: Array[PackedVector3Array] = []
	for share in SWELL_RINGS:
		var ring_points := PackedVector3Array()
		for column in COLUMNS:
			var angle := TAU * column / COLUMNS
			var radius: float = share * outline(angle, BEVEL if share == 1.0 else 0.0)
			var position := Vector2(cos(angle), sin(angle)) * radius
			var swell := SWELL * sin(position.x * 6.1 + 0.4) * sin(position.y * 5.3) * (1.0 - smoothstep(0.55, 0.95, share))
			ring_points.append(Vector3(position.x, HEIGHT + SWELL_LIFT + swell, position.y))
		rings.append(ring_points)
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	for ring in rings.size() - 1:
		var foam := 1.0 if ring == rings.size() - 2 else 0.0
		for column in COLUMNS:
			var next := (column + 1) % COLUMNS
			var inner_first: Vector3 = rings[ring][column]
			var inner_second: Vector3 = rings[ring][next]
			var outer_first: Vector3 = rings[ring + 1][column]
			var outer_second: Vector3 = rings[ring + 1][next]
			for corners in [[inner_first, outer_first, outer_second], [inner_first, outer_second, inner_second]]:
				points.append_array(corners)
				var shade := 0.9 + 0.1 * clampf((corners[0].y + corners[1].y + corners[2].y) / 3.0 - HEIGHT, 0.0, SWELL) / SWELL
				colors.append(Color(shade, shade, shade - foam * 0.5, 1.0))
	result.add_facets(points, colors)


static func outline(angle: float, inset: float) -> float:
	return HexSlabArt.hex_outline(angle, inset - (APOTHEM - HexSlabArt.APOTHEM))


## Centres of the water hexes: every lattice cell in the rectangle that is not the centre of a land tile.
static func cells(land_centres: Array[Vector2]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var rows := int(HALF_DEPTH / 1.5)
	for row in range(-rows, rows + 1):
		var columns := int(HALF_WIDTH / BoardGeometry.SQUARE_ROOT_OF_THREE) + 1
		for column in range(-columns - rows, columns + rows + 1):
			var centre := Vector2(BoardGeometry.SQUARE_ROOT_OF_THREE * (column + row / 2.0), 1.5 * row)
			if absf(centre.x) > HALF_WIDTH or not _is_free(centre, land_centres):
				continue
			result.append(centre)
	return result


static func _is_free(centre: Vector2, land_centres: Array[Vector2]) -> bool:
	for land in land_centres:
		if land.distance_to(centre) < CELL_EPSILON:
			return false
	return true


## Per water cell, parallel to `cells`: x is a bitmask of the hex edges that touch land (bit k is the edge
## toward angle 60 k degrees, the way `HexSlabArt` faces), y the shoal level (`SHOAL_NEAR` beside land,
## `SHOAL_FAR` one hex further out, 0 in open sea). Lattice cells inside the rectangle that are not water are land.
static func coast(cells: Array[Vector2]) -> Array[Vector2]:
	var index_of := {}
	for index in cells.size():
		index_of[_key(cells[index])] = index
	var masks: Array[int] = []
	for cell in cells:
		masks.append(_land_mask(cell, index_of))
	var result: Array[Vector2] = []
	for index in cells.size():
		var shoal := SHOAL_NEAR if masks[index] != 0 else 0.0
		if shoal == 0.0 and _has_coastal_neighbour(cells[index], index_of, masks):
			shoal = SHOAL_FAR
		result.append(Vector2(masks[index], shoal))
	return result


static func _land_mask(cell: Vector2, index_of: Dictionary) -> int:
	var mask := 0
	for direction in 6:
		var neighbour := cell + _step(direction)
		var inside := absf(neighbour.x) <= HALF_WIDTH and absf(neighbour.y) <= HALF_DEPTH
		if inside and not index_of.has(_key(neighbour)):
			mask |= 1 << direction
	return mask


static func _has_coastal_neighbour(cell: Vector2, index_of: Dictionary, masks: Array[int]) -> bool:
	for direction in 6:
		var found: Variant = index_of.get(_key(cell + _step(direction)))
		if found != null and masks[found] != 0:
			return true
	return false


static func _step(direction: int) -> Vector2:
	var angle := PI / 3.0 * direction
	return Vector2(cos(angle), sin(angle)) * BoardGeometry.SQUARE_ROOT_OF_THREE


static func _key(centre: Vector2) -> Vector2i:
	return Vector2i(roundi(centre.x * 10.0), roundi(centre.y * 10.0))
