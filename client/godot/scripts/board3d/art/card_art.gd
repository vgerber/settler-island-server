class_name CardArt
extends RefCounted
## Resource and development cards as faceted clay, lying face up on y = 0 (x across, z along the long side; the
## glyph's up is -z, so it reads upright for the default camera). Origin at the centre of the base, front toward +z.
## A face is a card-stock rim around a light field (a pale tint of the resource; dev cards: pale lavender) with a
## saturated band down each long side that tells the resource at a glance, and one raised clay miniature in dark
## saturated shades. Dev cards have a plum band and one cut corner. The underside is a walnut plate with a brass
## diamond. `card_back` and `dev_back` have the back on top (walnut or plum, a brass frame and emblem), for
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
const FIELD_LIFT := 0.001
## The side bands of a face.
const BAND_WIDTH := 0.04

const PLUM := Color("#5B4378")
const WALNUT := Color("#5A3E2A")
const WALNUT_TOP := Color("#7B5634")
const WALNUT_DARK := Color("#3F2B1A")
const BRASS := Color("#C9A46A")
const BRASS_LIGHT := Color("#E8C77C")
const BRASS_DARK := Color("#8E6A28")
const DEV_FIELD := Color("#BFB1D3")
## How far a resource field is pulled toward card stock.
const FIELD_PALE := 0.3
const INK_PLUM := Color("#3E2C57")
const STEEL_DARK := Color("#4A5266")
const STEEL_LIGHT := Color("#A9B1C2")

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
	var resource_color: Color = Palette.RESOURCE_COLORS[resource]
	var field := ClayPalette.mute(resource_color).lerp(ClayPalette.CHIP_FACE, FIELD_PALE)
	_add_underside(result)
	_add_body(result, _outline(false), ClayPalette.mute(ClayPalette.CHIP_FACE))
	_add_face(result, false, field, ClayPalette.mute(resource_color))
	match resource:
		SiResource.CLAY:
			_glyph_clay(result)
		SiResource.WOOD:
			_glyph_wood(result)
		SiResource.SHEEP:
			_glyph_sheep(result)
		SiResource.WHEAT:
			_glyph_wheat(result)
		SiResource.ORE:
			_glyph_ore(result)
	return result


static func development_builder(kind: String) -> ClayBuilder:
	var result := ClayBuilder.new()
	_add_underside(result, PLUM)
	_add_body(result, _outline(true), ClayPalette.mute(PLUM))
	_add_face(result, true, ClayPalette.mute(DEV_FIELD), ClayPalette.mute(PLUM))
	match kind:
		SiDevelopmentCard.KNIGHT:
			_glyph_knight(result)
		SiDevelopmentCard.ROAD_BUILDING:
			_glyph_roads(result)
		SiDevelopmentCard.YEAR_OF_PLENTY:
			_glyph_cornucopia(result)
		SiDevelopmentCard.MONOPOLY:
			_glyph_coins(result)
		SiDevelopmentCard.VICTORY_POINT:
			_glyph_star(result)
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


## The field and a band down each long side, as flat sheets (a prism per sheet would cost 10 triangles more).
static func _add_face(result: ClayBuilder, cut_corner: bool, field: Color, band: Color) -> void:
	_sheet(result, _field_outline(cut_corner), THICKNESS + FIELD_LIFT, field)
	var half := HALF - Vector2.ONE * BORDER_WIDTH
	var raised := THICKNESS + FIELD_LIFT * 1.8
	_sheet(result, _rect_corners(Vector2(-half.x, -half.y), Vector2(-half.x + BAND_WIDTH, half.y)), raised, band)
	var cut := (CUT - BORDER_WIDTH * 0.4) if cut_corner else 0.0
	var top := -half.y + maxf(cut - BAND_WIDTH, 0.0)
	var right := PackedVector2Array([Vector2(half.x - BAND_WIDTH, top), Vector2(half.x, -half.y + cut), half, Vector2(half.x - BAND_WIDTH, half.y)])
	_sheet(result, right, raised, band)


## Where glyphs stand: just above the sheets.
static func _top() -> float:
	return THICKNESS + FIELD_LIFT * 2.5


