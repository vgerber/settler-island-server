class_name CardArt
extends RefCounted
## Resource and development cards as faceted clay, lying face up on y = 0 (x across, z along the long side; the
## glyph's up is -z, so it reads upright for the default camera). Origin at the centre of the base, front toward +z.
## A face is a card-stock border (dev cards: plum, one cut corner) around a coloured field with one raised glyph;
## the underside is a walnut plate with a brass diamond. `card_back` and `dev_back` have the back on top, for
## opponent hands and decks. No text. Use `ClayMaterials.stock()`; the vertex colours carry everything.

const HALF := Vector2(0.18, 0.25)
const THICKNESS := 0.014
const BORDER_WIDTH := 0.025
const CHAMFER := 0.03
## The cut corner of a dev card, at the +x, -z corner.
const CUT := 0.075
## The underside: a diamond layer, then the walnut plate, then the body.
const DIAMOND_DEPTH := 0.002
const PLATE_TOP := 0.004
const PLATE_INSET := 0.016
const FIELD_LIFT := 0.002
const GLYPH_HEIGHT := 0.006

const PLUM := Color("#5B4378")
const WALNUT := Color("#5A3E2A")
const WALNUT_TOP := Color("#7B5634")
const WALNUT_DARK := Color("#3F2B1A")
const BRASS := Color("#C9A46A")
const BRASS_LIGHT := Color("#E8C77C")
const BRASS_DARK := Color("#8E6A28")
const DEV_FIELD := Color("#E6D8BA")
const LOG_LIGHT := Color("#D9B27A")

static var _cache: Dictionary = {}


static func resource_card(resource: String) -> ArrayMesh:
	return _mesh("resource_" + resource, func() -> ClayBuilder: return resource_builder(resource))


static func development_card(kind: String) -> ArrayMesh:
	return _mesh("development_" + kind, func() -> ClayBuilder: return development_builder(kind))


static func card_back() -> ArrayMesh:
	return _mesh("back", func() -> ClayBuilder: return _back_builder(false))


static func dev_back() -> ArrayMesh:
	return _mesh("dev_back", func() -> ClayBuilder: return _back_builder(true))


static func resource_builder(resource: String) -> ClayBuilder:
	var result := ClayBuilder.new()
	var field := ClayPalette.mute(Palette.RESOURCE_COLORS[resource])
	_add_underside(result)
	_add_body(result, _outline(false), ClayPalette.mute(ClayPalette.CHIP_FACE))
	_add_field(result, _field_outline(false), field)
	var top := THICKNESS + FIELD_LIFT
	match resource:
		SiResource.CLAY:
			_glyph_clay(result, top)
		SiResource.WOOD:
			_glyph_wood(result, top)
		SiResource.SHEEP:
			_glyph_sheep(result, top)
		SiResource.WHEAT:
			_glyph_wheat(result, top)
		SiResource.ORE:
			_glyph_ore(result, top)
	return result


static func development_builder(kind: String) -> ClayBuilder:
	var result := ClayBuilder.new()
	_add_underside(result, PLUM)
	_add_body(result, _outline(true), ClayPalette.mute(PLUM))
	_add_field(result, _field_outline(true), ClayPalette.mute(DEV_FIELD))
	var top := THICKNESS + FIELD_LIFT
	match kind:
		SiDevelopmentCard.KNIGHT:
			_glyph_shield(result, top)
		SiDevelopmentCard.ROAD_BUILDING:
			_glyph_roads(result, top)
		SiDevelopmentCard.YEAR_OF_PLENTY:
			_glyph_two_cards(result, top)
		SiDevelopmentCard.MONOPOLY:
			_glyph_coins(result, top)
		SiDevelopmentCard.VICTORY_POINT:
			_glyph_star(result, top)
	return result


static func _mesh(key: String, build: Callable) -> ArrayMesh:
	if not _cache.has(key):
		var builder: ClayBuilder = build.call()
		_cache[key] = builder.to_mesh()
	return _cache[key]


## The body: a chamfered slab from the plate to the top of the card.
static func _add_body(result: ClayBuilder, outline: PackedVector2Array, color: Color) -> void:
	var transform := Transform3D(Basis.IDENTITY, Vector3(0.0, PLATE_TOP, 0.0))
	result.add_prism(transform, outline, THICKNESS - PLATE_TOP, color, 0.8)


