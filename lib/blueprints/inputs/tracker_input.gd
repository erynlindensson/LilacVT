extends "../vt_action.gd"

const ParameterGrouping = preload("res://lib/blueprints/ui/parameter_grouping.gd")
const ParameterList = preload("res://lib/blueprints/ui/parameter_list.gd")
const ParameterRow = preload("res://lib/blueprints/ui/parameter_row.gd")
const TrackingSystem = preload("res://lib/tracking/tracking_system.gd")

var kind = &"Camera":
	set(g):
		if kind == g and _list != null:
			return
		kind = g
		title = "%s Tracking" % g
		rebuild_slots()

var _list: ParameterList
var input_ranges: Dictionary = {}
var values := {}
var value_displays := {}

func _ready() -> void:
	var tracking: TrackingSystem = get_tree().get_first_node_in_group("system:tracking")
	if tracking:
		tracking.parameters_updated.connect(_on_parameters_updated)
	if _list == null:
		rebuild_slots()
	else:
		ensure_slot_colors()

func rebuild_slots() -> void:
	for child in get_children():
		child.queue_free()

	values.clear()
	value_displays.clear()
	_list = ParameterList.new(self)
	_list.build_filter_row()

	var params: Array = Registry.parameters_in_group(kind)
	var grouped := ParameterGrouping.group_parameters(params)
	var label_width := 0.0

	for group_name in ParameterGrouping.sorted_group_names(grouped):
		var group_params: Array = grouped[group_name]
		_list.add_group_header(group_name, group_params.size())
		for p in group_params:
			var value_range: Vector2 = get_input_range(StringName(p))
			var def_val: float = Registry.get_default(p)
			var row := _list.add_parameter_row(
				p,
				value_range,
				def_val,
				&"output",
				SlotType.VECTOR,
				true
			)
			if row == null:
				continue
			row.min_value_changed.connect(_on_row_min_value_changed)
			row.max_value_changed.connect(_on_row_max_value_changed)
			row.current_value_changed.connect(_on_row_current_value_changed)
			label_width = maxf(
				label_width,
				row.get_theme_default_font().get_string_size(p).x
			)
			values[p] = def_val
			value_displays[p] = row.current_value

	_apply_default_collapse.call_deferred()
	_list.finalize_layout(label_width)
	ensure_slot_colors()

func _apply_default_collapse() -> void:
	var expanded_groups: Array = []
	if graph != null:
		if "_bindings" in graph:
			for b in graph._bindings:
				if b.from_node == name:
					expanded_groups.append(ParameterGrouping.infer_group(String(b.from_slot)))
		else:
			for conn in graph.get_connection_list():
				if conn.from_node != name:
					continue
				var slot_idx := get_output_slot_by_port(conn.from_port)
				if slot_idx < 0:
					continue
				var param := String(get_slot_name(slot_idx))
				expanded_groups.append(ParameterGrouping.infer_group(param))
	_list.set_default_collapse(expanded_groups)
	_list.finalize_layout()
	ensure_slot_colors()
	if graph != null and graph.has_method(&"sync_visual_connections"):
		graph.sync_visual_connections()

func set_input_range(parameter: StringName, value_range: Vector2) -> void:
	var key := String(parameter)
	input_ranges[key] = value_range
	if _list != null:
		var row := _list.get_row(key)
		if row != null:
			row.set_value_range(value_range)

func get_input_range(parameter: StringName) -> Vector2:
	var key := String(parameter)
	if key in input_ranges:
		return input_ranges[key]
	var meta = Registry[parameter]
	if meta != null and meta is Dictionary and meta.has("range"):
		return meta.range
	return Vector2(0.0, 1.0)

func _on_row_min_value_changed(param: String, val: float) -> void:
	var current_range := get_input_range(StringName(param))
	input_ranges[param] = Vector2(val, current_range.y)
	var slot_idx := get_slot_by_name(StringName(param))
	if slot_idx != -1:
		action_updated.emit(slot_idx)

func _on_row_max_value_changed(param: String, val: float) -> void:
	var current_range := get_input_range(StringName(param))
	input_ranges[param] = Vector2(current_range.x, val)
	var slot_idx := get_slot_by_name(StringName(param))
	if slot_idx != -1:
		action_updated.emit(slot_idx)

func _on_row_current_value_changed(param: String, val: float) -> void:
	values[param] = val
	var slot_idx := get_slot_by_name(StringName(param))
	if slot_idx != -1:
		action_updated.emit(slot_idx)

func get_type() -> StringName:
	return &"tracking_input"

func serialize() -> Dictionary:
	var data := {"type": kind}
	if _list != null:
		data.merge(_list.get_ui_state())
	if not input_ranges.is_empty():
		var ranges := {}
		for param in input_ranges:
			var r: Vector2 = input_ranges[param]
			ranges[param] = [r.x, r.y]
		data["input_ranges"] = ranges
	return data

func get_parameter_list() -> BlueprintParameterList:
	return _list

func deserialize(data: Dictionary) -> void:
	for param in data.get("input_ranges", {}):
		var r = data["input_ranges"][param]
		if r is Array and r.size() == 2:
			input_ranges[String(param)] = Vector2(float(r[0]), float(r[1]))
	# kind must be applied first: its setter rebuilds the slots, which replaces
	# _list and would discard any UI state loaded beforehand.
	kind = data.get("type", kind)
	for param in data.get("input_ranges", {}):
		var r = data["input_ranges"][param]
		if r is Array and r.size() == 2:
			set_input_range(StringName(param), Vector2(float(r[0]), float(r[1])))
	if _list != null:
		_list.load_ui_state(data)
		_list.finalize_layout()

func _on_parameters_updated(parameters, _delta) -> void:
	for p in parameters:
		if p in values:
			values[p] = parameters[p]
			if p in value_displays and is_instance_valid(value_displays[p]):
				if not is_equal_approx(value_displays[p].value, parameters[p]):
					value_displays[p].value = parameters[p]
			var slot_idx := get_slot_by_name(p)
			if slot_idx != -1:
				action_updated.emit(slot_idx)

func get_input_slot_by_port(_port: int) -> int:
	return -1

func get_input_port_by_name(_slot: StringName) -> int:
	return -1

func get_output_slot_by_port(port: int) -> int:
	if _list == null or port < 0 or port >= _list.port_count:
		return -1
	return _list.slots.get(port, -1)

func get_output_port_by_name(slot: StringName) -> int:
	if _list == null:
		return -1
	return _list.ports.get(slot.to_lower(), -1)

func get_value(slot: int):
	if slot < 0 or slot >= get_child_count():
		return Vector4.ZERO
	var parameter: StringName = get_slot_name(slot)
	var out: float = values.get(parameter, Registry.get_default(parameter))
	var value_range: Vector2 = get_input_range(parameter)
	var normalized: float = inverse_lerp(value_range.x, value_range.y, out) if value_range.x != value_range.y else 0.0
	return Vector4(
		value_range.x,
		value_range.y,
		out,
		normalized
	)
