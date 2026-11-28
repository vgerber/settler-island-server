class_name FlatIconArt
extends RefCounted
## Printed icons for card and flag faces: the `IconShapes` polygons as flat sheets of vertex colour, like ink on stock.
## Draws on the plane y = `lift` of `transform` (x right, z down on the icon); every layer sits `LAYER_STEP` above
## the one before, so overlaps resolve without z-fighting.

const LAYER_STEP := 0.0006
## Outline thickness as a share of the icon size.
const INK_SHARE := 0.045


## `centre` is (x, z) in the plane of `transform`; `size` is the edge of the icon's unit box.
static func add(builder: ClayBuilder, icon: String, transform: Transform3D, centre: Vector2, size: float, lift: float) -> void:
	var layers := IconShapes.layers(icon)
	var height := lift
	var index := 0
	while index < layers.size():
		var last := index
		var group: int = layers[index]["group"]
		while group >= 0 and last + 1 < layers.size() and layers[last + 1]["group"] == group:
			last += 1
		height += LAYER_STEP
		for member in range(index, last + 1):
			if layers[member]["ink"]:
				_sheet(builder, IconShapes.grown(layers[member]["points"], INK_SHARE), transform, centre, size, height, Palette.INK)
		height += LAYER_STEP
		for member in range(index, last + 1):
			_sheet(builder, layers[member]["points"], transform, centre, size, height, layers[member]["fill"])
		index = last + 1


static func _sheet(
	builder: ClayBuilder, outline: PackedVector2Array, transform: Transform3D, centre: Vector2, size: float, height: float, color: Color
) -> void:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	for index in range(1, outline.size() - 1):
		for corner in [outline[0], outline[index], outline[index + 1]]:
			points.append(transform * Vector3(centre.x + corner.x * size, height, centre.y + corner.y * size))
		colors.append(color)
	builder.add_facets(points, colors)
