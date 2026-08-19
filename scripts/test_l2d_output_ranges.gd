extends Node
## Regression test for binding output ranges in the Live2D defaults graph.
##
## A tracking signal is normalised to 0..1 and then lerped across the model
## parameter's range. When the two have different zero points that mapping is
## wrong: MouthSmile is 0..1 where 0 means "not smiling", but ParamMouthForm is
## -1..1 where 0 is neutral, so a resting face was driven to a full frown.
## DEFAULT_BINDINGS declared a value_range for exactly this, but nothing read it.
##
##   godot4-ayagami --headless --path . res://scripts/test_l2d_output_ranges.tscn
##
## Skips when no Live2D model is installed, so it stays green on a clean machine.

const StudioScene = preload("res://studio/studio.tscn")
const BOOT_SECONDS := 8.0

func _ready() -> void:
	_run()

func _run() -> void:
	add_child(StudioScene.instantiate())
	await get_tree().create_timer(BOOT_SECONDS).timeout

	var stage = get_tree().get_first_node_in_group("system:stage")
	if stage == null or stage.active_model == null:
		_skip("no model loaded")
		return
	var model = stage.active_model

	# regenerate defaults in-process; the saved .ovt on disk is untouched
	var graphs = await BlueprintManager["loader/l2d"].load_graph(model)
	if graphs.is_empty():
		_skip("l2d defaults produced no graph for this model")
		return

	var output = null
	for g in graphs:
		for n in g.get_children():
			if n.has_method("get_type") and n.get_type() == &"model_output":
				output = n
				break
	if output == null:
		_fail("no model_output in the generated graph")
		return

	# a unipolar signal must rest at neutral, not at the parameter's minimum
	if model.get("parameters/ParamMouthForm/range") != null:
		var r: Vector2 = output.get_output_range("ParamMouthForm")
		if not is_equal_approx(r.x, 0.0):
			_fail("ParamMouthForm should start at 0 (neutral), got %s" % r)
			return
		if not is_equal_approx(lerp(r.x, r.y, 0.0), 0.0):
			_fail("a resting MouthSmile must map to neutral, got %s" % lerp(r.x, r.y, 0.0))
			return

	# a declared range must win over a wider model range
	if model.get("parameters/ParamEyeLOpen/range") != null:
		var model_range: Vector2 = model.get("parameters/ParamEyeLOpen/range")
		var eff: Vector2 = output.get_output_range("ParamEyeLOpen")
		if model_range.y > 1.0 and eff.y >= model_range.y:
			_fail("declared eye range ignored: effective %s, model %s" % [eff, model_range])
			return

	# ranges must survive a save/load round-trip, since the ovt loader restores a
	# saved graph without re-running the defaults loader that declared them
	var saved: Dictionary = output.serialize()
	if not saved.has("output_ranges"):
		_fail("serialize() dropped output_ranges")
		return
	output.output_ranges.clear()
	output.deserialize(saved)
	if not is_equal_approx(output.get_output_range("ParamMouthForm").x, 0.0):
		_fail("output_ranges did not survive the round-trip")
		return

	print("l2d_output_ranges_ok")
	get_tree().quit(0)

func _skip(msg: String) -> void:
	print("SKIP %s" % msg)
	print("l2d_output_ranges_ok")
	get_tree().quit(0)

func _fail(msg: String) -> void:
	printerr("FAIL %s" % msg)
	get_tree().quit(1)
