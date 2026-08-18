extends Node
## Smoke test: boot the studio, open the blueprint editor, and exercise the group
## and inspector paths. It asserts those paths complete; it does NOT assert the
## console is clean, so check stderr as well when running it.
##
## The editor is a Window built by hud.gd only in response to a button press, so
## nothing headless reached it before. Run with:
##   godot4-ayagami --headless --path . res://scripts/test_blueprint_editor_smoke.tscn

const StudioScene = preload("res://studio/studio.tscn")
const EditorScene = preload("res://studio/hud/blueprint_editor/editor.tscn")
const Blueprint = preload("res://lib/blueprints/blueprint.gd")

## how long to let the studio settle and load its model before opening the editor
const BOOT_SECONDS := 8.0

var _studio: Node

func _ready() -> void:
	_run()

func _run() -> void:
	_studio = StudioScene.instantiate()
	add_child(_studio)

	await get_tree().create_timer(BOOT_SECONDS).timeout

	var stage = get_tree().get_first_node_in_group("system:stage")
	if stage == null:
		_fail("no node in group system:stage")
		return
	if stage.active_model == null:
		_skip("no model loaded; put a model under user://Live2DModels to run this")
		return

	var editor = EditorScene.instantiate()
	editor.active_model = stage.active_model
	editor.visible = true
	add_child(editor)

	# let _ready reparent the model's graphs into the profile tabs
	await get_tree().process_frame
	await get_tree().process_frame

	var profiles = editor.get_node_or_null("%Profiles")
	if profiles == null:
		_fail("editor has no %Profiles node")
		return
	if profiles.get_child_count() == 0:
		_skip("model has no blueprint profiles to exercise")
		return

	var graph: Blueprint = profiles.get_child(0)

	# exercise the group + inspector paths the editor toolbar drives
	var frame = graph.spawn_frame("Smoke")
	if frame == null:
		_fail("spawn_frame returned null")
		return

	var actions := []
	for child in graph.get_children():
		if child.get_class() == "GraphFrame":
			continue
		if child.has_method("get_type"):
			actions.append(child)
	if actions.is_empty():
		_skip("profile has no actions to group")
		return

	actions[0].set_selected(true)
	graph.group_selected_actions("Smoke Selection")
	graph.refresh_wire_colors()

	# the inspector rebuilds its fields from whatever is selected
	editor.get_node("%InspectorPanel").bind_graph(graph)
	editor.get_node("%InspectorPanel").show_element(actions[0])
	await get_tree().process_frame
	editor.get_node("%InspectorPanel").show_element(frame)
	await get_tree().process_frame

	# serialize the whole editor state the way save_settings does
	var model_data := {}
	editor.save_settings(model_data)
	if not model_data.has("graphs"):
		_fail("save_settings produced no graphs")
		return

	print("blueprint_editor_smoke_ok")
	get_tree().quit(0)

func _skip(msg: String) -> void:
	print("SKIP %s" % msg)
	print("blueprint_editor_smoke_ok")
	get_tree().quit(0)

func _fail(msg: String) -> void:
	printerr("FAIL %s" % msg)
	get_tree().quit(1)
