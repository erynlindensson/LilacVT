extends Node
## Interactive probe for global (unfocused) key detection.
##
## Prints a line whenever one of the sampled keys changes state. Run it, then click
## into ANOTHER window and press keys: lines should keep appearing. That unfocused
## case is the whole point of the extension, and is the part no automated test here
## can cover.
##
##   godot4-ayagami --path . res://scripts/probe_global_input.tscn
##
## Each sampled key deliberately exercises a different branch of keymap.rs.

const RUN_SECONDS := 90.0

var _gi: Node
var _state := {}
var _elapsed := 0.0

# label -> why it is here
const PROBES := {
	"A": "letter (Godot reports uppercase, X maps the lowercase keysym)",
	"5": "digit (passes through as Latin-1)",
	"Space": "printable ASCII",
	"F12": "function key (mapped by sequence)",
	"Kp 7": "keypad (mapped by sequence)",
	"Shift": "modifier (must match either side)",
	"Ctrl": "modifier (must match either side)",
}

func _ready() -> void:
	_gi = get_node_or_null("/root/GlobalInput")
	if _gi == null:
		printerr("FAIL GlobalInput autoload missing")
		get_tree().quit(1)
		return

	print("backend available: %s" % _gi.is_available())
	if not _gi.is_available():
		print("No X11 backend. Under pure Wayland this is expected and hotkeys are inert.")
	print("")
	print("Sampling for %d seconds. Click into another window and press these:" % int(RUN_SECONDS))
	for label in PROBES:
		print("  %-6s  %s" % [label, PROBES[label]])
	print("")

	for label in PROBES:
		_state[label] = false

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= RUN_SECONDS:
		print("\ndone")
		get_tree().quit(0)
		return

	for label in PROBES:
		var code := OS.find_keycode_from_string(label)
		if code == KEY_NONE:
			continue
		var now: bool = _gi.is_key_pressed(code)
		if now != _state[label]:
			_state[label] = now
			print("%7.2fs  %-6s %s" % [_elapsed, label, "DOWN" if now else "up"])
