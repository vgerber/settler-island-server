class_name CardArt
extends RefCounted
## Resource and development cards as faceted clay, lying face up on y = 0 (x across, z along the long side; the
## icon's up is -z, so it reads upright for the default camera). Origin at the centre of the base, front toward +z.
## A face is a card-stock rim around a light field (a pale tint of the resource; dev cards: pale lavender) with a
## saturated band down each long side that tells the resource at a glance, and one flat printed icon (`FlatIconArt`,
## the 2D HUD's icon language) lying on the field. Dev cards have a plum band and one cut corner. The underside is a walnut plate with a brass
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
## Icon edge on the field, and where its centre sits.
const ICON_SIZE_RESOURCE := 0.22
const ICON_SIZE_DEVELOPMENT := 0.2
const ICON_CENTRE := Vector2(0.0, 0.0)

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
	_add_icon(result, resource, ICON_SIZE_RESOURCE)
	return result


static func development_builder(kind: String) -> ClayBuilder:
	var result := ClayBuilder.new()
	_add_underside(result, PLUM)
	_add_body(result, _outline(true), ClayPalette.mute(PLUM))
	_add_face(result, true, ClayPalette.mute(DEV_FIELD), ClayPalette.mute(PLUM))
	_add_icon(result, kind, ICON_SIZE_DEVELOPMENT)
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


## Where icons lie: just above the sheets.
static func _add_icon(result: ClayBuilder, icon: String, size: float) -> void:
	FlatIconArt.add(result, icon, Transform3D.IDENTITY, ICON_CENTRE, size, _top())


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
