extends SceneTree
func _initialize():
	_run.call_deferred()
func _run():
	await process_frame
	await process_frame
	var mm = root.get_node("/root/ModelManager")
	mm.refresh_models()
	var id = ""
	for meta in mm.model_cache.values():
		if meta.format == "vrm" and String(meta.id).begins_with("AvatarSample"):
			id = meta.id
			break
	if id.is_empty():
		printerr("FAIL: no AvatarSample VRM in cache")
		quit(1)
		return
	print("loading ", id)
	var model = mm.make_model(id)
	if model == null:
		printerr("FAIL: make_model returned null")
		quit(1)
		return
	model.position = Vector2(640, 360)
	model.scale = Vector2(0.8, 0.8)
	root.add_child(model)
	await model.loaded
	if model.is_queued_for_deletion() or not model.is_initialized():
		printerr("FAIL: VRM failed to load")
		quit(1)
		return
	print("OK: VRM model loaded")
	print("OK: hit size=", model.size, " centered=", model.centered)
	# Simulate drag/zoom sync
	model.global_position = Vector2(700, 400)
	model.scale = Vector2(1.1, 1.1)
	await process_frame
	if model.model != null and model.model.position.is_finite():
		print("OK: 3D model synced to ", model.model.position, " scale=", model.model.scale)
	else:
		printerr("FAIL: 3D model transform not finite")
		quit(1)
		return
	var lights = model.vp.find_children("*", "DirectionalLight3D")
	print("OK: lights in VRM viewport=", lights.size())
	if lights.is_empty():
		printerr("FAIL: no directional lights")
		quit(1)
		return
	quit(0)