## A flat convex polygon facing up at `height`.
static func _sheet(result: ClayBuilder, outline: PackedVector2Array, height: float, color: Color) -> void:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	for index in range(1, outline.size() - 1):
		for corner in [outline[0], outline[index], outline[index + 1]]:
			points.append(Vector3(corner.x, height, corner.y))
		colors.append(color)
	result.add_facets(points, colors)


static func _rect_corners(from: Vector2, to: Vector2) -> PackedVector2Array:
	return PackedVector2Array([from, Vector2(to.x, from.y), to, Vector2(from.x, to.y)])


## Walnut plate and a brass diamond below it (an inverted pyramid, so its facets face down).
static func _add_underside(result: ClayBuilder, plate := WALNUT) -> void:
	var plate_half := Vector3(HALF.x - PLATE_INSET, (PLATE_TOP - DIAMOND_DEPTH) * 0.5, HALF.y - PLATE_INSET)
	var plate_centre := Vector3(0.0, DIAMOND_DEPTH + plate_half.y, 0.0)
	result.add_box(Transform3D(Basis.IDENTITY, plate_centre), plate_half, ClayPalette.mute(plate), 1.0)
	var flipped := Transform3D(Basis(Vector3.RIGHT, PI) * Basis(Vector3.UP, PI * 0.25), Vector3(0.0, DIAMOND_DEPTH, 0.0))
	result.add_pyramid(flipped, 0.08, 0.08, DIAMOND_DEPTH, BRASS, 1.0)


## A crafted back: a walnut (dev: plum) body with a lighter inlay, a brass frame line, brass studs in the corners
## and a raised brass diamond with a dark jewel.
static func _back_builder(cut_corner: bool) -> ClayBuilder:
	var result := ClayBuilder.new()
	var body := PLUM if cut_corner else WALNUT
	var inlay := ClayPalette.shade(PLUM, 1.15) if cut_corner else WALNUT_TOP
	var jewel := INK_PLUM if cut_corner else WALNUT_DARK
	result.add_prism(Transform3D.IDENTITY, _outline(cut_corner), THICKNESS, ClayPalette.mute(body), 0.8)
	var field := _field_outline(cut_corner)
	_sheet(result, field, THICKNESS + FIELD_LIFT, ClayPalette.mute(inlay))
	_add_frame(result, field, ClayPalette.mute(BRASS))
	var top := _top()
	var diamond := Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0.0, top, 0.0))
	result.add_pyramid(diamond, 0.1, 0.1, 0.008, ClayPalette.mute(BRASS_DARK), 0.9)
	result.add_pyramid(diamond.translated(Vector3(0.0, 0.006, 0.0)), 0.07, 0.07, 0.01, ClayPalette.mute(BRASS), 1.0)
	result.add_pyramid(diamond.translated(Vector3(0.0, 0.014, 0.0)), 0.03, 0.03, 0.01, ClayPalette.mute(jewel), 1.0)
	for corner in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]:
		var stud := Vector2(corner.x * 0.115, corner.y * 0.175)
		var placed := Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(stud.x, top, stud.y))
		result.add_pyramid(placed, 0.016, 0.016, 0.008, ClayPalette.mute(BRASS_LIGHT), 1.0)
	return result


## A thin line of brass around the inlay.
static func _add_frame(result: ClayBuilder, field: PackedVector2Array, color: Color) -> void:
	var outer := _inset(field, 0.012)
	var inner := _inset(field, 0.02)
	for index in outer.size():
		var next := (index + 1) % outer.size()
		_sheet(result, PackedVector2Array([outer[index], outer[next], inner[next], inner[index]]), THICKNESS + FIELD_LIFT * 1.8, color)


