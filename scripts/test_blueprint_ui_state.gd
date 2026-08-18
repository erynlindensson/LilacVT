extends Node
## Round-trip test for BlueprintParameterList collapse/filter state.
##
## Runs as a scene rather than via --script: parameter_list.gd reaches
## VtAction -> VtModel -> BlueprintManager, and autoloads only exist when a
## scene is run.
##   godot4-ayagami --headless --path . res://scripts/test_blueprint_ui_state.tscn

const ParameterList = preload("res://lib/blueprints/ui/parameter_list.gd")

const GROUPS := {"Eyes": [], "Mouth": [], "Brows": []}

func _ready() -> void:
	var list := ParameterList.new(null)
	list._group_rows = GROUPS.duplicate(true)

	# groups with connections start expanded, everything else collapsed
	list.set_default_collapse(["Eyes"])
	if list.collapsed_groups.get("Eyes", true):
		_fail("Eyes should start expanded")
		return
	if not list.collapsed_groups.get("Mouth", false):
		_fail("Mouth should start collapsed")
		return

	var saved: Dictionary = list.get_ui_state()
	if "Eyes" in saved.collapsed_groups:
		_fail("expanded group was saved as collapsed")
		return
	if "Mouth" not in saved.collapsed_groups:
		_fail("collapsed group missing from saved state")
		return

	var restored := ParameterList.new(null)
	restored._group_rows = GROUPS.duplicate(true)
	restored.load_ui_state(saved)
	if restored.collapsed_groups.get("Eyes", true):
		_fail("Eyes should still be expanded after reload")
		return
	if not restored.collapsed_groups.get("Mouth", false):
		_fail("Mouth should still be collapsed after reload")
		return

	# the deferred default pass runs after deserialize and must not clobber it
	restored.set_default_collapse([])
	if restored.collapsed_groups.get("Eyes", true):
		_fail("set_default_collapse clobbered restored state")
		return

	print("blueprint_ui_state_ok")
	get_tree().quit(0)

func _fail(msg: String) -> void:
	printerr("FAIL %s" % msg)
	get_tree().quit(1)
