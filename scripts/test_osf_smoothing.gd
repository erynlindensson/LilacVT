extends SceneTree
## Headless smoke test for OSF tracker-level 1€ smoothing.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var script = load("res://lib/tracking/camera/openseeface/osf_tracker.gd")
	var tracker = script.new()
	root.add_child(tracker)
	await process_frame
	assert(tracker.tracking_smoothing > 0.0)
	var raw: float = tracker._smooth_param("FaceAngleX", 10.0)
	assert(typeof(raw) == TYPE_FLOAT)
	tracker.tracking_smoothing = 0.0
	assert(is_equal_approx(tracker._smooth_param("FaceAngleX", 7.5), 7.5))
	print("osf_smoothing_ok")
	quit(0)