## A convex polygon moved inward by `distance` along every edge.
static func _inset(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	var centre := Vector2.ZERO
	for point in points:
		centre += point / points.size()
	for index in points.size():
		var before := points[(index + points.size() - 1) % points.size()]
		var after := points[(index + 1) % points.size()]
		var inward_before := _edge_inward(before, points[index], centre)
		var inward_after := _edge_inward(points[index], after, centre)
		result.append(points[index] + (inward_before + inward_after) * distance / (1.0 + inward_before.dot(inward_after)))
	return result


static func _edge_inward(from: Vector2, to: Vector2, centre: Vector2) -> Vector2:
	var normal := (to - from).orthogonal().normalized()
	return normal if normal.dot(centre - from) > 0.0 else -normal


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


# --- Shared parts ---------------------------------------------------------------------------------------------


static func _around(angle: float) -> Vector3:
	return Vector3(cos(angle), 0.0, sin(angle))


static func _ngon(centre: Vector2, radius: float, sides: int, phase := 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for side in sides:
		points.append(centre + Vector2.from_angle(phase + TAU * side / sides) * radius)
	return points


## A bar with pointed ends along its local x, turned by `yaw`.
static func _bar(centre: Vector2, half_length: float, half_width: float, yaw: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for corner in [Vector2(-half_length - half_width, 0.0), Vector2(-half_length, -half_width), Vector2(half_length, -half_width),
			Vector2(half_length + half_width, 0.0), Vector2(half_length, half_width), Vector2(-half_length, half_width)]:
		points.append(centre + corner.rotated(yaw))
	return points


## A raised prism standing on `base` (y), `height` tall; the colour is muted like all clay.
static func _block(result: ClayBuilder, outline: PackedVector2Array, base: float, height: float, color: Color, ao_floor := 0.8) -> void:
	result.add_prism(Transform3D(Basis.IDENTITY, Vector3(0.0, base, 0.0)), outline, height, ClayPalette.mute(color), ao_floor)


## A box on the card at `centre` (x, z) whose bottom is `base` (y).
static func _brick(result: ClayBuilder, centre: Vector2, base: float, half: Vector3, yaw: float, color: Color) -> void:
	var transform := Transform3D(Basis(Vector3.UP, yaw), Vector3(centre.x, base + half.y, centre.y))
	result.add_box(transform, half, ClayPalette.mute(color), 0.8)


## A low hexagonal dome of facets: the lit side is lighter, the far side darker.
static func _dome(result: ClayBuilder, centre: Vector3, radius: float, height: float, color: Color, contrast := 0.2) -> void:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var apex := centre + Vector3(0.0, height, 0.0)
	for side in 6:
		var from := centre + _around(TAU * side / 6.0) * radius
		var to := centre + _around(TAU * (side + 1) / 6.0) * radius
		points.append_array([from, to, apex])
		var lit := -sin(TAU * (side + 0.5) / 6.0)
		colors.append(ClayPalette.shade(ClayPalette.mute(color), 1.02 - contrast + contrast * lit))
	result.add_facets(points, colors)


## A faceted rock: five sides narrowing to a crown; every facet has its own shade.
static func _chunk(result: ClayBuilder, centre: Vector2, base: float, radius: float, height: float, yaw: float, color: Color) -> void:
	var lower := PackedVector3Array()
	var upper := PackedVector3Array()
	for side in 5:
		var angle := yaw + TAU * side / 5.0
		var wobble := 1.0 + 0.18 * sin(side * 2.3 + yaw * 3.0)
		lower.append(Vector3(centre.x, base, centre.y) + _around(angle) * radius * wobble)
		upper.append(Vector3(centre.x, base + height * 0.62, centre.y) + _around(angle + 0.25) * radius * 0.62)
	var apex := Vector3(centre.x + radius * 0.1, base + height, centre.y - radius * 0.1)
	var muted := ClayPalette.mute(color)
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	for side in 5:
		var next := (side + 1) % 5
		points.append_array([lower[side], lower[next], upper[side], lower[next], upper[next], upper[side], upper[side], upper[next], apex])
		var lit := 0.78 + 0.34 * clampf(-sin(yaw + TAU * (side + 0.5) / 5.0) * 0.5 + 0.5, 0.0, 1.0)
		colors.append_array([ClayPalette.shade(muted, lit * 0.92), ClayPalette.shade(muted, lit * 0.8), ClayPalette.shade(muted, lit * 1.1)])
	result.add_facets(points, colors)


## A flat disc of `sides` triangles facing along `frame`'s z, `depth` along it.
static func _disc(result: ClayBuilder, frame: Transform3D, depth: float, radius: float, sides: int, color: Color) -> void:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	for side in sides:
		var from := Vector2.from_angle(TAU * side / sides) * radius
		var to := Vector2.from_angle(TAU * (side + 1) / sides) * radius
		points.append_array([frame * Vector3(0.0, 0.0, depth), frame * Vector3(from.x, from.y, depth), frame * Vector3(to.x, to.y, depth)])
		colors.append(color)
	result.add_facets(points, colors)


## The dark inside of a horn's open end, facing along from -> to.
static func _mouth(result: ClayBuilder, from: Vector3, to: Vector3, radius: float) -> void:
	var axis := (to - from).normalized()
	var across := Vector3.UP.cross(axis).normalized()
	var frame := Transform3D(Basis(across, axis.cross(across), axis), to)
	_disc(result, frame, 0.002, radius * 0.92, 6, ClayPalette.mute(Color("#3A2412")))


## A frustum from `from` to `to` (not vertical), so chained tubes with equal joint radii form a curved horn.
static func _tube(result: ClayBuilder, from: Vector3, to: Vector3, radius_from: float, radius_to: float, color: Color) -> void:
	var direction := to - from
	var length := direction.length()
	var axis := direction / length
	var across := Vector3.UP.cross(axis).normalized()
	var transform := Transform3D(Basis(axis.cross(across), axis, across), from)
	var profile := PackedVector2Array([Vector2(radius_from, 0.0), Vector2(radius_to, length)])
	result.add_lathe(profile, transform, ClayPalette.mute(color), 0.65, 6)


static func _sheet_hex(result: ClayBuilder, radius: float, height: float, color: Color) -> void:
	_sheet(result, _ngon(Vector2.ZERO, radius, 6, PI * 0.5), height, color)


# --- Resources ------------------------------------------------------------------------------------------------


## Clay: a stack of fired bricks in three courses, bonded, with a loose brick in front.
static func _glyph_clay(result: ClayBuilder) -> void:
	var half := Vector3(0.05, 0.016, 0.028)
	var kiln := Color("#9E3B1E")
	var top := _top()
	var courses := [[-0.052, 0.052, 0.0], [-0.034, 0.07, 0.03], [-0.052, 0.052, -0.025]]
	for course in courses.size():
		var offsets: Array = courses[course]
		for side in 2:
			var shade: float = [0.86, 1.0, 1.15, 0.94][(course + side * 2) % 4]
			var centre := Vector2(offsets[side], -0.07)
			_brick(result, centre, top + course * half.y * 2.0, half, offsets[2] * (1.0 - side * 2.0), ClayPalette.shade(kiln, shade))
	_brick(result, Vector2(-0.03, 0.06), top, half, 0.22, ClayPalette.shade(kiln, 1.08))
	_brick(result, Vector2(0.03, 0.15), top, half, -0.3, ClayPalette.shade(kiln, 0.9))


## Wood: a pile of three logs lying toward the camera, bark rings and light cut ends.
static func _glyph_wood(result: ClayBuilder) -> void:
	var bark := ClayPalette.mute(Color("#5E3A1E"))
	var cut := ClayPalette.mute(Color("#E2B572"))
	var radius := 0.047
	var length := 0.085
	var top := _top()
	for log in [Vector2(-radius, 0.0), Vector2(radius, 0.0), Vector2(0.0, radius * 1.74)]:
		var frame := Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(log.x, top + radius + log.y, 0.1 - log.y * 0.6))
		var lying := frame * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
		var profile := PackedVector2Array([Vector2(radius, -length), Vector2(radius, length)])
		result.add_lathe(profile, lying, bark, 0.6, 6)
		_disc(result, frame, length, radius, 6, bark)
		_disc(result, frame, length + 0.002, radius * 0.76, 6, cut)


## Sheep: the board's sheep, a fleece of domes with a dark face, ears and front legs, on a patch of pasture.
static func _glyph_sheep(result: ClayBuilder) -> void:
	var fleece := Palette.FLEECE
	var face := ClayPalette.SHEEP_FACE
	var top := _top()
	_sheet_hex(result, 0.115, top, ClayPalette.mute(Color("#3F7A34")))
	var base := top + 0.004
	for leg in [-1.0, 1.0]:
		_brick(result, Vector2(leg * 0.05, 0.045), base, Vector3(0.01, 0.02, 0.01), 0.0, face)
	_dome(result, Vector3(-0.04, base + 0.012, -0.03), 0.06, 0.045, ClayPalette.shade(fleece, 0.95), 0.12)
	_dome(result, Vector3(0.04, base + 0.012, -0.03), 0.06, 0.045, ClayPalette.shade(fleece, 0.95), 0.12)
	_dome(result, Vector3(0.0, base + 0.012, -0.07), 0.055, 0.04, ClayPalette.shade(fleece, 0.92), 0.12)
	_dome(result, Vector3(0.0, base + 0.016, 0.0), 0.07, 0.055, fleece, 0.12)
	_brick(result, Vector2(0.0, 0.113), base + 0.012, Vector3(0.02, 0.014, 0.028), 0.0, face)
	for ear in [-1.0, 1.0]:
		var placed := Transform3D(Basis(Vector3.BACK, ear * 0.9), Vector3(ear * 0.034, base + 0.04, 0.08))
		result.add_pyramid(placed, 0.009, 0.013, 0.024, ClayPalette.mute(face), 0.9)


## Wheat: three fanned stalks, each with five grains lying along its head, bound by a brown tie.
static func _glyph_wheat(result: ClayBuilder) -> void:
	var top := _top()
	var root := Vector2(0.0, 0.2)
	var stalk := ClayPalette.mute(Color("#8A6418"))
	for tilt in [-0.33, 0.0, 0.33]:
		var direction := Vector2(0.0, -1.0).rotated(tilt)
		var side := direction.orthogonal()
		var length := 0.34 if tilt == 0.0 else 0.29
		var tip := root + direction * length
		_sheet(result, PackedVector2Array([root - side * 0.009, root + side * 0.009, tip + side * 0.006, tip - side * 0.006]), top + 0.002, stalk)
		for pair in 2:
			var spot := root + direction * (length - 0.14 + pair * 0.065)
			for sign_value in [-1.0, 1.0]:
				_grain(result, spot + side * sign_value * 0.01, direction.rotated(sign_value * 0.6), top, pair)
		_grain(result, tip - direction * 0.03, direction, top, 1)
	var tie := ClayPalette.mute(Color("#6B3F1E"))
	_sheet(result, _rect_corners(Vector2(-0.058, 0.105), Vector2(0.058, 0.125)), top + 0.004, tie)


## A grain: a small pyramid lying on the card, its tip along `direction` (x, z).
static func _grain(result: ClayBuilder, at: Vector2, direction: Vector2, top: float, variant: int) -> void:
	var axis := Vector3(direction.x, 0.0, direction.y)
	var across := Vector3.UP.cross(axis).normalized()
	var transform := Transform3D(Basis(axis.cross(across), axis, across), Vector3(at.x, top + 0.014, at.y))
	var color := Color("#E0A32A") if variant == 0 else Color("#C78A16")
	result.add_pyramid(transform, 0.014, 0.014, 0.058, ClayPalette.mute(color), 0.9)


## Ore: three faceted chunks with copper veins, and a miner's pick laid across the front.
static func _glyph_ore(result: ClayBuilder) -> void:
	var slate := Color("#5A6A8A")
	var top := _top()
	_chunk(result, Vector2(-0.045, -0.095), top, 0.082, 0.14, 0.3, slate)
	_chunk(result, Vector2(0.06, -0.06), top, 0.06, 0.09, 1.1, ClayPalette.shade(slate, 1.12))
	_chunk(result, Vector2(-0.07, -0.01), top, 0.045, 0.06, 2.0, ClayPalette.shade(slate, 0.9))
	var copper := ClayPalette.mute(Color("#D9782A"))
	for vein in [Vector2(0.015, -0.115), Vector2(0.075, -0.045)]:
		var placed := Transform3D(Basis(Vector3.UP, 0.6), Vector3(vein.x, top + 0.06, vein.y))
		result.add_pyramid(placed, 0.018, 0.018, 0.026, copper, 0.9)
	var yaw := -0.45
	var middle := Vector2(0.0, 0.15)
	_brick(result, middle, top, Vector3(0.1, 0.01, 0.01), yaw, Color("#7A4A22"))
	var end := middle + Vector2(-0.095, 0.0).rotated(yaw)
	_block(result, _bar(end, 0.05, 0.014, yaw + PI * 0.5), top, 0.03, STEEL_DARK, 0.8)


# --- Development cards ----------------------------------------------------------------------------------------


## Knight: a plum shield with a gold cross in a steel rim, over a sword.
static func _glyph_knight(result: ClayBuilder) -> void:
	var top := _top()
	var blade := PackedVector2Array([Vector2(-0.016, -0.17), Vector2(0.0, -0.215), Vector2(0.016, -0.17), Vector2(0.016, 0.145), Vector2(-0.016, 0.145)])
	var edge := PackedVector2Array([Vector2(-0.024, -0.17), Vector2(0.0, -0.225), Vector2(0.024, -0.17), Vector2(0.024, 0.145), Vector2(-0.024, 0.145)])
	_sheet(result, edge, top + 0.001, ClayPalette.mute(STEEL_DARK))
	_sheet(result, blade, top + 0.002, ClayPalette.mute(STEEL_LIGHT))
	_brick(result, Vector2(0.0, 0.155), top, Vector3(0.06, 0.008, 0.012), 0.0, Color("#B8841C"))
	_brick(result, Vector2(0.0, 0.2), top, Vector3(0.012, 0.008, 0.026), 0.0, Color("#6B3F1E"))
	result.add_pyramid(Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0.0, top, 0.232)), 0.016, 0.016, 0.014, ClayPalette.mute(Color("#B8841C")), 0.9)
	var outline := PackedVector2Array([Vector2(-0.092, -0.1), Vector2(0.092, -0.1), Vector2(0.092, 0.015), Vector2(0.0, 0.14), Vector2(-0.092, 0.015)])
	_block(result, outline, top + 0.003, 0.012, STEEL_DARK, 0.8)
	var inner := PackedVector2Array()
	for point in outline:
		inner.append(point * 0.74 + Vector2(0.0, -0.012))
	_block(result, inner, top + 0.015, 0.008, PLUM, 1.0)
	var gold := ClayPalette.mute(Color("#EBB93A"))
	var height := top + 0.024
	_sheet(result, _rect_corners(Vector2(-0.012, -0.085), Vector2(0.012, 0.085)), height, gold)
	_sheet(result, _rect_corners(Vector2(-0.055, -0.045), Vector2(0.055, -0.021)), height, gold)


