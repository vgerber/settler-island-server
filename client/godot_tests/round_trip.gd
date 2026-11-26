extends SceneTree
## Parses every fixture message through the generated classes and checks `to_dict` gives it back.
## Usage: godot --headless --path <project> -s round_trip.gd -- <fixtures.json>
## Fixtures: {"client": [ClientMessage, ...], "server": [ServerMessage, ...]} as the server writes them.


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
	for input in fixtures["client"]:
		var message := SiClientMessage.from_dict(input)
		failures += _check(input, null if message == null else message.to_dict())
	for input in fixtures["server"]:
		var message := SiServerMessage.from_dict(input)
		failures += _check(input, null if message == null else message.to_dict())
	var total: int = fixtures["client"].size() + fixtures["server"].size()
	if failures > 0:
		_finish(1, "ROUND_TRIP_FAILED %d of %d" % [failures, total])
		return
	_finish(0, "ROUND_TRIP_OK %d" % total)


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