## A thin coloured sheet on the body; its ao_floor of 1 keeps it flat.
static func _add_field(result: ClayBuilder, outline: PackedVector2Array, color: Color) -> void:
	result.add_prism(Transform3D(Basis.IDENTITY, Vector3(0.0, THICKNESS, 0.0)), outline, FIELD_LIFT, color, 0.95)


## Walnut plate and a brass diamond below it (an inverted pyramid, so its facets face down).
static func _add_underside(result: ClayBuilder, plate := WALNUT) -> void:
	var plate_half := Vector3(HALF.x - PLATE_INSET, (PLATE_TOP - DIAMOND_DEPTH) * 0.5, HALF.y - PLATE_INSET)
	var plate_centre := Vector3(0.0, DIAMOND_DEPTH + plate_half.y, 0.0)
	result.add_box(Transform3D(Basis.IDENTITY, plate_centre), plate_half, ClayPalette.mute(plate), 1.0)
	var flipped := Transform3D(Basis(Vector3.RIGHT, PI) * Basis(Vector3.UP, PI * 0.25), Vector3(0.0, DIAMOND_DEPTH, 0.0))
	result.add_pyramid(flipped, 0.08, 0.08, DIAMOND_DEPTH, BRASS, 1.0)


## Walnut back on top: body, a lighter inlay and a raised brass diamond.
static func _back_builder(cut_corner: bool) -> ClayBuilder:
	var result := ClayBuilder.new()
	if cut_corner:
		_add_back_top(result, true, PLUM, ClayPalette.shade(PLUM, 1.25))
	else:
		_add_back_top(result, false, WALNUT, WALNUT_TOP)
	return result


static func _add_back_top(result: ClayBuilder, cut_corner: bool, body: Color, inlay: Color) -> void:
	result.add_prism(Transform3D.IDENTITY, _outline(cut_corner), THICKNESS, ClayPalette.mute(body), 0.8)
	_add_field(result, _field_outline(cut_corner), ClayPalette.mute(inlay))
	var diamond := Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0.0, THICKNESS + FIELD_LIFT, 0.0))
	result.add_pyramid(diamond, 0.09, 0.09, GLYPH_HEIGHT * 1.5, BRASS, 0.9)
	result.add_pyramid(diamond, 0.045, 0.045, GLYPH_HEIGHT * 2.0, BRASS_LIGHT, 1.0)


## The card outline: four chamfered corners, or the +x/-z corner cut off for a dev card.
static func _outline(cut_corner: bool) -> PackedVector2Array:
	return _chamfered(HALF, CHAMFER, CUT if cut_corner else CHAMFER)


## The field is square-cornered (a chamfer there is invisible); a dev card's cut corner is pulled in with it.
static func _field_outline(cut_corner: bool) -> PackedVector2Array:
	var half := HALF - Vector2.ONE * BORDER_WIDTH
	if not cut_corner:
		return PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)])
	var cut := CUT - BORDER_WIDTH * 0.4
	return PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x - cut, -half.y), Vector2(half.x, -half.y + cut), half, Vector2(-half.x, half.y),
	])


static func _chamfered(half: Vector2, chamfer: float, cut: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-half.x + chamfer, -half.y), Vector2(half.x - cut, -half.y), Vector2(half.x, -half.y + cut),
		Vector2(half.x, half.y - chamfer), Vector2(half.x - chamfer, half.y), Vector2(-half.x + chamfer, half.y),
		Vector2(-half.x, half.y - chamfer), Vector2(-half.x, -half.y + chamfer),
	])


static func _rect(centre: Vector2, half: Vector2, yaw := 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for corner in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]:
		points.append(centre + (corner * half).rotated(yaw))
	return points


