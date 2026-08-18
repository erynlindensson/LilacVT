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
			var value_range: Vector2 = Registry[p].range
			var row := _list.add_parameter_row(
				p,
				value_range,
				Registry.get_default(p),
				&"output",
				SlotType.VECTOR,
				true
			)
			if row == null:
				continue
			label_width = maxf(
				label_width,
				row.get_theme_default_font().get_string_size(p).x
			)
			values[p] = Registry.get_default(p)
			value_displays[p] = row.current_value

	_apply_default_collapse.call_deferred()
	_list.finalize_layout(label_width)
	ensure_slot_colors()

func _apply_default_collapse() -> void:
	var expanded_groups: Array = []
	if graph != null:
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
	if graph != null and graph.has_method(&"refresh_wire_colors"):
		graph.refresh_wire_colors()

func get_type() -> StringName:
	return &"tracking_input"

func serialize() -> Dictionary:
	var data := {"type": kind}
	if _list != null:
		data.merge(_list.get_ui_state())
	return data

func get_parameter_list() -> BlueprintParameterList:
	return _list

func deserialize(data: Dictionary) -> void:
	if _list != null:
		_list.load_ui_state(data)
		_list.finalize_layout()
	kind = data.get("type", kind)

func _on_parameters_updated(parameters, _delta) -> void:
	for p in parameters:
		if p in values:
			values[p] = parameters[p]
			value_displays[p].value = parameters[p]
			slot_updated.emit(get_output_port_by_name(p))

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
	var parameter: StringName = get_slot_name(slot)
	var out: float = values[parameter]
	var value_range = Registry.get(parameter).range
	return Vector4(
		value_range.x,
		value_range.y,
		out,
		inverse_lerp(value_range.x, value_range.y, out)
	)
