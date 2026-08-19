extends GraphEdit

const Serializers = preload("res://lib/utils/serializers.gd")
const VtModel = preload("res://lib/model/vt_model.gd")
const VtAction = preload("./vt_action.gd")
const GraphFrameGroup = preload("res://lib/blueprints/graph_frame_group.gd")

const GROUP_DROP_MARGIN := 24.0

const GROUP_TINTS: Array[Color] = [
	Color(0.35, 0.62, 0.95, 0.15),
	Color(0.35, 0.78, 0.42, 0.15),
	Color(0.92, 0.62, 0.28, 0.15),
	Color(0.72, 0.42, 0.88, 0.15),
	Color(0.88, 0.42, 0.52, 0.15),
]

var graph_elements: Dictionary[String, GraphNode] = {}
var graph_frames: Dictionary[String, GraphFrame] = {}
var _bindings: Array[Dictionary] = []

signal selection_changed(selected: Array)

static var _action_types: Array[PackedScene] = [
	preload("res://lib/blueprints/inputs/hotkey_action.tscn"),
	preload("res://lib/blueprints/inputs/screen_button.tscn"),
	preload("res://lib/blueprints/inputs/tracker_input.tscn"),
	preload("res://lib/blueprints/logic/arithmetic.tscn"),
	preload("res://lib/blueprints/logic/blink.tscn"),
	preload("res://lib/blueprints/logic/breathe.tscn"),
	preload("res://lib/blueprints/logic/smoothing.tscn"),
	preload("res://lib/blueprints/outputs/model_output.tscn"),
	preload("res://lib/blueprints/outputs/play_animation.tscn"),
	preload("res://lib/blueprints/outputs/toggle_expression.tscn")
]

static var palette: Dictionary[StringName, PackedScene] = _action_types.reduce(
	func (acc, template: PackedScene):
		var action = template.instantiate() as VtAction
		acc[action.get_type()] = template
		action.free()
		return acc,
	{} as Dictionary[StringName, PackedScene]
)

static func create_action(type: StringName) -> VtAction:
	if type in palette:
		var node = palette[type].instantiate()
		return node
	return null
	
func spawn_action(action_type, model: VtModel, id: String = "") -> VtAction:
	var node: VtAction
	if action_type is VtAction:
		node = action_type
	elif action_type is StringName:
		node = create_action(action_type)
		
	if node == null:
		return null
		
	node.graph = self
	node.model = model
	
	if id.is_empty():
		id = "%d" % rid_allocate_id()
	node.set_meta("id", id)
		
	add_child(node, true)
	node.position_offset = (scroll_offset + size / 2) / zoom - node.size / 2
	return node

func spawn_frame(title: String = "", id: String = "") -> GraphFrame:
	var frame: GraphFrame = GraphFrameGroup.new()
	if id.is_empty():
		id = "%d" % rid_allocate_id()
	frame.name = "Group_%s" % id
	frame.set_meta("id", id)
	frame.title = title if not title.is_empty() else _unique_group_title()
	frame.tint_color_enabled = true
	frame.tint_color = GROUP_TINTS[graph_frames.size() % GROUP_TINTS.size()]
	frame.autoshrink_enabled = true
	frame.selectable = true
	frame.draggable = true
	frame.resizable = true
	frame.custom_minimum_size = Vector2(160, 80)
	add_child(frame, true)
	frame.position_offset = (scroll_offset + size / 2) / zoom - Vector2(120, 80)
	frame.size = Vector2(160, 80)
	return frame

func _unique_group_title(base: String = "Group") -> String:
	var used: Dictionary = {}
	for frame in graph_frames.values():
		used[frame.title] = true
	if base not in used:
		return base
	for i in range(2, 1000):
		var candidate := "%s %d" % [base, i]
		if candidate not in used:
			return candidate
	return "%s %d" % [base, graph_frames.size() + 2]

