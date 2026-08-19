extends Node
## Automated test for parameter minimum, maximum, and current value manual controls.
##
## Tests:
##   1. ParameterRow spinbox editability (min, max, current) and change signals.
##   2. ModelOutput manual min/max range adjustment, current value editing, and serialization.
##   3. TrackingInput manual min/max range adjustment, normalized signal calculation, current value editing, and serialization.
##   4. Inspector parameter panel bidirectional synchronization with ParameterRow.
##   5. Arithmetic node manual spinbox change notifications.

const ParameterRow = preload("res://lib/blueprints/ui/parameter_row.gd")
const ParameterPanel = preload("res://lib/blueprints/ui/inspector_parameter_panel.gd")
const Blueprint = preload("res://lib/blueprints/blueprint.gd")
const BlueprintTemplate = preload("res://lib/blueprints/blueprint.tscn")
const VtModel = preload("res://lib/model/vt_model.gd")

class MockModel extends VtModel:
	var _params := {
		"ParamA": {"range": Vector2(-1.0, 1.0), "default": 0.0},
		"ParamB": {"range": Vector2(0.0, 1.0), "default": 0.5},
	}
	var values := {}

	func _init():
		for p in _params:
			values[p] = _params[p].default

	func is_initialized() -> bool:
		return true

	func get_meshes() -> Array:
		return []

	func _build_model() -> bool:
		return true

	func _load_model() -> void:
		_loading = false

	func get_idle_animation_player() -> AnimationPlayer:
		return null

	func get_animation_player() -> AnimationPlayer:
		return null

	func tracking_updated(_tracking_data: Dictionary, _delta: float) -> void:
		pass

	func get_parameters() -> Dictionary:
		return _params

	func _get(property: StringName) -> Variant:
		var p_str := String(property)
		if p_str.begins_with("parameters/"):
			var rest := p_str.trim_prefix("parameters/")
			var parts := rest.split("/")
			var name := parts[0]
			if name in _params:
				if parts.size() == 1:
					return values.get(name, 0.0)
				elif parts[1] == "range":
					return _params[name].range
				elif parts[1] == "default":
					return _params[name].default
		elif p_str.begins_with("modifiers/parameters/") and p_str.ends_with("/visible"):
			return true
		return null

	func _set(property: StringName, value: Variant) -> bool:
		var p_str := String(property)
		if p_str.begins_with("parameters/"):
			var name := p_str.trim_prefix("parameters/")
			values[name] = value
			return true
		return false

	func _property_get_revert(property: StringName) -> Variant:
		return _get(property)

func _ready() -> void:
	_run()

