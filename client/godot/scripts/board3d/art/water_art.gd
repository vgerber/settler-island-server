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

static var _mesh: ArrayMesh = null


static func hex() -> ArrayMesh:
	if _mesh == null:
		_mesh = builder().to_mesh()
	return _mesh


static func builder() -> ClayBuilder:
	var result := ClayBuilder.new()
	var grey := Color(0.85, 0.85, 0.85)
	result.add_slab(outline, HEIGHT, BEVEL, Color.WHITE, grey, Color(0.6, 0.6, 0.6), 0.8, 1, COLUMNS)
	return result


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
