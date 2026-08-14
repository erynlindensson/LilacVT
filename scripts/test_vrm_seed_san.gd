extends SceneTree

## Headless check that VRM 1.0 runtime import creates AnimationPlayer.
## Run: godot4-ayagami --headless --path /home/eryn/open-vt -s res://scripts/test_vrm_seed_san.gd

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	await process_frame
	var mm = root.get_node_or_null("/root/ModelManager")
	if mm == null:
		printerr("FAIL: ModelManager missing")
		quit(1)
		return
	mm.refresh_models()
	var id := ""
	for meta in mm.model_cache.values():
		if meta.format == &"vrm" and String(meta.id).contains("Seed-san"):
			id = meta.id
			break
	if id.is_empty():
		print("SKIP: Seed-san.vrm not installed under user://VrmModels")
		quit(0)
		return
	print("loading ", id)
	var model = mm.make_model(id)
	if model == null:
		printerr("FAIL: make_model returned null")
		quit(1)
		return
	root.add_child(model)
	await model.loaded
	if model.is_queued_for_deletion() or not model.is_initialized():
		printerr("FAIL: Seed-san failed to load")
		quit(1)
		return
	var anim: AnimationPlayer = model.get_idle_animation_player()
	if anim == null:
		printerr("FAIL: no AnimationPlayer after VRM 1.0 import")
		quit(1)
		return
	var skeleton: Skeleton3D = model._get_skeleton()
	if skeleton == null:
		printerr("FAIL: no skeleton after VRM 1.0 import")
		quit(1)
		return
	print("OK: Seed-san loaded anim=", anim.name, " clips=", anim.get_animation_list().size(), " skeleton=", skeleton.name)
	if not anim.has_animation("happy") or anim.get_animation("happy").get_track_count() < 1:
		printerr("FAIL: happy clip has no morph tracks")
		quit(1)
		return
	var meshes: Array = model.get_meshes()
	var names := PackedStringArray()
	for mesh_node in meshes:
		names.append(String(mesh_node.name))
	if not "robo_arm" in names or not "wear" in names:
		printerr("FAIL: expected wear/robo_arm meshes, got ", names)
		quit(1)
		return
	print("OK: meshes=", names)
	quit(0)