func get_selected_actions() -> Array[VtAction]:
	var out: Array[VtAction] = []
	for node in graph_elements.values():
		if node is VtAction and node.is_selected():
			out.append(node)
	return out

func group_selected_actions(title: String = "") -> GraphFrame:
	var selected := get_selected_actions()
	if selected.is_empty():
		return null
	var frame := spawn_frame(title)
	for node in selected:
		_attach_to_frame(node, frame)
	return frame

func _attach_to_frame(action: VtAction, frame: GraphFrame) -> void:
	if get_element_frame(action.name) != null:
		detach_graph_element_from_frame(action.name)
	attach_graph_element_to_frame(action.name, frame.name)
	if frame is GraphFrameGroup:
		frame.queue_redraw()

func _detach_from_frame(action: VtAction) -> void:
	if get_element_frame(action.name) == null:
		return
	var frame := get_element_frame(action.name)
	detach_graph_element_from_frame(action.name)
	if frame is GraphFrameGroup:
		frame.queue_redraw()

func refresh_group_handles_for_frame(frame: GraphFrame) -> void:
	if frame is GraphFrameGroup:
		frame.refresh_title_handles()

func _frame_at_point(point: Vector2) -> GraphFrame:
	for frame_id in graph_frames:
		var frame: GraphFrame = graph_frames[frame_id]
		var rect := _frame_drop_rect(frame)
		if rect.has_point(point):
			return frame
	return null

func _frame_drop_rect(frame: GraphFrame) -> Rect2:
	var rect := Rect2(frame.position_offset, frame.size)
	if frame is GraphFrameGroup:
		var bar := GraphFrameGroup.TITLEBAR_HEIGHT
		rect = rect.merge(Rect2(frame.position_offset + Vector2(0, -bar), Vector2(frame.size.x, bar)))
	if rect.size.length_squared() < 256.0:
		rect.size = Vector2(maxf(rect.size.x, 160.0), maxf(rect.size.y, 80.0))
	return rect.grow(GROUP_DROP_MARGIN)

func _node_drop_point(node: GraphElement) -> Vector2:
	return node.position_offset + node.size * 0.5

func _apply_drop_membership(moved: Array) -> void:
	for element in moved:
		if element is not VtAction:
			continue
		if element is GraphFrame:
			continue
		var point := _node_drop_point(element)
		var target := _frame_at_point(point)
		var current := get_element_frame(element.name)
		if target != null and target != current:
			_attach_to_frame(element, target)
		elif target == null and current != null:
			var current_rect := _frame_drop_rect(current)
			if not current_rect.has_point(point):
				_detach_from_frame(element)

func _on_graph_elements_linked_to_frame_request(
	elements: Array,
	frame_name: StringName
) -> void:
	var frame := get_node_or_null(NodePath(frame_name)) as GraphFrame
	if frame == null:
		return
	for element_name in elements:
		var node := get_node_or_null(NodePath(element_name))
		if node is VtAction:
			_attach_to_frame(node, frame)

func _on_end_node_move() -> void:
	var moved: Array = []
	for child in get_children():
		if child is VtAction and child.is_selected():
			moved.append(child)
	if not moved.is_empty():
		_apply_drop_membership(moved)
	for frame in graph_frames.values():
		if frame is GraphFrameGroup:
			frame.queue_redraw()

func deserialize_groups(groups: Array) -> void:
	for entry in groups:
		if entry is not Dictionary:
			continue
		var data: Dictionary = entry
		var frame_id: String = data.get("id", "")
		if frame_id.is_empty():
			continue
		var frame := spawn_frame(data.get("title", "Group"), frame_id)
		frame.position_offset = Serializers.Vec2Serializer.from_json(
			data.get("position"), frame.position_offset
		)
		frame.autoshrink_enabled = data.get("autoshrink", true)
		frame.tint_color_enabled = data.get("tint_enabled", true)
		var tint = data.get("tint", "")
		if tint is String and not tint.is_empty():
			frame.tint_color = Color.from_string(tint, frame.tint_color)
		if not frame.autoshrink_enabled and data.has("size"):
			frame.size = Serializers.Vec2Serializer.from_json(data.size, frame.size)
		for node_id in data.get("nodes", []):
			if node_id in graph_elements:
				var action: VtAction = graph_elements[node_id]
				if get_element_frame(action.name) != null:
					detach_graph_element_from_frame(action.name)
				attach_graph_element_to_frame(action.name, frame.name)
	for frame in graph_frames.values():
		if frame is GraphFrameGroup:
			frame.queue_redraw()

