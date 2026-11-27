class_name ClayBuilder
extends RefCounted
## Collects low-poly, flat-shaded, vertex-coloured triangle meshes for the clay kit. Every part is built in its
## own unit space and placed with a `Transform3D`; `to_mesh` gives every triangle its own face normal (the
## faceted look), and the vertex colour carries the albedo already multiplied by a baked ambient occlusion (darker toward the part's base and
## creases), which is the Compatibility renderer's stand-in for SSAO (a Forward+ Environment adds real SSAO
## on top, see `ClayMaterials`). Colour values are sRGB; `clay.gdshader` converts them.

const DEFAULT_SEGMENTS := 7
## Round shapes never get more segments than this, whatever the caller asks (low poly).
const MAX_SEGMENTS := 8
## A slab bevel is one chamfer.
const BEVEL_STEPS := 1
## Orients grid normals of slabs: far below, so every upward or outward normal points away from it.
const ORIENT_POINT := Vector3(0.0, -1000.0, 0.0)

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()


func is_empty() -> bool:
	return _indices.is_empty()


## The mesh with one normal per triangle: vertices are not shared, so the facets stay hard.
func to_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _indices.is_empty():
		return mesh
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for triangle in _indices.size() / 3:
		var corners := [_indices[triangle * 3], _indices[triangle * 3 + 1], _indices[triangle * 3 + 2]]
		var edge := _vertices[corners[1]] - _vertices[corners[0]]
		# Godot's front faces are clockwise, so the outward normal is against the cross product.
		var normal := -edge.cross(_vertices[corners[2]] - _vertices[corners[0]]).normalized()
		for corner: int in corners:
			indices.append(vertices.size())
			vertices.append(_vertices[corner])
			normals.append(normal)
			colors.append(_colors[corner])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Vertices with `predicate(position, color)` true; the dice test counts pips with it.
func count_vertices(predicate: Callable) -> int:
	var count := 0
	for index in _vertices.size():
		if predicate.call(_vertices[index], _colors[index]):
			count += 1
	return count


## Two builders with equal arrays are the same mesh (props are deterministic per tile).
func same_geometry_as(other: ClayBuilder) -> bool:
	return _vertices == other._vertices and _colors == other._colors and _indices == other._indices


## A grid of `rows` x `columns` points, row-major. Columns wrap when `wrap` (rings). Triangles are wound to
## agree with the normals, and triangles without area (poles) are dropped.
func add_surface(
	points: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	rows: int,
	columns: int,
	wrap: bool,
) -> void:
	var offset := _vertices.size()
	_vertices.append_array(points)
	_normals.append_array(normals)
	_colors.append_array(colors)
	var column_pairs := columns if wrap else columns - 1
	for row in rows - 1:
		for column in column_pairs:
			var next_column := (column + 1) % columns
			var first := offset + row * columns + column
			var second := offset + row * columns + next_column
			var third := offset + (row + 1) * columns + column
			var fourth := offset + (row + 1) * columns + next_column
			_add_triangle(first, second, third)
			_add_triangle(second, fourth, third)


func _add_triangle(first: int, second: int, third: int) -> void:
	var geometric := (_vertices[second] - _vertices[first]).cross(_vertices[third] - _vertices[first])
	if geometric.length_squared() < 1e-14:
		return
	# Godot's front faces are clockwise, so the cross product points against the outward normal.
	var outward := _normals[first] + _normals[second] + _normals[third]
	if geometric.dot(outward) > 0.0:
		_indices.append_array([first, third, second])
		return
	_indices.append_array([first, second, third])


## Unit sphere, scaled by the transform into an ellipsoid.
func add_sphere(transform: Transform3D, color: Color, ao_floor := 0.7, segments := DEFAULT_SEGMENTS) -> void:
	segments = mini(segments, MAX_SEGMENTS)
	var rings := maxi(segments / 2, 4)
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	for ring in rings + 1:
		var latitude := PI * (float(ring) / rings - 0.5)
		for segment in segments:
			var longitude := TAU * segment / segments
			var direction := Vector3(cos(latitude) * cos(longitude), sin(latitude), cos(latitude) * sin(longitude))
			points.append(transform * direction)
			normals.append(_transform_normal(transform, direction))
	add_surface(points, normals, _occluded_colors(points, color, ao_floor), rings + 1, segments, true)


