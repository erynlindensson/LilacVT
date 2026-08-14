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
		printerr("FAIL: no AvatarSample VRM")
		quit(1)
		return

	var model = mm.make_model(id)
	model.position = Vector2(640, 360)
	root.add_child(model)
	await model.loaded
	if not model.is_initialized():
		printerr("FAIL: model not initialized")
		quit(1)
		return

	var params = model.get_parameters()
	print("OK: param count=", params.size())
	for need in ["headRotX", "headRotY", "headRotZ"]:
		if not params.has(need):
			printerr("FAIL: missing ", need)
			quit(1)
			return
	print("OK: headRot params present")
	print("OK: aa=", params.has("aa"), " blinkLeft=", params.has("blinkLeft"))

	var vis = model.get("modifiers/parameters/headRotX/visible")
	if vis != true:
		printerr("FAIL: visible modifier not true got=", vis)
		quit(1)
		return
	model.set("parameters/headRotX", 15.0)
	var got = float(model.get("parameters/headRotX"))
	if abs(got - 15.0) > 0.01:
		printerr("FAIL: _set/_get headRotX got=", got)
		quit(1)
		return
	print("OK: parameters/ bridge works")

	var empty: Dictionary[String, float] = {}
	model.apply_parameters(empty)
	got = float(model.get("parameters/headRotX"))
	if abs(got - 15.0) > 0.01:
		printerr("FAIL: empty apply wiped headRotX got=", got)
		quit(1)
		return
	print("OK: empty apply_parameters preserves values")

	if params.has("aa"):
		model.set("parameters/aa", 0.75)
		print("OK: set aa=", model.get("parameters/aa"))

	var loader = load("res://lib/blueprints/loaders/vrm_defaults.gd").new()
	root.add_child(loader)
	var graphs = await loader.load_graph(model)
	if graphs.is_empty():
		printerr("FAIL: vrm_defaults returned no graphs")
		quit(1)
		return
	print("OK: vrm_defaults graph=", graphs[0].name, " nodes=", graphs[0].get_child_count())
	loader.queue_free()

	var l2d = load("res://lib/blueprints/loaders/l2d_defaults.gd").new()
	root.add_child(l2d)
	var l2d_graphs = await l2d.load_graph(model)
	if not l2d_graphs.is_empty():
		printerr("FAIL: l2d_defaults should skip VRM")
		quit(1)
		return
	print("OK: l2d_defaults skips VRM")
	l2d.queue_free()
	quit(0)
