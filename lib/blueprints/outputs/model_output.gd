extends "../vt_action.gd"

const ParameterGrouping = preload("res://lib/blueprints/ui/parameter_grouping.gd")
const ParameterList = preload("res://lib/blueprints/ui/parameter_list.gd")
const ParameterRow = preload("res://lib/blueprints/ui/parameter_row.gd")
const OneEuro = preload("res://lib/utils/oneeuro_filter.gd")

var _list: ParameterList
var bindings = {}
## Per-parameter output range overrides, keyed by parameter name.
## A binding may drive only part of a model parameter's range: MouthSmile is a
## 0..1 signal, but ParamMouthForm spans -1..1 where 0 is neutral, so mapping the
## signal across the full range pins a neutral face to a full frown.
var output_ranges: Dictionary = {}
## Per-parameter smoothing strength, 0..1, keyed by parameter name. Previously one
## smoothing node was spawned per binding, which made 17 of the 22 nodes in a
## generated Live2D graph and emitted a signal per node per frame.
var smoothing: Dictionary = {}
## Live OneEuro filters for the smoothed parameters.
var _filters: Dictionary = {}
## Latest unsmoothed target per smoothed parameter; filters need to keep
## converging on frames where no new value arrives.
var _targets: Dictionary = {}
var binding_display = {}
var _dirty = false
var _refresh = false

func set_model(m: VtModel):
	model = m
	build_slots()

	model.modifier_updated.connect(
		func (field: StringName, _new, _old):
			if field.begins_with("modifiers/parameters"):
				self.refresh_fields()
	)

func build_slots() -> void:
	for child in get_children():
		child.queue_free()

	_list = ParameterList.new(self)
	_list.build_filter_row()

	var parameters := model.get_parameters()
	var grouped := ParameterGrouping.group_parameters(parameters.keys())
	var label_width := 0.0

	for group_name in ParameterGrouping.sorted_group_names(grouped):
		var params: Array = grouped[group_name]
		_list.add_group_header(group_name, params.size())
		for property in params:
			var meta: Dictionary = parameters[property]
			var value_range: Vector2 = meta.range
			var vis: bool = model.get("modifiers/parameters/%s/visible" % property)
			var row := _list.add_parameter_row(
				property,
				value_range,
				meta.default,
				&"input",
				SlotType.NUMERIC,
				vis
			)
			if row == null:
				continue
			label_width = maxf(
				label_width,
				row.get_theme_default_font().get_string_size(property).x
			)
			binding_display[property] = row.current_value
			bindings[property] = meta.default

	_apply_default_collapse.call_deferred()
	_list.finalize_layout(label_width)
	ensure_slot_colors()
	_dirty = true

func _apply_default_collapse() -> void:
	var expanded_groups: Array = []
	if graph != null:
		if "_bindings" in graph:
			for b in graph._bindings:
				if b.to_node == name:
					expanded_groups.append(ParameterGrouping.infer_group(String(b.to_slot)))
		else:
			for conn in graph.get_connection_list():
				if conn.to_node != name:
					continue
				var slot_idx := get_input_slot_by_port(conn.to_port)
				if slot_idx < 0:
					continue
				var param := String(get_slot_name(slot_idx))
				expanded_groups.append(ParameterGrouping.infer_group(param))
	_list.set_default_collapse(expanded_groups)
	_list.finalize_layout()
	ensure_slot_colors()
	if graph != null and graph.has_method(&"sync_visual_connections"):
		graph.sync_visual_connections()

func refresh_fields() -> void:
	_rebuild_port_maps()
	if graph != null and graph.has_method(&"sync_visual_connections"):
		graph.sync_visual_connections()

func _rebuild_port_maps() -> void:
	if _list == null:
		return
	for child in get_children():
		if child is ParameterRow:
			var param: String = child.parameter_name
			var vis: bool = model.get("modifiers/parameters/%s/visible" % param)
			_list.set_row_enabled(param, vis)

func unbind(slot: int, _node: GraphNode) -> void:
	var slot_idx := slot
	if _list != null and slot < _list.port_count:
		var s := get_input_slot_by_port(slot)
		if s != -1:
			slot_idx = s
	if slot_idx < 0 or slot_idx >= get_child_count():
		return
	var param = get_slot_name(slot_idx)
	bindings.erase(param)

