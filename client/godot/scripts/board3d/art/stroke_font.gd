class_name StrokeFont
extends RefCounted
## Digits as centre lines in a 0.6 x 1 glyph box (y up), drawn by `ClayBuilder` as round-capped ribbons. Pressing
## numbers into clay needs no font file this way, and the shapes are our own.

const GLYPH_WIDTH := 0.6
const GLYPH_GAP := 0.2
const COLON_ADVANCE := 0.15
## Round joints between ribbons are small polygons.
const JOINT_SEGMENTS := 4

const _STROKES := {
	"0": [[[0.3, 1.0], [0.52, 0.9], [0.6, 0.5], [0.52, 0.1], [0.3, 0.0], [0.08, 0.1], [0.0, 0.5], [0.08, 0.9], [0.3, 1.0]]],
	"1": [[[0.12, 0.8], [0.32, 1.0], [0.32, 0.0]]],
	"2": [[[0.02, 0.78], [0.12, 0.94], [0.3, 1.0], [0.5, 0.94], [0.58, 0.76], [0.48, 0.56], [0.0, 0.0], [0.6, 0.0]]],
	"3": [[[0.02, 0.88], [0.3, 1.0], [0.55, 0.88], [0.55, 0.68], [0.26, 0.54], [0.56, 0.4], [0.6, 0.16], [0.3, 0.0], [0.0, 0.1]]],
	"4": [[[0.46, 0.0], [0.46, 1.0], [0.0, 0.3], [0.62, 0.3]]],
	"5": [[[0.56, 1.0], [0.06, 1.0], [0.02, 0.56], [0.3, 0.62], [0.56, 0.5], [0.6, 0.2], [0.3, 0.0], [0.0, 0.08]]],
	"6": [[[0.54, 0.94], [0.3, 1.0], [0.06, 0.76], [0.0, 0.3], [0.14, 0.05], [0.34, 0.0], [0.58, 0.16], [0.58, 0.4], [0.34, 0.56], [0.1, 0.42]]],
	"7": [[[0.0, 1.0], [0.6, 1.0], [0.2, 0.0]]],
	"8": [
		[[0.3, 1.0], [0.53, 0.9], [0.53, 0.68], [0.3, 0.55], [0.07, 0.68], [0.07, 0.9], [0.3, 1.0]],
		[[0.3, 0.55], [0.58, 0.4], [0.58, 0.14], [0.3, 0.0], [0.02, 0.14], [0.02, 0.4], [0.3, 0.55]],
	],
	":": [[[0.075, 0.7]], [[0.075, 0.3]]],
	"9": [[[0.06, 0.06], [0.3, 0.0], [0.54, 0.24], [0.6, 0.7], [0.46, 0.95], [0.26, 1.0], [0.02, 0.84], [0.02, 0.6], [0.26, 0.44], [0.5, 0.58]]],
}


## Width of `text` in glyph units (a glyph is `GLYPH_WIDTH` wide, 1 high).
static func text_width(text: String) -> float:
	var width := 0.0
	for character in text:
		width += _advance(character) + GLYPH_GAP
	return maxf(width - GLYPH_GAP, 0.0)


static func _advance(character: String) -> float:
	return COLON_ADVANCE if character == ":" else GLYPH_WIDTH


## Adds `text` to `builder` as ribbons lying in the local xz plane of `transform`, centred on its origin, glyph
## x along +x, glyph up along -z (away from a camera that looks toward -z), `height` units tall, strokes
## `stroke_width` thick. Rotate the transform to tilt the text with its surface.
static func add_text(
	builder: ClayBuilder, text: String, transform: Transform3D, height: float, stroke_width: float, color: Color
) -> void:
	var cursor := -text_width(text) * 0.5
	for character in text:
		for stroke: Array in _STROKES[character]:
			_add_stroke(builder, stroke, cursor, transform, height, stroke_width, color)
		cursor += _advance(character) + GLYPH_GAP


static func _add_stroke(
	builder: ClayBuilder, stroke: Array, cursor: float, transform: Transform3D, height: float, stroke_width: float, color: Color
) -> void:
	var points: Array[Vector3] = []
	for point: Array in stroke:
		points.append(Vector3(cursor + point[0], 0.0, 0.5 - point[1]) * height)
	for index in points.size() - 1:
		_add_ribbon(builder, points[index], points[index + 1], transform, stroke_width, color)
	for point in points:
		add_disc(builder, Transform3D(transform.basis, transform * point), stroke_width * 0.5, color, JOINT_SEGMENTS)


static func _add_ribbon(
	builder: ClayBuilder, from: Vector3, to: Vector3, transform: Transform3D, stroke_width: float, color: Color
) -> void:
	var direction := (to - from).normalized()
	var side := Vector3(-direction.z, 0.0, direction.x) * stroke_width * 0.5
	var corners := PackedVector3Array(
		[transform * (from - side), transform * (from + side), transform * (to - side), transform * (to + side)]
	)
	var normal := (transform.basis * Vector3.UP).normalized()
	var normals := PackedVector3Array([normal, normal, normal, normal])
	var colors := PackedColorArray([color, color, color, color])
	builder.add_surface(corners, normals, colors, 2, 2, false)


## Vertices `add_disc` makes per disc (the centre repeats once per segment).
static func disc_vertex_count(segments := 10) -> int:
	return segments * 2


## A flat disc of `radius` in the local xz plane of `transform`, facing local +y (the die's pips, the chip's
## probability dots and the dots of the strokes).
static func add_disc(builder: ClayBuilder, transform: Transform3D, radius: float, color: Color, segments := 10) -> void:
	var points := PackedVector3Array()
	for segment in segments:
		points.append(transform.origin)
	for segment in segments:
		var angle := TAU * segment / segments
		points.append(transform * Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	var normal := (transform.basis * Vector3.UP).normalized()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for point in points:
		normals.append(normal)
		colors.append(color)
	builder.add_surface(points, normals, colors, 2, segments, true)