## Road building: two road pieces, a red and a blue one, laid one behind the other.
static func _glyph_roads(result: ClayBuilder) -> void:
	var top := _top()
	var yaw := -0.5
	var pieces := [[Vector2(0.0, -0.085), Color("#C8372D")], [Vector2(0.0, 0.1), Color("#2E62C9")]]
	for piece: Array in pieces:
		var centre: Vector2 = piece[0]
		var color: Color = piece[1]
		_block(result, _bar(centre, 0.1, 0.045, yaw), top, 0.016, ClayPalette.shade(color, 0.72), 0.7)
		_block(result, _bar(centre, 0.085, 0.032, yaw), top + 0.016, 0.01, color, 0.9)
		_sheet(result, _bar(centre, 0.07, 0.007, yaw), top + 0.027, ClayPalette.mute(ClayPalette.shade(color, 1.35)))



## Year of plenty: a cornucopia of curled horn with an apple, an orange, a pear and plums spilling out.
static func _glyph_cornucopia(result: ClayBuilder) -> void:
	var top := _top()
	var horn := Color("#B87A1E")
	var path := [Vector2(-0.085, -0.2), Vector2(-0.092, -0.1), Vector2(-0.045, -0.005), Vector2(0.035, 0.065)]
	var radii := [0.016, 0.036, 0.058, 0.078]
	for index in 3:
		var color := ClayPalette.shade(horn, 0.85 + 0.15 * index)
		var from := Vector3(path[index].x, top + radii[index] * 0.9, path[index].y)
		var to := Vector3(path[index + 1].x, top + radii[index + 1] * 0.9, path[index + 1].y)
		_tube(result, from, to, radii[index], radii[index + 1], color)
		if index == 2:
			_mouth(result, from, to, radii[index + 1])
	var base := top + 0.006
	_dome(result, Vector3(0.06, base, 0.11), 0.06, 0.065, Color("#C42B22"))
	_dome(result, Vector3(-0.005, base, 0.16), 0.052, 0.058, Color("#E5800F"))
	_dome(result, Vector3(0.1, base, 0.04), 0.042, 0.048, Color("#4F8F2F"))
	_dome(result, Vector3(-0.05, base, 0.1), 0.04, 0.045, Color("#6A3790"))
	_dome(result, Vector3(0.095, base, 0.17), 0.038, 0.042, Color("#6A3790"))