func reset_value(slot: int) -> void:
	var slot_idx := slot
	if _list != null and slot < _list.port_count:
		var s := get_input_slot_by_port(slot)
		if s != -1:
			slot_idx = s
	if slot_idx < 0 or slot_idx >= get_child_count():
		return
	var param = get_slot_name(slot_idx)
	var default = model.property_get_revert("parameters/%s" % [param])
	bindings[param] = default
	_dirty = true

func get_input_slot_by_port(port: int) -> int:
	if port < 0 or port >= _list.port_count:
		return -1
	return _list.slots.get(port, -1)

func get_input_port_by_name(slot: StringName) -> int:
	return _list.ports.get(slot.to_lower(), -1)

func get_output_slot_by_port(_port: int) -> int:
	return -1

func get_output_port_by_name(_slot: StringName) -> int:
	return -1

func get_type() -> StringName:
	return &"model_output"

func serialize() -> Dictionary:
	if _list == null:
		return {}
	var data: Dictionary = _list.get_ui_state()
	# ranges must persist: a saved graph is restored by the ovt loader, which does
	# not re-run the defaults loader that declared them
	if not output_ranges.is_empty():
		var ranges := {}
		for param in output_ranges:
			var r: Vector2 = output_ranges[param]
			ranges[param] = [r.x, r.y]
		data["output_ranges"] = ranges
	if not smoothing.is_empty():
		data["smoothing"] = smoothing.duplicate()
	return data

func get_parameter_list() -> BlueprintParameterList:
	return _list

func deserialize(data: Dictionary) -> void:
	for param in data.get("output_ranges", {}):
		var r = data["output_ranges"][param]
		if r is Array and r.size() == 2:
			output_ranges[String(param)] = Vector2(float(r[0]), float(r[1]))
	for param in data.get("smoothing", {}):
		set_smoothing(StringName(param), float(data["smoothing"][param]))
	if _list != null:
		_list.load_ui_state(data)
		_list.finalize_layout()

## Declares the sub-range of a model parameter that a binding should drive.
func set_output_range(parameter: StringName, value_range: Vector2) -> void:
	output_ranges[String(parameter)] = value_range

func get_output_range(parameter: StringName) -> Vector2:
	var key := String(parameter)
	if key in output_ranges:
		return output_ranges[key]
	return model.get("parameters/%s/range" % [key])

## Smoothing strength for a parameter, 0 (off) to 1 (heaviest).
func set_smoothing(parameter: StringName, strength: float) -> void:
	var key := String(parameter)
	strength = clampf(strength, 0.0, 1.0)
	if strength <= 0.0:
		smoothing.erase(key)
		_filters.erase(key)
		_targets.erase(key)
		return
	smoothing[key] = strength
	# same curve the smoothing node used, so generated graphs feel unchanged
	_filters[key] = OneEuro.new(
		lerp(0.06, 0.01, strength),
		lerp(0.004, 0.0002, strength)
	)

func get_smoothing(parameter: StringName) -> float:
	return smoothing.get(String(parameter), 0.0)

func update_value(slot: int, v: Variant) -> void:
	var parameter: StringName = get_slot_name(slot)
	var value_range: Vector2 = get_output_range(parameter)
	var value: float = lerp(value_range.x, value_range.y, v as float)
	var key := String(parameter)
	if key in _filters:
		_targets[key] = value
	else:
		bindings[parameter] = value
		_dirty = true

func _update_model() -> void:
	if not _dirty:
		return

	for p in bindings:
		binding_display[p].value = bindings[p]
		model.set("parameters/%s" % [p], bindings[p])
	_dirty = false
	bindings.clear()

## Smoothed parameters advance every frame, not only when a new value arrives,
## otherwise the filter freezes partway to its target once input goes quiet.
func _apply_smoothing() -> void:
	for key in _targets:
		if key not in _filters:
			continue
		bindings[StringName(key)] = _filters[key].filter(_targets[key])
		_dirty = true

func _process(_delta: float) -> void:
	_apply_smoothing()
	_update_model()
