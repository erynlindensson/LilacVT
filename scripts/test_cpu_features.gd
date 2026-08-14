extends SceneTree
## Headless test for CPU AVX probe used to hide MediaPipe.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var cpu = load("res://lib/utils/cpu_features.gd")
	if cpu == null:
		printerr("FAIL: cpu_features.gd failed to load")
		quit(1)
		return
	var detected: bool = cpu.has_avx()
	var expected := false
	var f := FileAccess.open("/proc/cpuinfo", FileAccess.READ)
	if f != null:
		while not f.eof_reached():
			var line := f.get_line()
			if line.begins_with("flags"):
				expected = (" " + line.strip_edges() + " ").contains(" avx ")
				break
	if detected != expected:
		printerr("FAIL: has_avx=%s expected=%s" % [str(detected), str(expected)])
		quit(1)
		return
	print("cpu_features_ok avx=%s" % str(detected))
	quit(0)
