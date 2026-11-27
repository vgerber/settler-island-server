class_name DieArt
extends RefCounted
## One die: an ivory clay cube with round edges and pips on all six faces. Origin at the centre, so the die
## rests at y = `HALF` over the surface. Opposite faces add up to 7. The motion agent lands a die on value `v` by
## using `orientation(v, yaw)`: it maps the local normal `FACE_NORMALS[v]` onto world +y (up) for any yaw, so
## the top face shows `v`. Both tables are the single source; the headless test checks them against the pips.

const HALF := 0.14
const EDGE_ROUNDING := 0.032
const PIP_RADIUS := 0.02
const PIP_SPACING := 0.062
const PIP_LIFT := 0.002
const PIP_SEGMENTS := 10

## Local outward normal of the face that shows each value.
const FACE_NORMALS := {
	1: Vector3.UP,
	6: Vector3.DOWN,
	2: Vector3.BACK,
	5: Vector3.FORWARD,
	3: Vector3.RIGHT,
	4: Vector3.LEFT,
}

## Rotation that turns the face of each value to the top (the die at rest, before the yaw about +y).
const FACE_TO_TOP := {
	1: Basis.IDENTITY,
	6: Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1)),
	2: Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)),
	5: Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)),
	3: Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1)),
	4: Basis(Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)),
}

## Pip grid cells (column, row) in -1..1 for each value.
const PIP_CELLS := {
	1: [[0, 0]],
	2: [[-1, -1], [1, 1]],
	3: [[-1, -1], [0, 0], [1, 1]],
	4: [[-1, -1], [1, -1], [-1, 1], [1, 1]],
	5: [[-1, -1], [1, -1], [0, 0], [-1, 1], [1, 1]],
	6: [[-1, -1], [-1, 0], [-1, 1], [1, -1], [1, 0], [1, 1]],
}

static var _mesh: ArrayMesh = null


## Orientation of a die at rest showing `value` on top, turned by `yaw` radians about +y.
static func orientation(value: int, yaw: float) -> Basis:
	return Basis(Vector3.UP, yaw) * FACE_TO_TOP[value]


static func die() -> ArrayMesh:
	if _mesh == null:
		_mesh = builder().to_mesh()
	return _mesh


static func builder() -> ClayBuilder:
	var body := ClayPalette.mute(Palette.CARD_STOCK)
	var result := ClayBuilder.new()
	result.add_round_box(Transform3D.IDENTITY, Vector3.ONE * HALF, EDGE_ROUNDING, body, 0.72)
	for value: int in FACE_NORMALS:
		_add_pips(result, value)
	return result


## Whether `color` is the colour of a pip (the test counts pip vertices per face).
static func is_pip_color(color: Color) -> bool:
	return color.is_equal_approx(Palette.INK)


static func _add_pips(result: ClayBuilder, value: int) -> void:
	var normal: Vector3 = FACE_NORMALS[value]
	var tangent := Vector3.RIGHT if absf(normal.y) > 0.5 else Vector3.UP
	var bitangent := tangent.cross(normal)
	var basis := Basis(tangent, normal, bitangent)
	for cell: Array in PIP_CELLS[value]:
		var offset: Vector3 = tangent * cell[0] * PIP_SPACING + bitangent * cell[1] * PIP_SPACING
		var origin: Vector3 = normal * (HALF + PIP_LIFT) + offset
		StrokeFont.add_disc(result, Transform3D(basis, origin), PIP_RADIUS, Palette.INK, PIP_SEGMENTS)
