class_name IconShapes
extends RefCounted
## Flat icons as convex polygons in a unit box (-0.5..0.5, y down) for every resource and development card kind. One
## source for the 3D card and port faces (`FlatIconArt`) and the 2D HUD (`ResourceArt.draw_development_icon`). A layer is
## {points, fill, ink, group}: `ink` layers get an ink outline, and consecutive layers of one `group` (>= 0) share one
## outer outline (all outlines first, then all fills), which is how the fleece cloud and the star stay seamless.

const DISC_SIDES := 10
const GOLD := Color("#E0A82A")
const GOLD_DARK := Color("#B07C14")
const STEEL := Color("#A9B1C2")
const PLUM := Color("#5B4378")
const ROAD := Color("#8C7B62")


static func layers(icon: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	match icon:
		SiResource.WOOD:
			_wood(result)
		SiResource.SHEEP:
			_sheep(result)
		SiResource.WHEAT:
			_wheat(result)
		SiResource.CLAY:
			_clay(result)
		SiResource.ORE:
			_ore(result)
		SiDevelopmentCard.KNIGHT:
			_knight(result)
		SiDevelopmentCard.ROAD_BUILDING:
			_roads(result)
		SiDevelopmentCard.YEAR_OF_PLENTY:
			_plenty(result)
		SiDevelopmentCard.MONOPOLY:
			_coins(result)
		SiDevelopmentCard.VICTORY_POINT:
			_star(result)
		_:
			push_error("IconShapes: unknown icon '%s'" % icon)
	return result


## A polygon moved outward by `distance` along every edge (convex input).
static func grown(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	var centre := Vector2.ZERO
	for point in points:
		centre += point / points.size()
	var result := PackedVector2Array()
	for index in points.size():
		var before := points[(index + points.size() - 1) % points.size()]
		var after := points[(index + 1) % points.size()]
		var outward_before := _outward(before, points[index], centre)
		var outward_after := _outward(points[index], after, centre)
		result.append(points[index] + (outward_before + outward_after) * distance / (1.0 + outward_before.dot(outward_after)))
	return result


static func _outward(from: Vector2, to: Vector2, centre: Vector2) -> Vector2:
	var normal := (to - from).orthogonal().normalized()
	return normal if normal.dot(centre - from) < 0.0 else -normal


static func _add(result: Array[Dictionary], points: PackedVector2Array, fill: Color, ink := true, group := -1) -> void:
	result.append({"points": points, "fill": fill, "ink": ink, "group": group})


static func _rect(position: Vector2, extent: Vector2) -> PackedVector2Array:
	return PackedVector2Array([position, position + Vector2(extent.x, 0.0), position + extent, position + Vector2(0.0, extent.y)])


static func _disc(centre: Vector2, radius: float, squash := 1.0, sides := DISC_SIDES) -> PackedVector2Array:
	var points := PackedVector2Array()
	for side in sides:
		var around := Vector2.from_angle(TAU * side / sides + PI / sides)
		points.append(centre + Vector2(around.x * radius, around.y * radius * squash))
	return points


## A thin quad from `from` to `to`.
static func _stroke(from: Vector2, to: Vector2, width: float) -> PackedVector2Array:
	var across := (to - from).orthogonal().normalized() * width * 0.5
	return PackedVector2Array([from - across, to - across, to + across, from + across])


static func _wood(result: Array[Dictionary]) -> void:
	var bark := Palette.resource_pattern_color(SiResource.WOOD)
	_add(result, _rect(Vector2(-0.44, -0.2), Vector2(0.68, 0.4)), bark)
	_add(result, _disc(Vector2(0.22, 0.0), 0.22), Palette.LOG_CUT)
	_add(result, _disc(Vector2(0.22, 0.0), 0.09), bark, false)


static func _sheep(result: Array[Dictionary]) -> void:
	for spot: Vector2 in [Vector2(-0.2, 0.06), Vector2(0.0, -0.12), Vector2(0.2, 0.06), Vector2(0.0, 0.14)]:
		_add(result, _disc(spot, 0.21), Palette.FLEECE, true, 1)
	_add(result, _disc(Vector2(0.37, -0.1), 0.1), Palette.INK)


static func _wheat(result: Array[Dictionary]) -> void:
	var straw := Palette.resource_pattern_color(SiResource.WHEAT)
	for offset: float in [-0.16, 0.0, 0.16]:
		_add(result, _rect(Vector2(offset - 0.035, -0.2), Vector2(0.07, 0.62)), straw)
		_add(result, PackedVector2Array([
			Vector2(offset, -0.48), Vector2(offset + 0.09, -0.28), Vector2(offset, -0.17), Vector2(offset - 0.09, -0.28),
		]), straw)
	_add(result, _rect(Vector2(-0.25, 0.06), Vector2(0.5, 0.09)), Palette.resource_pattern_color(SiResource.CLAY))


static func _clay(result: Array[Dictionary]) -> void:
	var brick := Palette.resource_pattern_color(SiResource.CLAY)
	_add(result, _rect(Vector2(-0.44, 0.02), Vector2(0.84, 0.3)), brick)
	_add(result, _rect(Vector2(-0.28, -0.32), Vector2(0.84, 0.3)), brick)


static func _ore(result: Array[Dictionary]) -> void:
	var slate := Palette.resource_pattern_color(SiResource.ORE)
	_add(result, PackedVector2Array([
		Vector2(-0.42, 0.3), Vector2(-0.34, -0.12), Vector2(0.0, -0.4), Vector2(0.36, -0.14), Vector2(0.42, 0.3),
	]), slate)
	_add(result, _stroke(Vector2(0.0, -0.36), Vector2(0.06, 0.26), 0.06), slate.lightened(0.45), false)
	_add(result, _stroke(Vector2(-0.32, -0.1), Vector2(0.06, 0.04), 0.06), slate.darkened(0.4), false)


## A shield with a gold cross and a sword behind it.
static func _knight(result: Array[Dictionary]) -> void:
	_add(result, PackedVector2Array([Vector2(-0.04, -0.5), Vector2(0.04, -0.5), Vector2(0.06, 0.32), Vector2(-0.06, 0.32)]), STEEL)
	_add(result, _rect(Vector2(-0.2, 0.3), Vector2(0.4, 0.07)), GOLD_DARK)
	_add(result, PackedVector2Array([Vector2(-0.34, -0.3), Vector2(0.34, -0.3), Vector2(0.34, 0.06), Vector2(0.0, 0.46), Vector2(-0.34, 0.06)]), PLUM)
	_add(result, _rect(Vector2(-0.05, -0.2), Vector2(0.1, 0.5)), GOLD, false)
	_add(result, _rect(Vector2(-0.2, -0.08), Vector2(0.4, 0.1)), GOLD, false)


## A road with a dashed centre line.
static func _roads(result: Array[Dictionary]) -> void:
	_add(result, PackedVector2Array([Vector2(-0.12, -0.44), Vector2(0.12, -0.44), Vector2(0.46, 0.44), Vector2(-0.46, 0.44)]), ROAD)
	for step in 3:
		var along := 0.3 - step * 0.28
		var half := 0.025 + (along + 0.5) * 0.03
		_add(result, _rect(Vector2(-half, along - 0.08), Vector2(half * 2.0, 0.16)), Palette.CREAM, false)


## A cornucopia spilling three fruits.
static func _plenty(result: Array[Dictionary]) -> void:
	_add(result, PackedVector2Array([Vector2(-0.46, 0.4), Vector2(-0.02, -0.26), Vector2(0.44, 0.12), Vector2(0.1, 0.42)]), Color("#B5773A"))
	_add(result, _disc(Vector2(0.2, -0.26), 0.15), Color("#C23A2E"))
	_add(result, _disc(Vector2(-0.12, -0.36), 0.14), Color("#5E9A3C"))
	_add(result, _disc(Vector2(0.34, -0.02), 0.13), GOLD)


## A stack of three coins.
static func _coins(result: Array[Dictionary]) -> void:
	for step in 3:
		var top := 0.26 - step * 0.2
		_add(result, _rect(Vector2(-0.36, top), Vector2(0.72, 0.1)), GOLD_DARK)
		_add(result, _disc(Vector2(0.0, top + 0.1), 0.36, 0.4, 8), GOLD_DARK)
		_add(result, _disc(Vector2(0.0, top), 0.36, 0.4, 8), GOLD)


static func _star(result: Array[Dictionary]) -> void:
	var tips: Array[Vector2] = []
	var notches: Array[Vector2] = []
	for point in 5:
		tips.append(Vector2.from_angle(-PI * 0.5 + TAU * point / 5.0) * 0.5)
		notches.append(Vector2.from_angle(-PI * 0.5 + TAU * (point + 0.5) / 5.0) * 0.22)
	_add(result, PackedVector2Array(notches), GOLD, true, 1)
	for point in 5:
		_add(result, PackedVector2Array([notches[(point + 4) % 5], tips[point], notches[point]]), GOLD, true, 1)
