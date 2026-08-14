extends SceneTree
## Headless checks for Cubism physics controls on AyagamiPhysicsMutator.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if not ClassDB.class_exists("AyagamiPhysicsMutator"):
		printerr("FAIL: AyagamiPhysicsMutator class missing (rebuild ayagami .so)")
		quit(1)
		return
	var controller: Object = ClassDB.instantiate("AyagamiPhysicsMutator")
	if controller == null:
		printerr("FAIL: could not instantiate AyagamiPhysicsMutator")
		quit(1)
		return
	if not ("strength" in controller):
		printerr("FAIL: strength property missing — .so is stale")
		quit(1)
		return
	controller.strength = 0.4
	if absf(float(controller.strength) - 0.4) > 0.001:
		printerr("FAIL: strength did not stick")
		quit(1)
		return
	if not controller.has_method("set_group_strength") or not controller.has_method("get_group_ids"):
		printerr("FAIL: per-group physics methods missing — .so is stale")
		quit(1)
		return
	controller.call("set_group_strength", "Hair", 0.25)
	if absf(float(controller.call("get_group_strength", "Hair")) - 0.25) > 0.001:
		printerr("FAIL: group strength did not stick")
		quit(1)
		return
	var ids: PackedStringArray = controller.call("get_group_ids")
	if ids.size() != 0:
		printerr("FAIL: empty definition should have no groups")
		quit(1)
		return
	print("l2d_physics_controls_ok")
	quit(0)
