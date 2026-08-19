extends Node
## Smoke test for the GlobalInput extension.
##
## Verifies the class registers, the autoload resolves, and is_key_pressed answers
## for a representative spread of keycodes without erroring. It cannot assert a
## real key press: that needs a human holding a key, or a key-synthesis tool.
##   godot4-ayagami --headless --path . res://scripts/test_global_input.tscn

func _ready() -> void:
	if not ClassDB.class_exists("GlobalInputServer"):
		_fail("GlobalInputServer class not registered by the extension")
		return

	# resolved through the autoload, exactly as hotkey_binding.gd does
	var gi: Node = get_node_or_null("/root/GlobalInput")
	if gi == null:
		_fail("GlobalInput autoload missing")
		return

	for m in ["is_key_pressed", "is_available", "reload_layout"]:
		if not gi.has_method(m):
			_fail("GlobalInput is missing method %s" % m)
			return

	print("backend_available=%s" % gi.is_available())

	# a spread across every mapping branch: ascii, letter, digit, F-key,
	# keypad, modifier, and an unmappable code
	var probes := {
		"A": OS.find_keycode_from_string("A"),
		"5": OS.find_keycode_from_string("5"),
		"Space": OS.find_keycode_from_string("Space"),
		"F12": OS.find_keycode_from_string("F12"),
		"Kp 7": OS.find_keycode_from_string("Kp 7"),
		"Shift": OS.find_keycode_from_string("Shift"),
		"Ctrl": OS.find_keycode_from_string("Ctrl"),
	}
	for label in probes:
		var code: int = probes[label]
		if code == KEY_NONE:
			_fail("Godot could not resolve keycode for %s" % label)
			return
		var pressed = gi.is_key_pressed(code)
		if typeof(pressed) != TYPE_BOOL:
			_fail("is_key_pressed(%s) returned %s, expected bool" % [label, typeof(pressed)])
			return

	# malformed input must degrade to false, never crash
	for bad in [0, -1, 999999999]:
		if gi.is_key_pressed(bad) != false:
			_fail("is_key_pressed(%d) should be false" % bad)
			return

	print("global_input_ok")
	get_tree().quit(0)

func _fail(msg: String) -> void:
	printerr("FAIL %s" % msg)
	get_tree().quit(1)