## Surface of revolution around y. `profile` runs bottom to top as (radius, height); the normals follow the
## profile, so dense points make soft edges.
func add_lathe(
	profile: PackedVector2Array, transform: Transform3D, color: Color, ao_floor := 0.7, segments := DEFAULT_SEGMENTS
) -> void:
	segments = mini(segments, MAX_SEGMENTS)
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	for index in profile.size():
		var tangent := profile[mini(index + 1, profile.size() - 1)] - profile[maxi(index - 1, 0)]
		var profile_normal := Vector2(tangent.y, -tangent.x).normalized()
		for segment in segments:
			var angle := TAU * segment / segments
			var direction := Vector3(cos(angle), 0.0, sin(angle))
			points.append(transform * (direction * profile[index].x + Vector3.UP * profile[index].y))
			var local_normal := direction * profile_normal.x + Vector3.UP * profile_normal.y
			normals.append(_transform_normal(transform, local_normal))
	add_surface(points, normals, _occluded_colors(points, color, ao_floor), profile.size(), segments, true)


## Profile of a capsule standing on y: round ends of `radius`, straight part `half_length` each side of 0.
static func capsule_profile(radius: float, half_length: float, steps := 5) -> PackedVector2Array:
	var profile := PackedVector2Array()
	for step in steps + 1:
		var angle := PI * 0.5 * step / steps
		profile.append(Vector2(sin(angle) * radius, -half_length - cos(angle) * radius))
	for step in steps + 1:
		var angle := PI * 0.5 * step / steps
		profile.append(Vector2(cos(angle) * radius, half_length + sin(angle) * radius))
	return profile


## A box of `half_extents` with sharp edges.
func add_box(transform: Transform3D, half_extents: Vector3, color: Color, ao_floor := 0.7) -> void:
	var faces: Array[PackedVector3Array] = []
	var outward := PackedVector3Array()
	for axis in 3:
		for sign_value in [-1.0, 1.0]:
			var normal := Vector3.ZERO
			normal[axis] = sign_value
			var first := Vector3.ZERO
			first[(axis + 1) % 3] = half_extents[(axis + 1) % 3]
			var second := Vector3.ZERO
			second[(axis + 2) % 3] = half_extents[(axis + 2) % 3]
			var centre := normal * half_extents[axis]
			faces.append(PackedVector3Array([centre - first - second, centre + first - second, centre + first + second, centre - first + second]))
			outward.append(normal)
	_add_faces(transform, faces, outward, color, ao_floor)


## A gable roof: ridge along x at y = `height`, eaves at y = 0 on z = +-`half_depth`, triangular ends. Faces the
## camera with a steep slope when `height` is about 1.4 times `half_depth`.
func add_gable(
	transform: Transform3D, half_length: float, half_depth: float, height: float, color: Color, ao_floor := 0.8
) -> void:
	var faces: Array[PackedVector3Array] = [
		PackedVector3Array([Vector3(-half_length, 0.0, half_depth), Vector3(half_length, 0.0, half_depth), Vector3(half_length, height, 0.0), Vector3(-half_length, height, 0.0)]),
		PackedVector3Array([Vector3(-half_length, 0.0, -half_depth), Vector3(-half_length, height, 0.0), Vector3(half_length, height, 0.0), Vector3(half_length, 0.0, -half_depth)]),
		PackedVector3Array([Vector3(-half_length, 0.0, -half_depth), Vector3(-half_length, 0.0, half_depth), Vector3(-half_length, height, 0.0)]),
		PackedVector3Array([Vector3(half_length, 0.0, -half_depth), Vector3(half_length, height, 0.0), Vector3(half_length, 0.0, half_depth)]),
	]
	var outward := PackedVector3Array(
		[Vector3(0.0, half_depth, height), Vector3(0.0, half_depth, -height), Vector3.LEFT, Vector3.RIGHT]
	)
	_add_faces(transform, faces, outward, color, ao_floor)