static func _ngon(centre: Vector2, radius: float, sides: int, phase := 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for side in sides:
		points.append(centre + Vector2.from_angle(phase + TAU * side / sides) * radius)
	return points


## A raised prism lying on `base` (y), `height` tall.
static func _block(result: ClayBuilder, outline: PackedVector2Array, base: float, height: float, color: Color, ao_floor := 0.8) -> void:
	result.add_prism(Transform3D(Basis.IDENTITY, Vector3(0.0, base, 0.0)), outline, height, ClayPalette.mute(color), ao_floor)


## A low hexagonal dome of facets: the lit side is lighter, the far side darker.
static func _dome(result: ClayBuilder, centre: Vector3, radius: float, height: float, color: Color) -> void:
	var sides := 6
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var apex := centre + Vector3(0.0, height, 0.0)
	for side in sides:
		var from := centre + _around(TAU * side / sides) * radius
		var to := centre + _around(TAU * (side + 1) / sides) * radius
		points.append_array([from, to, apex])
		var lit := -sin(TAU * (side + 0.5) / sides)
		colors.append(ClayPalette.shade(color, 0.82 + 0.2 * lit))
	result.add_facets(points, colors)


static func _around(angle: float) -> Vector3:
	return Vector3(cos(angle), 0.0, sin(angle))


## Clay: a pyramid of three dark bricks with a lighter one on top, and one more behind.
static func _glyph_clay(result: ClayBuilder, top: float) -> void:
	var brick := Color("#7E3A22")
	var half := Vector2(0.075, 0.04)
	var height := 0.02
	for side in [-1.0, 1.0]:
		_block(result, _rect(Vector2(side * 0.08, 0.075), half), top, height, brick)
	_block(result, _rect(Vector2(0.0, 0.075), half), top + height, height, ClayPalette.shade(brick, 1.3))
	_block(result, _rect(Vector2(0.0, -0.05), half), top, height, ClayPalette.shade(brick, 1.1))


## Wood: three log ends, bark ring and a faceted light end grain.
static func _glyph_wood(result: ClayBuilder, top: float) -> void:
	var bark := Color("#8A5C36")
	var logs := [[Vector2(-0.08, 0.075), 0.075, 0.024], [Vector2(0.08, 0.075), 0.075, 0.024], [Vector2(0.0, -0.055), 0.085, 0.036]]
	for log: Array in logs:
		var centre: Vector2 = log[0]
		var radius: float = log[1]
		var height: float = log[2]
		_block(result, _ngon(centre, radius, 5, -PI * 0.5), top, height, bark, 0.75)
		_end_grain(result, Vector3(centre.x, top + height, centre.y), radius * 0.82)


## A flat five-facet cap, the lit facets lighter.
static func _end_grain(result: ClayBuilder, centre: Vector3, radius: float) -> void:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	for side in 5:
		var from := centre + _around(-PI * 0.5 + TAU * side / 5.0) * radius
		var to := centre + _around(-PI * 0.5 + TAU * (side + 1) / 5.0) * radius
		points.append_array([from, to, centre + Vector3(0.0, 0.006, 0.0)])
		colors.append(ClayPalette.shade(LOG_LIGHT, 1.0 if side % 2 == 0 else 0.86))
	result.add_facets(points, colors)


## Sheep: a fleece cloud of four domes with a dark face and ears at the front.
static func _glyph_sheep(result: ClayBuilder, top: float) -> void:
	var fleece := Palette.FLEECE
	_dome(result, Vector3(-0.075, top, 0.0), 0.085, 0.05, fleece)
	_dome(result, Vector3(0.075, top, 0.0), 0.085, 0.05, fleece)
	_dome(result, Vector3(0.0, top, -0.07), 0.09, 0.06, fleece)
	_dome(result, Vector3(0.0, top, 0.025), 0.095, 0.065, ClayPalette.shade(fleece, 1.04))
	_block(result, _ngon(Vector2(0.0, 0.105), 0.055, 5, PI * 0.5), top, 0.03, ClayPalette.SHEEP_FACE, 0.9)


## Wheat: three fanned stalks with a grain head each.
static func _glyph_wheat(result: ClayBuilder, top: float) -> void:
	var gold := ClayPalette.EAR_GOLD
	var stalk := ClayPalette.STRAW_DARK
	var root := Vector2(0.0, 0.17)
	for tilt in [-0.32, 0.0, 0.32]:
		var direction := Vector2(0.0, -1.0).rotated(tilt)
		var length := 0.3 if tilt == 0.0 else 0.26
		_block(result, _rect(root + direction * length * 0.4, Vector2(0.01, length * 0.4), tilt), top, GLYPH_HEIGHT * 0.5, stalk, 1.0)
		var head := root + direction * (length + 0.01)
		_block(result, _ngon_stretched(head, Vector2(0.036, 0.075), tilt), top, 0.012, gold, 0.85)


static func _ngon_stretched(centre: Vector2, radii: Vector2, yaw: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for corner in [Vector2(0.0, -1.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(-1.0, 0.0)]:
		points.append(centre + (corner * radii).rotated(yaw))
	return points


## Ore: a big stone peak, a second smaller one and a brass nugget.
static func _glyph_ore(result: ClayBuilder, top: float) -> void:
	var stone := ClayPalette.STONE_GREY
	var raise := Transform3D(Basis(Vector3.UP, 0.4), Vector3(-0.03, top, 0.0))
	result.add_pyramid(raise, 0.11, 0.11, 0.075, ClayPalette.shade(stone, 1.15), 0.8)
	var second := Transform3D(Basis(Vector3.UP, -0.3), Vector3(0.075, top, 0.07))
	result.add_pyramid(second, 0.075, 0.075, 0.05, ClayPalette.shade(stone, 0.9), 0.8)
	var nugget := Transform3D(Basis(Vector3.UP, 0.8), Vector3(-0.09, top, 0.1))
	result.add_pyramid(nugget, 0.04, 0.04, 0.035, BRASS_LIGHT, 0.9)


## Knight: a shield with a lighter boss panel.
static func _glyph_shield(result: ClayBuilder, top: float) -> void:
	var steel := ClayPalette.STONE_GREY
	var outline := PackedVector2Array([Vector2(-0.1, -0.1), Vector2(0.1, -0.1), Vector2(0.1, 0.03), Vector2(0.0, 0.15), Vector2(-0.1, 0.03)])
	_block(result, outline, top, 0.014, steel, 0.8)
	var inner := PackedVector2Array()
	for point in outline:
		inner.append(point * 0.62 + Vector2(0.0, -0.012))
	_block(result, inner, top + 0.014, 0.008, PLUM, 1.0)


## Road building: two bars side by side, tilted like pieces being laid.
static func _glyph_roads(result: ClayBuilder, top: float) -> void:
	var wood := ClayPalette.WOOD_BROWN
	_block(result, _rect(Vector2(-0.03, -0.05), Vector2(0.15, 0.045), -0.35), top, 0.024, wood, 0.8)
	_block(result, _rect(Vector2(0.03, 0.07), Vector2(0.15, 0.045), -0.35), top, 0.024, ClayPalette.shade(wood, 1.3), 0.8)


## Year of plenty: two small cards, one green and one gold, fanned.
static func _glyph_two_cards(result: ClayBuilder, top: float) -> void:
	var leaf := ClayPalette.LEAF_BRIGHT
	var gold := ClayPalette.STRAW
	_block(result, _rect(Vector2(-0.05, 0.0), Vector2(0.075, 0.105), -0.25), top, 0.012, ClayPalette.shade(leaf, 0.95), 0.85)
	_block(result, _rect(Vector2(0.05, 0.0), Vector2(0.075, 0.105), 0.25), top + 0.006, 0.012, gold, 0.85)
	_block(result, _rect(Vector2(0.05, 0.0), Vector2(0.035, 0.06), 0.25), top + 0.018, 0.004, ClayPalette.shade(gold, 1.2), 1.0)


## Monopoly: a heap of three brass coins.
static func _glyph_coins(result: ClayBuilder, top: float) -> void:
	_block(result, _ngon(Vector2(-0.055, 0.06), 0.09, 6), top, 0.014, BRASS_DARK, 0.8)
	_block(result, _ngon(Vector2(0.065, 0.075), 0.085, 6, 0.3), top, 0.014, BRASS, 0.8)
	_block(result, _ngon(Vector2(0.0, -0.045), 0.095, 6, 0.15), top + 0.014, 0.014, BRASS_LIGHT, 0.8)


## Victory point: a faceted five-point star, gold.
static func _glyph_star(result: ClayBuilder, top: float) -> void:
	var gold := Color("#F3C54A")
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var apex := Vector3(0.0, top + 0.012, -0.015)
	for index in 10:
		var from := _star_point(index, top)
		var to := _star_point(index + 1, top)
		points.append_array([from, to, apex])
		colors.append(ClayPalette.shade(gold, 1.08 if index % 2 == 0 else 0.82))
	result.add_facets(points, colors)


static func _star_point(index: int, top: float) -> Vector3:
	var radius := 0.14 if index % 2 == 0 else 0.062
	var direction := Vector2.from_angle(-PI * 0.5 + PI * index / 5.0) * radius
	return Vector3(direction.x, top, direction.y - 0.015)
