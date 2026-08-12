extends "./blueprint_loader.gd"

## Default OSF/VTS → VRM expression / head bindings.
const DEFAULT_BINDINGS = {
	"FaceAngleX": [
		{"name": "headRotX", "smoothing": 15},
	],
	"FaceAngleY": [
		{"name": "headRotY", "smoothing": 15},
	],
	"FaceAngleZ": [
		{"name": "headRotZ", "smoothing": 20},
	],
	"MouthOpen": [
		{"name": "aa", "smoothing": 10},
	],
	"MouthSmile": [
		{"name": "happy", "smoothing": 12},
	],
	# EyeOpen is open-amount; blink presets are closed-amount → invert via arithmetic.
	"EyeOpenLeft": [
		{"name": "blinkLeft", "smoothing": 8, "invert": true},
	],
	"EyeOpenRight": [
		{"name": "blinkRight", "smoothing": 8, "invert": true},
	],
	"EyeLeftX": [
		{"name": "lookLeft", "smoothing": 8, "when_positive": true},
		{"name": "lookRight", "smoothing": 8, "when_negative": true},
	],
	"EyeRightX": [
		{"name": "lookLeft", "smoothing": 8, "when_positive": true},
		{"name": "lookRight", "smoothing": 8, "when_negative": true},
	],
	"EyeLeftY": [
		{"name": "lookUp", "smoothing": 8, "when_positive": true},
		{"name": "lookDown", "smoothing": 8, "when_negative": true},
	],
	"EyeRightY": [
		{"name": "lookUp", "smoothing": 8, "when_positive": true},
		{"name": "lookDown", "smoothing": 8, "when_negative": true},
	],
}

const PAD = 30

func id() -> StringName:
	return "vrm"

func load_graph(model: VtModel) -> Array[Blueprint]:
	if model.modelmeta == null or model.modelmeta.format != "vrm":
		return []

	var model_params := model.get_parameters()
	if model_params.is_empty():
		return []

	_ensure_camera_registry()

	var graph: Blueprint = BlueprintTemplate.instantiate()
	graph.name = "VRM Standard"
	add_child(graph)

	var camera_tracker: VtAction = graph.spawn_action(&"tracking_input", model)
	var model_output: VtAction = graph.spawn_action(&"model_output", model)

	if camera_tracker == null or model_output == null:
		push_error("vrm defaults: failed to spawn required blueprint actions")
		remove_child(graph)
		graph.free()
		return []

	camera_tracker.name = "CameraTracker"
	camera_tracker.kind = &"Camera"

	var x := camera_tracker.size.x + PAD
	var y := 0.0
	var column_width := 0.0
	var connected := 0

	for input_parameter in DEFAULT_BINDINGS:
		for output_parameter in DEFAULT_BINDINGS[input_parameter]:
			var out_name := String(output_parameter.name)
			if not _model_has_parameter(model_params, out_name):
				continue
			# Skip look axes that need signed split for v1 — only wire if no when_* flags
			# or wire simple full-range when the model has the look param (best-effort).
			if output_parameter.get("when_positive", false) or output_parameter.get("when_negative", false):
				# Look dirs need signed split; map full eye axis through invert-less path later.
				# For MVP, skip signed look splits (head/mouth/blink are the priority).
				continue

			var input_slot: int = camera_tracker.get_output_port_by_name(StringName(input_parameter))
			if input_slot < 0:
				continue
			var output_slot: int = model_output.get_input_port_by_name(StringName(out_name))
			if output_slot < 0:
				continue

			var input: VtAction = camera_tracker
			var _x := x

			if bool(output_parameter.get("invert", false)):
				var inv: VtAction = graph.spawn_action(&"arithmetic", model)
				if inv == null:
					continue
				inv.deserialize({"operator": "Subtract", "a": 1.0, "b": null})
				graph._on_connection_request(
					input.name, input_slot,
					inv.name, inv.get_input_port_by_name("b")
				)
				inv.position_offset = Vector2(_x, y)
				_x += inv.size.x + PAD
				input = inv
				input_slot = inv.get_output_port_by_name("value")

			if float(output_parameter.get("smoothing", 0.0)) > 0.0:
				var smoothing: VtAction = graph.spawn_action(&"smoothing", model)
				if smoothing == null:
					continue
				smoothing.smoothing = float(output_parameter.get("smoothing", 0.0)) / 100.0
				graph._on_connection_request(
					input.name, input_slot,
					smoothing.name, smoothing.get_input_port_by_name("value")
				)
				smoothing.position_offset = Vector2(_x, y)
				_x += smoothing.size.x + PAD
				input = smoothing
				input_slot = smoothing.get_output_port_by_name("value")

			graph._on_connection_request(
				input.name, input_slot,
				model_output.name, output_slot
			)
			connected += 1
			y += PAD * 2
			column_width = maxf(column_width, _x)

	if connected == 0:
		push_warning(
			"vrm defaults: no parameter bindings connected for %s"
			% model.modelmeta.name
		)
	else:
		print_debug("vrm defaults: connected %d bindings for %s" % [connected, model.modelmeta.name])

	x += column_width
	model_output.position_offset = Vector2(x, 0)
	camera_tracker.position_offset = Vector2(0, 0)

	await get_tree().process_frame

	remove_child(graph)
	return [graph]

func _model_has_parameter(model_params: Dictionary, param_name: String) -> bool:
	return model_params.has(param_name) or model_params.has(StringName(param_name))

func _ensure_camera_registry() -> void:
	if not Registry.parameters_in_group("Camera").is_empty():
		return
	Registry.add_parameter("FaceAngleX", Vector2(-30, 30))
	Registry.add_parameter("FaceAngleY", Vector2(-30, 30))
	Registry.add_parameter("FaceAngleZ", Vector2(-30, 30))
	Registry.add_parameter("MouthSmile", Vector2(0, 1))
	Registry.add_parameter("MouthOpen", Vector2(0, 1))
	Registry.add_parameter("EyeOpenLeft", Vector2(0, 1), 1)
	Registry.add_parameter("EyeOpenRight", Vector2(0, 1), 1)
	Registry.add_parameter("EyeLeftX", Vector2(-1, 1))
	Registry.add_parameter("EyeLeftY", Vector2(-1, 1))
	Registry.add_parameter("EyeRightX", Vector2(-1, 1))
	Registry.add_parameter("EyeRightY", Vector2(-1, 1))
