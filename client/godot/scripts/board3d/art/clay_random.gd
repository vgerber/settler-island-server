class_name ClayRandom
extends RefCounted
## Deterministic randomness for props: a generator seeded from a hash of the tile coordinates, so the same
## tile always grows the same trees (screenshots compare, and nothing flickers when the board rebuilds).


static func for_tile(q: int, r: int, salt := 0) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = mix(mix(mix(0x9E3779B1, q), r), salt)
	return generator


## One round of an integer hash (xorshift-multiply); the state is kept to 62 bits so it never overflows.
static func mix(state: int, value: int) -> int:
	var mixed := (state ^ (value + 0x7F4A7C15)) & 0x3FFFFFFFFFFFFFFF
	mixed = (mixed ^ (mixed >> 15)) * 0x2C1B3C6D & 0x3FFFFFFFFFFFFFFF
	mixed = (mixed ^ (mixed >> 12)) * 0x297A2D39 & 0x3FFFFFFFFFFFFFFF
	return mixed ^ (mixed >> 15)
