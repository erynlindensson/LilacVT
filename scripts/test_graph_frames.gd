extends Node
## Round-trip test for blueprint GraphFrame groups.
##
## Runs as a scene rather than via --script: Blueprint.palette instantiates every
## action scene at static-init time, and those reach the Registry / GlobalInput /
## BlueprintManager autoloads, which only exist when a scene is run.
##   godot4-ayagami --headless --path . res://scripts/test_graph_frames.tscn

const BlueprintScene = preload("res://lib/blueprints/blueprint.tscn")
const Blueprint = preload("res://lib/blueprints/blueprint.gd")
const VtAction = preload("res://lib/blueprints/vt_action.gd")

func _ready() -> void:
	_run()

func _run() -> void:
	var graph: Blueprint = BlueprintScene.instantiate()
	add_child(graph)

	var a: VtAction = graph.spawn_action(&"breathe", null)
	var b: VtAction = graph.spawn_action(&"smoothing", null)
	if a == null or b == null:
		_fail("could not spawn test nodes")
		return

	a.position_offset = Vector2(40, 40)
	b.position_offset = Vector2(220, 40)
	a.set_selected(true)
	b.set_selected(true)

	var frame := graph.group_selected_actions("Inputs")
	if frame == null:
		_fail("group_selected_actions returned null")
		return
	if frame.title != "Inputs":
		_fail("expected frame title 'Inputs', got '%s'" % frame.title)
		return

	var attached: Array = graph.get_attached_nodes_of_frame(frame.name)
	if attached.size() != 2:
		_fail("expected 2 attached nodes, got %d" % attached.size())
		return

	var data := graph.serialize()
	var groups: Array = data.get("groups", [])
	if groups.size() != 1:
		_fail("expected 1 serialized group, got %d" % groups.size())
		return
	if groups[0].get("title", "") != "Inputs":
		_fail("group title lost in serialize")
		return
	if groups[0].get("nodes", []).size() != 2:
		_fail("expected 2 member ids in serialized group")
		return

	_verify(data)

func _verify(data: Dictionary) -> void:
	var graph2: Blueprint = BlueprintScene.instantiate()
	add_child(graph2)

	for node_data in data.nodes:
		var n: VtAction = graph2.spawn_action(
			StringName(node_data.type), null, node_data.id
		)
		if n == null:
			_fail("could not restore node %s" % node_data.type)
			return
		n.position_offset = Vector2(node_data.position.x, node_data.position.y)

	graph2.deserialize_groups(data.groups)

	if graph2.graph_frames.size() != 1:
		_fail("expected 1 restored frame, got %d" % graph2.graph_frames.size())
		return

	var restored_frame: GraphFrame = graph2.graph_frames.values()[0]
	if restored_frame.title != "Inputs":
		_fail("restored frame title is '%s'" % restored_frame.title)
		return

	var restored: Array = graph2.get_attached_nodes_of_frame(restored_frame.name)
	if restored.size() != 2:
		_fail("expected 2 restored attachments, got %d" % restored.size())
		return

	# the restored group must hold the same actions, matched by their stable ids
	var restored_ids: Array = []
	for element_name in restored:
		var node := graph2.get_node_or_null(NodePath(element_name))
		restored_ids.append(String(node.get_meta("id", "")))
	restored_ids.sort()
	var expected_ids: Array = data.groups[0].nodes.duplicate()
	expected_ids.sort()
	if restored_ids != expected_ids:
		_fail("membership changed: %s != %s" % [restored_ids, expected_ids])
		return

	print("graph_frames_ok")
	get_tree().quit(0)

func _fail(msg: String) -> void:
	printerr("FAIL %s" % msg)
	get_tree().quit(1)