## Convex planar faces (corner lists) with their outward normals; the AO spans all of them.
func _add_faces(
	transform: Transform3D, faces: Array[PackedVector3Array], outward: PackedVector3Array, color: Color, ao_floor: float
) -> void:
	var all_points := PackedVector3Array()
	for face in faces:
		for point in face:
			all_points.append(transform * point)
	var colors := _occluded_colors(all_points, color, ao_floor)
	var cursor := 0
	for index in faces.size():
		var offset := _vertices.size()
		var normal := _transform_normal(transform, outward[index])
		for point_index in faces[index].size():
			_vertices.append(all_points[cursor])
			_normals.append(normal)
			_colors.append(colors[cursor])
			cursor += 1
		for corner in faces[index].size() - 2:
			_add_triangle(offset, offset + corner + 1, offset + corner + 2)


## A flat-bottomed slab with a rounded top edge. `outline` is `Callable(angle: float, inset: float) -> float`,
## the distance from the centre to the outline pulled in by `inset`; angles run as in `BoardGeometry`
## (x = cos, z = sin). Colours blend per row: `top_color` on the top, `side_color` down the wall to `base_color`
## at the bottom, with `crease` darkening the bevel. `top_rows` > 1 gives the top more rings (the sea
## displaces them); `drop` lowers the whole slab (a table whose top is y = 0). The vertex alpha is 1 on the top
## and fades to 0 down the bevel.
func add_slab(
	outline: Callable,
	height: float,
	bevel: float,
	top_color: Color,
	side_color: Color,
	base_color: Color,
	crease := 0.8,
	top_rows := 1,
	columns := 48,
	drop := 0.0,
) -> void:
	var rows := _slab_rows(height, bevel, top_rows, top_color, side_color, base_color, crease)
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	for row in rows:
		for column in columns:
			var angle := TAU * column / columns
			var radius: float = row["scale"] * outline.call(angle, row["inset"])
			points.append(Vector3(cos(angle) * radius, row["height"] - drop, sin(angle) * radius))
			colors.append(row["color"])
	var normals := grid_normals(points, rows.size(), columns)
	add_surface(points, normals, colors, rows.size(), columns, true)


