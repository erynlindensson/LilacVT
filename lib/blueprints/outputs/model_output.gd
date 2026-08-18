extends "../vt_action.gd"

const ParameterGrouping = preload("res://lib/blueprints/ui/parameter_grouping.gd")
const ParameterList = preload("res://lib/blueprints/ui/parameter_list.gd")
const ParameterRow = preload("res://lib/blueprints/ui/parameter_row.gd")

var _list: ParameterList
var bindings = {}
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
	if graph != null and graph.has_method(&"refresh_wire_colors"):
		graph.refresh_wire_colors()

func refresh_fields() -> void:
	var conns = graph.get_connection_list_from_node(self.name)
	for c in conns:
		if c.to_node != self.name:
			continue
		var old_port = c.to_port
		c.slot_name = get_slot_name(get_input_slot_by_port(c.to_port))
		graph.disconnect_node(
			c.from_node, c.from_port,
			c.to_node, old_port
		)

	_refresh = true
	await (Engine.get_main_loop() as SceneTree).process_frame
	if not _refresh:
		return

	_rebuild_port_maps()

	for c in conns:
		var new_port = get_input_port_by_name(c.slot_name)
		if new_port != -1:
			graph.connect_node(
				c.from_node, c.from_port,
				c.to_node, new_port
			)
	_refresh = false
	size.y = 0

func _rebuild_port_maps() -> void:
	_list.ports.clear()
	_list.slots.clear()
	var port_idx := 0
	for child in get_children():
		if child is ParameterRow:
			var param: String = child.parameter_name
			var vis: bool = model.get("modifiers/parameters/%s/visible" % param)
			_list.set_row_enabled(param, vis)
			var slot := child.get_index()
			if vis:
				_list.ports[param.to_lower()] = port_idx
				_list.slots[port_idx] = slot
				port_idx += 1
			apply_slot_color(slot, &"left")
	_list.port_count = port_idx

func unbind(slot: int, node: GraphNode) -> void:
	var param = get_slot_name(get_input_slot_by_port(slot))
	bindings.erase(param)

func reset_value(slot: int) -> void:
	var param = get_slot_name(get_input_slot_by_port(slot))
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
	return _list.get_ui_state()

func get_parameter_list() -> BlueprintParameterList:
	return _list

func deserialize(data: Dictionary) -> void:
	if _list != null:
		_list.load_ui_state(data)
		_list.finalize_layout()

func update_value(slot: int, v: Variant) -> void:
	var parameter: StringName = get_slot_name(slot)
	var value_range: Vector2 = model.get("parameters/%s/range" % [parameter])
	bindings[parameter] = lerp(value_range.x, value_range.y, v as float)
	_dirty = true

func _update_model() -> void:
	if not _dirty:
		return

	for p in bindings:
		binding_display[p].value = bindings[p]
		model.set("parameters/%s" % [p], bindings[p])
	_dirty = false
	bindings.clear()

func _process(_delta: float) -> void:
	_update_model()
