extends Node
## Automated test for inline parameter smoothing and node graph decluttering.
##
## Tests:
##   1. Per-parameter smoothing setters, getters, and OneEuro filter initialization on ModelOutput.
##   2. UI synchronization between ParameterRow smoothing controls and ModelOutput.
##   3. Bidirectional editing through ParameterRow spinbox events.
##   4. Serialization and deserialization round-trip of inline smoothing settings.
##   5. Frame-by-frame smoothing convergence across multiple frames.
##   6. Standalone smoothing node remains spawnable for custom workflows.

const ParameterRow = preload("res://lib/blueprints/ui/parameter_row.gd")
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
	var mock_model := MockModel.new()
	add_child(mock_model)

	var graph: Blueprint = BlueprintTemplate.instantiate()
	add_child(graph)

	var output_node = graph.spawn_action(&"model_output", mock_model)
	if output_node == null:
		_fail("spawn_action model_output failed")
		return

	await get_tree().process_frame

	# 1. Test inline smoothing configuration on ModelOutput
	output_node.set_smoothing(&"ParamA", 0.5)
	if not is_equal_approx(output_node.get_smoothing(&"ParamA"), 0.5):
		_fail("get_smoothing did not return 0.5")
		return

	# 2. Test ParameterRow UI synchronization
	var row_a: ParameterRow = output_node.get_parameter_list().get_row("ParamA")
	if row_a == null:
		_fail("ParameterRow ParamA not found")
		return
	if not is_equal_approx(row_a.get_smoothing_value(), 0.5):
		_fail("row_a.get_smoothing_value did not sync to 0.5")
		return
	if not is_equal_approx(row_a.smoothing_value.value, 50.0):
		_fail("row_a.smoothing_value.value did not sync to 50.0")
		return

	# 3. Test UI edit propagates back to ModelOutput
	row_a.smoothing_value.value = 75.0
	if not is_equal_approx(output_node.get_smoothing(&"ParamA"), 0.75):
		_fail("editing row_a did not update output_node smoothing to 0.75")
		return

	# 4. Test Serialization and Deserialization roundtrip
	var serialized: Dictionary = output_node.serialize()
	if not serialized.has("smoothing"):
		_fail("serialized output_node missing 'smoothing' dictionary")
		return
	if not is_equal_approx(float(serialized["smoothing"].get("ParamA", 0.0)), 0.75):
		_fail("serialized smoothing for ParamA was not 0.75")
		return

	# Reset and deserialize
	output_node.set_smoothing(&"ParamA", 0.0)
	if is_equal_approx(output_node.get_smoothing(&"ParamA"), 0.75):
		_fail("set_smoothing to 0.0 failed to reset")
		return
	output_node.deserialize(serialized)
	if not is_equal_approx(output_node.get_smoothing(&"ParamA"), 0.75):
		_fail("deserialization failed to restore smoothing to 0.75")
		return
	if not is_equal_approx(row_a.get_smoothing_value(), 0.75):
		_fail("deserialization failed to update row_a UI")
		return

	# 5. Test Frame-by-frame smoothing convergence
	var slot_idx: int = row_a.get_index()
	# Send normalized signal 1.0 (corresponds to ParamA max = 1.0)
	output_node.update_value(slot_idx, 1.0)
	output_node._process(0.016)

	var v1: float = float(mock_model.values["ParamA"])
	if v1 <= 0.0 or v1 >= 1.0:
		_fail("smoothing should produce intermediate value between 0.0 and 1.0, got %f" % v1)
		return

	# Multiple frames should converge closer to target
	for i in range(30):
		output_node._process(0.016)
	var v_final: float = float(mock_model.values["ParamA"])
	if v_final <= v1:
		_fail("smoothing filter failed to advance towards target: v1=%f, v_final=%f" % [v1, v_final])
		return

	# 6. Test standalone smoothing node is still available
	var standalone_smoothing = graph.spawn_action(&"smoothing", mock_model)
	if standalone_smoothing == null:
		_fail("standalone smoothing action should remain spawnable")
		return
	standalone_smoothing.smoothing = 0.5
	standalone_smoothing.update_value(0, 10.0)
	standalone_smoothing._process(0.016)
	var filtered = standalone_smoothing.get_value(0)
	if filtered <= 0.0:
		_fail("standalone smoothing node failed to compute filtered value")
		return

	print("parameter_smoothing_ok")
	get_tree().quit(0)

func _fail(msg: String) -> void:
	printerr("FAIL %s" % msg)
	get_tree().quit(1)
