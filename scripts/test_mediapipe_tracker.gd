extends SceneTree
## Headless smoke test for MediaPipe tracker JSON mapping (no webcam / venv).

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var cpu = load("res://lib/utils/cpu_features.gd")
	if cpu == null:
		printerr("FAIL: cpu_features.gd failed to load")
		quit(1)
		return
	var script = load("res://lib/tracking/camera/mediapipe/mp_tracker.gd")
	if script == null:
		printerr("FAIL: mp_tracker.gd failed to load")
		quit(1)
		return
	var tracker = script.new()
	root.add_child(tracker)
	await process_frame
	tracker.smoothing = 0.0
	tracker.tracking_smoothing = 0.0
	tracker.blink_sync = true
	tracker.apply_packet({
		"FaceAngleX": 12.5,
		"MouthOpen": 0.8,
		"EyeOpenLeft": 0.2,
		"EyeOpenRight": 0.9,
	})
	var params: Dictionary = tracker._parameters
	if not params.has("FaceAngleX") or absf(float(params["FaceAngleX"]) - 12.5) > 0.2:
		printerr("FAIL: FaceAngleX not applied")
		quit(1)
		return
	if absf(float(params.get("EyeOpenLeft", -1.0)) - 0.9) > 0.2:
		printerr("FAIL: blink_sync did not copy EyeOpenRight")
		quit(1)
		return
	var cfg = load("res://lib/tracking/camera/mediapipe/mp_config.gd")
	if cfg == null:
		printerr("FAIL: mp_config.gd failed to load")
		quit(1)
		return
	var proc_script = load("res://lib/tracking/camera/mediapipe/mp_process.gd")
	var proc = proc_script.new()
	if not proc.has_sources():
		printerr("FAIL: MediaPipe facetracker.py missing")
		quit(1)
		return
	if not cpu.has_avx():
		if proc.is_ready():
			printerr("FAIL: MediaPipe must not be ready without AVX")
			quit(1)
			return
		if proc.start():
			printerr("FAIL: MediaPipe must not start without AVX")
			quit(1)
			return
	print("mediapipe_tracker_ok avx=%s" % str(cpu.has_avx()))
	quit(0)
