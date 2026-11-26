class_name SiTestSupport
extends RefCounted
## Helpers every test script shares: the `--` arguments, a wall-clock deadline and one way to end a run.
## Tests print their marker line on success; the Rust harness also fails on any non-zero exit code.


## The `index`-th argument after `--`, or "" when it is missing.
static func argument(index: int) -> String:
	var arguments := OS.get_cmdline_user_args()
	return arguments[index] if index < arguments.size() else ""


## The point in time `milliseconds` from now, for `expired`.
static func deadline_in(milliseconds: int) -> int:
	return Time.get_ticks_msec() + milliseconds


static func expired(deadline: int) -> bool:
	return Time.get_ticks_msec() > deadline


## Prints `line` (to stderr on failure) and ends the run with `code`.
static func finish(tree: SceneTree, code: int, line: String) -> void:
	if code == 0:
		print(line)
	else:
		printerr(line)
		print(line)
	tree.quit(code)