func _action_id_for_element_name(element_name: StringName) -> String:
	var node := get_node_or_null(NodePath(element_name))
	if node is VtAction:
		return node.get_meta("id", "")
	return ""

func _serialize_groups() -> Array:
	var groups: Array = []
	for frame_id in graph_frames:
		var frame: GraphFrame = graph_frames[frame_id]
		var node_ids: Array[String] = []
		for element_name in get_attached_nodes_of_frame(frame.name):
			var action_id := _action_id_for_element_name(element_name)
			if not action_id.is_empty():
				node_ids.append(action_id)
		groups.append({
			"id": frame_id,
			"title": frame.title,
			"position": Serializers.Vec2Serializer.to_json(frame.position_offset),
			"size": Serializers.Vec2Serializer.to_json(frame.size),
			"autoshrink": frame.autoshrink_enabled,
			"tint_enabled": frame.tint_color_enabled,
			"tint": frame.tint_color.to_html(true),
			"nodes": node_ids,
		})
	return groups

func _ready() -> void:
	add_valid_connection_type(VtAction.SlotType.VECTOR, VtAction.SlotType.NUMERIC)
	graph_elements_linked_to_frame_request.connect(_on_graph_elements_linked_to_frame_request)
	end_node_move.connect(_on_end_node_move)
	child_entered_tree.connect(_connect_selection_signals)
	for child in get_children():
		_connect_selection_signals(child)

func get_selected_elements() -> Array:
	var selected: Array = []
	for child in get_children():
		if child is GraphElement and child.is_selected():
			selected.append(child)
	return selected

func _connect_selection_signals(node: Node) -> void:
	if node is not GraphElement:
		return
	if node.node_selected.is_connected(_on_element_selection_changed):
		return
	node.node_selected.connect(_on_element_selection_changed)
	node.node_deselected.connect(_on_element_selection_changed)

func _on_element_selection_changed() -> void:
	for frame in graph_frames.values():
		if frame is GraphFrameGroup:
			frame.queue_redraw()
	selection_changed.emit(get_selected_elements())

func refresh_wire_colors() -> void:
	for node in graph_elements.values():
		if node is VtAction:
			node.ensure_slot_colors()
	for conn in get_connection_list():
		set_connection_activity(
			conn.from_node, conn.from_port, conn.to_node, conn.to_port, 0.0
		)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		sync_visual_connections.call_deferred()

func connect_binding(from_node: StringName, from_slot: StringName, to_node: StringName, to_slot: StringName) -> bool:
	if not is_node_ready():
		await self.ready
	var n1 := get_node_or_null(NodePath(from_node)) as VtAction
	var n2 := get_node_or_null(NodePath(to_node)) as VtAction
	if n1 == null or n2 == null:
		return false

	var s1 := n1.get_slot_by_name(from_slot)
	var s2 := n2.get_slot_by_name(to_slot)
	if s1 == -1 or s2 == -1:
		return false

	var out_type = n1.get_output_type(s1)
	var in_type = n2.get_input_type(s2)
	if in_type == -1 or out_type == -1:
		return false
	if in_type != out_type and not (in_type == VtAction.SlotType.NUMERIC and out_type == VtAction.SlotType.VECTOR):
		return false

	# Non-triggers can only have one incoming binding per destination slot
	if in_type != VtAction.SlotType.TRIGGER:
		var to_remove: Array = []
		for b in _bindings:
			if b.to_node == to_node and String(b.to_slot).to_lower() == String(to_slot).to_lower():
				to_remove.append(b)
		for b in to_remove:
			disconnect_binding(b.from_node, b.from_slot, b.to_node, b.to_slot)

	for b in _bindings:
		if b.from_node == from_node and String(b.from_slot).to_lower() == String(from_slot).to_lower() \
		and b.to_node == to_node and String(b.to_slot).to_lower() == String(to_slot).to_lower():
			return true

	_bindings.append({
		"from_node": from_node,
		"from_slot": from_slot,
		"to_node": to_node,
		"to_slot": to_slot,
	})
	n2.bind(s2, n1)
	sync_visual_connections()
	return true

