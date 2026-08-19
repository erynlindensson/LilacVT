extends "./blueprint_loader.gd"

const Serializers = preload("res://lib/utils/serializers.gd")

func id() -> StringName:
	return "ovt"
	
func load_graph(model: VtModel) -> Array:
	var ovt_data: Dictionary = Files.read_json(model.modelmeta.openvt_parameters)
	if ovt_data.is_empty():
		return []
		
	var graphs: Dictionary = ovt_data.get("graphs", {})
	if graphs.is_empty():
		return []
	
	var valid_graphs = []
	for profile in graphs:
		var graph: Blueprint = BlueprintTemplate.instantiate()
		graph.name = profile
		add_child(graph)
		_deserialize(graph, model, graphs[profile])
		var keep := graph.get_child_count() > 0
		remove_child(graph)
		if keep:
			valid_graphs.append(graph)
		else:
			# nothing adopts an empty profile, so it has to be freed here or the
			# detached GraphEdit leaks for the lifetime of the process
			graph.queue_free()

	return valid_graphs

func _deserialize(graph: Blueprint, model: VtModel, data: Dictionary):
	for i in data.get("nodes", []):
		var id = i.get("id", "")
		if id.is_empty():
			continue
		var n = graph.spawn_action(StringName(i.type), model, id)
		if n == null:
			push_error("invalid action type (%s), clearing graph" % i.type)
			graph.clear_connections()
			for c in graph.get_children():
				c.queue_free()
			return 
		
		
		n.deserialize(i.get("parameters", {}))
		n.position_offset = Serializers.Vec2Serializer.from_json(i.get("position"), Vector2.ZERO)
	
	graph.deserialize_groups(data.get("groups", []))
		
	for i in data.get("bindings", []):
		if i.src in graph.graph_elements and i.dst in graph.graph_elements:
			var from_node: VtAction = graph.graph_elements[i.src]
			var to_node: VtAction = graph.graph_elements[i.dst]
			if from_node == null or to_node == null:
				continue
			var src_slot = String(i.src_slot)
			var dst_slot = String(i.dst_slot)
			graph.connect_binding(from_node.name, src_slot, to_node.name, dst_slot)

	graph.sync_visual_connections.call_deferred()
	graph.process_mode = PROCESS_MODE_INHERIT if data.get("enabled", true) else PROCESS_MODE_DISABLED