func _run() -> void:
	# Populate Registry with dummy parameters for headless tests
	Registry.add_parameter(&"HeadPitch", Vector2(-1.0, 1.0), 0.0, "Camera")
	Registry.add_parameter(&"EyeBlinkLeft", Vector2(0.0, 1.0), 0.0, "Camera")

	# 1. Test ParameterRow spinboxes editability and signals
	var row: ParameterRow = ParameterRow.create("TestParam", Vector2(-5.0, 5.0), 1.0)
	add_child(row)

	if not row.min_value.editable:
		_fail("ParameterRow min_value should be editable")
		return
	if not row.max_value.editable:
		_fail("ParameterRow max_value should be editable")
		return
	if not row.current_value.editable:
		_fail("ParameterRow current_value should be editable")
		return

	var min_changed: Array = [false, 0.0]
	var max_changed: Array = [false, 0.0]
	var cur_changed: Array = [false, 0.0]

	row.min_value_changed.connect(func(_p: String, v: float):
		min_changed[0] = true
		min_changed[1] = v
	)
	row.max_value_changed.connect(func(_p: String, v: float):
		max_changed[0] = true
		max_changed[1] = v
	)
	row.current_value_changed.connect(func(_p: String, v: float):
		cur_changed[0] = true
		cur_changed[1] = v
	)

	row.min_value.value = -10.0
	if not min_changed[0] or not is_equal_approx(float(min_changed[1]), -10.0):
		_fail("min_value_changed signal failed to emit on spinbox edit")
		return

	row.max_value.value = 10.0
	if not max_changed[0] or not is_equal_approx(float(max_changed[1]), 10.0):
		_fail("max_value_changed signal failed to emit on spinbox edit")
		return

	row.current_value.value = 2.5
	if not cur_changed[0] or not is_equal_approx(float(cur_changed[1]), 2.5):
		_fail("current_value_changed signal failed to emit on spinbox edit")
		return

	# 2. Test ModelOutput manual min/max/current adjustments
	var mock_model: MockModel = MockModel.new()
	add_child(mock_model)

	var graph: Blueprint = BlueprintTemplate.instantiate()
	add_child(graph)

	var output_node = graph.spawn_action(&"model_output", mock_model)
	if output_node == null:
		_fail("spawn_action model_output failed")
		return

	await get_tree().process_frame

	var row_a: ParameterRow = output_node.get_parameter_list().get_row("ParamA")
	if row_a == null:
		_fail("ParameterRow ParamA not found in output_node")
		return

	# Edit min/max through spinboxes
	row_a.min_value.value = -0.5
	row_a.max_value.value = 0.8
	var r_a: Vector2 = output_node.get_output_range(&"ParamA")
	if not is_equal_approx(r_a.x, -0.5) or not is_equal_approx(r_a.y, 0.8):
		_fail("output_node get_output_range did not update from row spinbox edit, got %s" % r_a)
		return

	# Test current value edit updates model directly
	row_a.current_value.value = 0.35
	output_node._process(0.016)
	if not is_equal_approx(float(mock_model.values["ParamA"]), 0.35):
		_fail("model parameter ParamA did not update from current_value edit, got %f" % float(mock_model.values["ParamA"]))
		return

	# Test serialization of output_ranges
	var saved_output: Dictionary = output_node.serialize()
	if not saved_output.has("output_ranges") or not saved_output["output_ranges"].has("ParamA"):
		_fail("output_node serialize missing output_ranges for ParamA")
		return
	output_node.output_ranges.clear()
	output_node.deserialize(saved_output)
	if not is_equal_approx(output_node.get_output_range(&"ParamA").x, -0.5):
		_fail("deserialized output_ranges failed to restore min bound")
		return
	if not is_equal_approx(row_a.min_value.value, -0.5):
		_fail("deserialized output_ranges failed to update row_a min_value UI")
		return

	# 3. Test TrackingInput manual min/max/current adjustments and normalization
	var tracker_node = graph.spawn_action(&"tracking_input", mock_model)
	if tracker_node == null:
		_fail("spawn_action tracking_input failed")
		return

	await get_tree().process_frame

	var tracker_plist: BlueprintParameterList = tracker_node.get_parameter_list()
	if tracker_plist == null or tracker_plist._rows.is_empty():
		_fail("tracking_input has no parameter rows")
		return

	var first_param: String = tracker_plist._rows.keys()[0]
	var tracker_row: ParameterRow = tracker_plist.get_row(first_param)

	var tracker_updated: Array = [false, -1]
	tracker_node.action_updated.connect(func(slot_idx: int):
		tracker_updated[0] = true
		tracker_updated[1] = slot_idx
	)

	# Edit tracker min/max
	tracker_row.min_value.value = -2.0
	tracker_row.max_value.value = 2.0
	var tracker_range: Vector2 = tracker_node.get_input_range(StringName(first_param))
	if not is_equal_approx(tracker_range.x, -2.0) or not is_equal_approx(tracker_range.y, 2.0):
		_fail("tracking_input get_input_range did not update from row edit, got %s" % tracker_range)
		return

	# Edit tracker current value manually
	tracker_row.current_value.value = 0.0
	if not tracker_updated[0]:
		_fail("tracking_input current_value edit did not emit action_updated")
		return

	var slot_idx: int = tracker_row.get_index()
	var val_vec: Vector4 = tracker_node.get_value(slot_idx)
	# For range [-2, 2], val=0.0 should normalize to 0.5
	if not is_equal_approx(val_vec.w, 0.5):
		_fail("tracking_input normalized value calculation failed with custom range: expected 0.5, got %f" % val_vec.w)
		return

	# Test serialization of input_ranges
	var saved_tracker: Dictionary = tracker_node.serialize()
	if not saved_tracker.has("input_ranges") or not saved_tracker["input_ranges"].has(first_param):
		_fail("tracking_input serialize missing input_ranges")
		return
	tracker_node.input_ranges.clear()
	tracker_node.deserialize(saved_tracker)
	if not is_equal_approx(tracker_node.get_input_range(StringName(first_param)).x, -2.0):
		_fail("deserialized input_ranges failed to restore min bound")
		return

	# 4. Test Inspector parameter panel bidirectional synchronization
	var inspector_panel: VBoxContainer = VBoxContainer.new()
	add_child(inspector_panel)
	ParameterPanel.build(output_node, inspector_panel)

	var inspector_block: VBoxContainer = null
	for c in inspector_panel.get_children():
		if c.has_meta("param_name") and c.get_meta("param_name") == "ParamA":
			inspector_block = c
			break
	if inspector_block == null:
		_fail("inspector panel block for ParamA not found")
		return

	var details_box: HBoxContainer = inspector_block.get_child(1) as HBoxContainer
	var insp_min: SpinBox = details_box.get_child(0) as SpinBox
	var insp_max: SpinBox = details_box.get_child(1) as SpinBox
	var insp_cur: SpinBox = details_box.get_child(2) as SpinBox

	if not insp_min.editable or not insp_max.editable or not insp_cur.editable:
		_fail("inspector parameter spinboxes should be editable")
		return

	# Edit in inspector -> updates node row
	insp_min.value = -0.75
	if not is_equal_approx(row_a.min_value.value, -0.75):
		_fail("editing inspector min spinbox did not update row_a min_value")
		return

	# Edit in node row -> updates inspector
	row_a.max_value.value = 0.95
	if not is_equal_approx(insp_max.value, 0.95):
		_fail("editing row_a max_value did not update inspector max spinbox")
		return

	# 5. Test Arithmetic node manual adjustment signals
	var arith_node = graph.spawn_action(&"arithmetic", mock_model)
	if arith_node == null:
		_fail("spawn_action arithmetic failed")
		return

	var arith_updated: Array = [false]
	arith_node.action_updated.connect(func(_slot: int):
		arith_updated[0] = true
	)

	arith_node.get_node("%InputA").value = 15.0
	if not arith_updated[0]:
		_fail("arithmetic InputA manual edit did not emit action_updated")
		return

	print("parameter_controls_ok")
	get_tree().quit(0)

func _fail(msg: String) -> void:
	printerr("FAIL %s" % msg)
	get_tree().quit(1)