func disconnect_binding(from_node: StringName, from_slot: StringName, to_node: StringName, to_slot: StringName) -> void:
	var target_idx := -1
	for idx in range(_bindings.size()):
		var b: Dictionary = _bindings[idx]
		if b.from_node == from_node and String(b.from_slot).to_lower() == String(from_slot).to_lower() \
		and b.to_node == to_node and String(b.to_slot).to_lower() == String(to_slot).to_lower():
			target_idx = idx
			break

	if target_idx != -1:
		_bindings.remove_at(target_idx)

	var n1 := get_node_or_null(NodePath(from_node)) as VtAction
	var n2 := get_node_or_null(NodePath(to_node)) as VtAction
	if n2 != null:
		var s2 := n2.get_slot_by_name(to_slot)
		if s2 != -1:
			n2.unbind(s2, n1)
			n2.reset_value(s2)

	sync_visual_connections()

func sync_visual_connections() -> void:
	clear_connections()
	for b in _bindings:
		var from_node := get_node_or_null(NodePath(b.from_node)) as VtAction
		var to_node := get_node_or_null(NodePath(b.to_node)) as VtAction
		if from_node == null or to_node == null:
			continue
		var from_port: int = from_node.get_output_port_by_name(b.from_slot)
		var to_port: int = to_node.get_input_port_by_name(b.to_slot)
		if from_port != -1 and to_port != -1:
			connect_node(b.from_node, from_port, b.to_node, to_port)
	refresh_wire_colors()

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if not is_node_ready():
		await self.ready
	var n1 := get_node_or_null(NodePath(from_node)) as VtAction
	var n2 := get_node_or_null(NodePath(to_node)) as VtAction
	if n1 == null or n2 == null:
		return
	var s1: int = n1.get_output_slot_by_port(from_port)
	var s2: int = n2.get_input_slot_by_port(to_port)
	if s1 == -1 or s2 == -1:
		return
	var from_name := n1.get_slot_name(s1)
	var to_name := n2.get_slot_name(s2)
	connect_binding(from_node, from_name, to_node, to_name)

func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	var n1 := get_node_or_null(NodePath(from_node)) as VtAction
	var n2 := get_node_or_null(NodePath(to_node)) as VtAction
	var from_name: StringName = &""
	var to_name: StringName = &""
	if n1 != null:
		var s1 := n1.get_output_slot_by_port(from_port)
		if s1 != -1:
			from_name = n1.get_slot_name(s1)
	if n2 != null:
		var s2 := n2.get_input_slot_by_port(to_port)
		if s2 != -1:
			to_name = n2.get_slot_name(s2)
	if not from_name.is_empty() and not to_name.is_empty():
		disconnect_binding(from_node, from_name, to_node, to_name)
	else:
		disconnect_node(from_node, from_port, to_node, to_port)

func _on_child_entered_tree(node: Node) -> void:
	if node is GraphFrame:
		var frame_id = node.get_meta("id", "")
		if frame_id.is_empty():
			frame_id = "%d" % rid_allocate_id()
			node.set_meta("id", frame_id)
		graph_frames[frame_id] = node
		_connect_selection_signals(node)
		return
	if node is not VtAction:
		return

	var id = node.get_meta("id", "")
	assert(not id.is_empty(), "node has invalid id")

	graph_elements[id] = node
	node.action_updated.connect(_on_action.bind(node))
	_connect_selection_signals(node)
	if node.has_method(&"get_parameter_list"):
		var plist = node.get_parameter_list()
		if plist != null and not plist.layout_changed.is_connected(sync_visual_connections):
			plist.layout_changed.connect(sync_visual_connections)