func _slab_rows(
	height: float, bevel: float, top_rows: int, top_color: Color, side_color: Color, base_color: Color, crease: float
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for index in top_rows:
		var ring_scale := float(index) / top_rows
		rows.append({"scale": ring_scale, "inset": bevel, "height": height, "color": top_color})
	for step in BEVEL_STEPS + 1:
		var angle := PI * 0.5 * step / BEVEL_STEPS
		var color := _scaled(top_color.lerp(side_color, sin(angle)), lerpf(1.0, crease, sin(angle)))
		color.a = 1.0 - sin(angle)
		rows.append(
			{"scale": 1.0, "inset": bevel * (1.0 - sin(angle)), "height": height - bevel * (1.0 - cos(angle)), "color": color}
		)
	var wall_middle := side_color.lerp(base_color, 0.5)
	wall_middle.a = 0.0
	var wall_bottom := base_color
	wall_bottom.a = 0.0
	rows.append({"scale": 1.0, "inset": 0.0, "height": (height - bevel) * 0.5, "color": wall_middle})
	rows.append({"scale": 1.0, "inset": 0.0, "height": 0.0, "color": wall_bottom})
	return rows


## Normals of a ring grid from central differences (columns wrap); a row without a measurable surface (the
## centre of a fan) points up.
static func grid_normals(points: PackedVector3Array, rows: int, columns: int) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(points.size())
	for row in rows:
		for column in columns:
			var around := points[row * columns + (column + 1) % columns] - points[row * columns + (column - 1 + columns) % columns]
			var down := points[mini(row + 1, rows - 1) * columns + column] - points[maxi(row - 1, 0) * columns + column]
			var normal := around.cross(down)
			if normal.length_squared() < 1e-12:
				normal = Vector3.UP
			normal = normal.normalized()
			if normal.dot(points[row * columns + column] - ORIENT_POINT) < 0.0:
				normal = -normal
			normals[row * columns + column] = normal
	return normals


## Albedo times a darkening that grows toward the part's lowest point: `ao_floor` at the bottom, 1 at the top.
static func _occluded_colors(points: PackedVector3Array, color: Color, ao_floor: float) -> PackedColorArray:
	var lowest := INF
	var highest := -INF
	for point in points:
		lowest = minf(lowest, point.y)
		highest = maxf(highest, point.y)
	var span := maxf(highest - lowest, 1e-5)
	var colors := PackedColorArray()
	for point in points:
		var height_fraction := smoothstep(0.0, 1.0, (point.y - lowest) / span)
		colors.append(_scaled(color, lerpf(ao_floor, 1.0, height_fraction)))
	return colors


static func _scaled(color: Color, factor: float) -> Color:
	return Color(color.r * factor, color.g * factor, color.b * factor, color.a)


static func _transform_normal(transform: Transform3D, normal: Vector3) -> Vector3:
	return (transform.basis.inverse().transposed() * normal).normalized()


## An upright prism: `outline` is a convex polygon of (x, z) points around the origin, extruded from y = 0 to
## `height`. Used for chamfered road beds and boat hulls.
func add_prism(transform: Transform3D, outline: PackedVector2Array, height: float, color: Color, ao_floor := 0.7) -> void:
	var centre := Vector2.ZERO
	for corner in outline:
		centre += corner / outline.size()
	var faces: Array[PackedVector3Array] = []
	var outward := PackedVector3Array()
	var top := PackedVector3Array()
	var bottom := PackedVector3Array()
	for index in outline.size():
		var from := outline[index]
		var to := outline[(index + 1) % outline.size()]
		top.append(Vector3(from.x, height, from.y))
		bottom.append(Vector3(from.x, 0.0, from.y))
		faces.append(PackedVector3Array([Vector3(from.x, 0.0, from.y), Vector3(to.x, 0.0, to.y), Vector3(to.x, height, to.y), Vector3(from.x, height, from.y)]))
		var normal := Vector2(to.y - from.y, from.x - to.x).normalized()
		if normal.dot((from + to) * 0.5 - centre) < 0.0:
			normal = -normal
		outward.append(Vector3(normal.x, 0.0, normal.y))
	faces.append(top)
	outward.append(Vector3.UP)
	faces.append(bottom)
	outward.append(Vector3.DOWN)
	_add_faces(transform, faces, outward, color, ao_floor)


## A four-sided pyramid on y = 0 with its apex at `height` (spires, hip roofs).
func add_pyramid(transform: Transform3D, half_x: float, half_z: float, height: float, color: Color, ao_floor := 0.8) -> void:
	var apex := Vector3(0.0, height, 0.0)
	var corners := [Vector3(-half_x, 0.0, -half_z), Vector3(half_x, 0.0, -half_z), Vector3(half_x, 0.0, half_z), Vector3(-half_x, 0.0, half_z)]
	var faces: Array[PackedVector3Array] = [PackedVector3Array(corners)]
	var outward := PackedVector3Array([Vector3.DOWN])
	for index in 4:
		var from: Vector3 = corners[index]
		var to: Vector3 = corners[(index + 1) % 4]
		faces.append(PackedVector3Array([from, to, apex]))
		var middle := (from + to) * 0.5
		outward.append(Vector3(middle.x * height / maxf(half_x, 1e-4) if absf(middle.x) > 1e-5 else 0.0, maxf(half_x, half_z), middle.z * height / maxf(half_z, 1e-4) if absf(middle.z) > 1e-5 else 0.0))
	_add_faces(transform, faces, outward, color, ao_floor)
