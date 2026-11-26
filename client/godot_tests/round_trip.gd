extends SceneTree
## Parses every fixture message through the generated classes and checks `to_dict` gives it back.
## Usage: godot --headless --path <project> -s round_trip.gd -- <fixtures.json>
## Fixtures: {"client", "server", "actions", "events", "errors"}, lists of values as the server writes them.
## Every generated variant class must have a sample, so a new Rust variant fails until the fixtures have one.

const KINDS := {
	"client": "SiClientMessage",
	"server": "SiServerMessage",
	"actions": "SiAction",
	"events": "SiEvent",
	"errors": "SiErrorCode",
}


func _init() -> void:
	var path := SiTestSupport.argument(0)
	if path.is_empty():
		_finish(1, "ROUND_TRIP_FAILED missing fixtures path")
		return
	var fixtures: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not fixtures is Dictionary:
		_finish(1, "ROUND_TRIP_FAILED fixtures are not a JSON object")
		return
	var failures := 0
	var total := 0
	for kind: String in KINDS:
		var samples: Array = fixtures.get(kind, [])
		for variant in SiTestSupport.missing_variants(KINDS[kind], samples):
			print("NO SAMPLE %s%s" % [KINDS[kind], variant])
			failures += 1
		for input in samples:
			failures += _check(input, _decode(kind, input))
		total += samples.size()
	if failures > 0:
		_finish(1, "ROUND_TRIP_FAILED %d of %d" % [failures, total])
		return
	_finish(0, "ROUND_TRIP_OK %d" % total)


## The value `input` decodes to and encodes back to, or null when the class does not know it.
func _decode(kind: String, input: Variant) -> Variant:
	var decoded: Variant = null
	match kind:
		"client":
			decoded = SiClientMessage.from_dict(input)
		"server":
			decoded = SiServerMessage.from_dict(input)
		"actions":
			decoded = SiAction.from_dict(input)
		"events":
			decoded = SiEvent.from_dict(input)
		"errors":
			decoded = SiErrorCode.from_dict(input)
	return null if decoded == null else decoded.to_dict()


func _finish(code: int, line: String) -> void:
	SiTestSupport.finish(self, code, line)


func _check(input: Variant, output: Variant) -> int:
	if _same(input, output):
		return 0
	print("MISMATCH\n  input:  %s\n  output: %s" % [JSON.stringify(input), JSON.stringify(output)])
	return 1


## Deep equality where a null entry equals a missing key (serde accepts both) and numbers parsed
## as floats equal the ints the classes write; the output must hold ints, which serde requires.
static func _same(expected: Variant, actual: Variant) -> bool:
	if expected is Dictionary and actual is Dictionary:
		return _same_dictionary(expected, actual)
	if expected is Array and actual is Array:
		return _same_array(expected, actual)
	if typeof(expected) == TYPE_FLOAT:
		return typeof(actual) == TYPE_INT and float(actual) == expected
	return typeof(expected) == typeof(actual) and expected == actual


static func _same_dictionary(expected: Dictionary, actual: Dictionary) -> bool:
	var keys := {}
	for key in expected:
		if expected[key] != null:
			keys[key] = true
	for key in actual:
		if actual[key] != null:
			keys[key] = true
	for key in keys:
		if not _same(expected.get(key), actual.get(key)):
			return false
	return true


static func _same_array(expected: Array, actual: Array) -> bool:
	if expected.size() != actual.size():
		return false
	for index in expected.size():
		if not _same(expected[index], actual[index]):
			return false
	return true