func _on_child_exiting_tree(node: Node) -> void:
	if node is GraphFrame:
		var frame_id = node.get_meta("id", "")
		if not frame_id.is_empty():
			graph_frames.erase(frame_id)
		return
	if node is not VtAction:
		return

	var id = node.get_meta("id", "")
	if not id.is_empty() and id in graph_elements:
		graph_elements.erase(id)
	node.action_updated.disconnect(_on_action.bind(node))

func _on_action(from_port_or_slot: int, node: VtAction) -> void:
	var from_slot := from_port_or_slot
	if node.get_child_count() > 0:
		var slot_from_port := node.get_output_slot_by_port(from_port_or_slot)
		if slot_from_port != -1:
			from_slot = slot_from_port
	if from_slot < 0 or from_slot >= node.get_child_count():
		return

	var from_name := node.get_slot_name(from_slot)
	var output_type = node.get_output_type(from_slot)
	var value = node.get_value(from_slot)

	for b in _bindings:
		if b.from_node != node.name or String(b.from_slot).to_lower() != String(from_name).to_lower():
			continue
		var target := get_node_or_null(NodePath(b.to_node)) as VtAction
		if target == null:
			continue
		var to_slot := target.get_slot_by_name(b.to_slot)
		if to_slot == -1:
			continue
		var input_type = target.get_input_type(to_slot)
		match output_type:
			VtAction.SlotType.TRIGGER:
				target.invoke_trigger(to_slot)
			_:
				if input_type == VtAction.SlotType.NUMERIC and output_type == VtAction.SlotType.VECTOR:
					if value is Vector4:
						target.update_value(to_slot, (value as Vector4).w)
					else:
						target.update_value(to_slot, float(value) if value != null else 0.0)
				else:
					target.update_value(to_slot, value)

func _on_delete_nodes_request(nodes: Array[StringName]) -> void:
	for i in nodes:
		var n = get_node_or_null(NodePath(i))
		if n == null:
			continue
		if n is VtAction:
			_disconnect_all(n)
		elif n is GraphFrame:
			for element_name in get_attached_nodes_of_frame(n.name):
				detach_graph_element_from_frame(element_name)
		n.queue_free()

## Tears down every connection touching a node so bound targets release it.
## Freeing the node alone drops the wires without ever calling unbind.
func _disconnect_all(node: VtAction) -> void:
	var to_remove: Array = []
	for b in _bindings:
		if b.from_node == node.name or b.to_node == node.name:
			to_remove.append(b)
	for b in to_remove:
		disconnect_binding(b.from_node, b.from_slot, b.to_node, b.to_slot)

func serialize() -> Dictionary:
	var nodes = []
	var bindings = []

	for i in graph_elements.values():
		var node = {
			"id": i.get_meta("id"),
			"type": i.get_type(),
			"position": Serializers.Vec2Serializer.to_json(i.position_offset),
			"parameters": i.serialize(),
		}
		nodes.append(node)

	for b in _bindings:
		var from_node := get_node_or_null(NodePath(b.from_node)) as VtAction
		var to_node := get_node_or_null(NodePath(b.to_node)) as VtAction
		if from_node == null or to_node == null:
			continue
		var from_id = from_node.get_meta("id", "")
		var to_id = to_node.get_meta("id", "")
		bindings.append({
			"src": from_id,
			"dst": to_id,
			"src_slot": b.from_slot,
			"dst_slot": b.to_slot,
		})

	return {
		"enabled": process_mode != PROCESS_MODE_DISABLED,
		"nodes": nodes,
		"bindings": bindings,
		"groups": _serialize_groups(),
	}