## Monopoly: a stack of three gold coins and one lying in front, on a plum medallion.
static func _glyph_coins(result: ClayBuilder) -> void:
	var top := _top()
	_sheet_hex(result, 0.115, top, ClayPalette.mute(INK_PLUM))
	var gold := Color("#E0A92E")
	var rim := Color("#9A6B14")
	for level in 3:
		var centre := Vector2(0.008 * (level - 1), -0.05)
		_block(result, _ngon(centre, 0.08, 6, 0.2 * level), top + 0.002 + level * 0.02, 0.02, gold if level % 2 == 0 else ClayPalette.shade(gold, 0.88), 0.75)
	_sheet(result, _ngon(Vector2(0.0, -0.05), 0.05, 6, 0.4), top + 0.064, ClayPalette.mute(rim))
	_block(result, _ngon(Vector2(0.0, 0.1), 0.065, 6, 0.5), top + 0.002, 0.02, ClayPalette.shade(gold, 1.1), 0.8)
	_sheet(result, _ngon(Vector2(0.0, 0.1), 0.04, 6, 0.5), top + 0.024, ClayPalette.mute(rim))


## Victory point: a faceted gold star in a gold ring on a plum medallion, with five gems between its points.
static func _glyph_star(result: ClayBuilder) -> void:
	var top := _top()
	_sheet_hex(result, 0.115, top, ClayPalette.mute(INK_PLUM))
	var gold := Color("#E8B02E")
	_star(result, top + 0.003, 0.108, 0.058, 0.0, ClayPalette.shade(gold, 0.66), ClayPalette.shade(gold, 0.55))
	_star(result, top + 0.012, 0.094, 0.05, 0.016, ClayPalette.shade(gold, 1.0), ClayPalette.shade(gold, 0.82))
	var gem := Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3.ZERO)
	for index in 5:
		var spot := Vector2.from_angle(-PI * 0.5 + TAU * (index + 0.5) / 5.0) * 0.092
		result.add_pyramid(gem.translated(Vector3(spot.x, top + 0.004, spot.y)), 0.012, 0.012, 0.014, ClayPalette.mute(Color("#E5E1EE")), 0.9)


## A five-point star of ten facets around an apex raised by `lift`; the lit points are lighter.
static func _star(result: ClayBuilder, height: float, outer: float, inner: float, lift: float, light: Color, dark: Color) -> void:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var apex := Vector3(0.0, height + lift, 0.0)
	for index in 10:
		for corner in [index, index + 1]:
			var radius := outer if corner % 2 == 0 else inner
			var direction := Vector2.from_angle(-PI * 0.5 + PI * corner / 5.0) * radius
			points.append(Vector3(direction.x, height, direction.y))
		points.append(apex)
		colors.append(ClayPalette.mute(light if index % 2 == 0 else dark))
	result.add_facets(points, colors)
