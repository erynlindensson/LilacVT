extends SceneTree
func _alive(p: int) -> bool:
	return p > 0 and DirAccess.dir_exists_absolute("/proc/%d" % p)
func _initialize():
	_run.call_deferred()
func _run():
	await process_frame
	await process_frame
	var script = load("res://lib/tracking/camera/openseeface/osf_tracker.gd")
	var tracker = script.new()
	tracker.port = 11575
	tracker.camera_id = 0
	root.add_child(tracker)
	await create_timer(2.5).timeout
	if not tracker.is_process_running():
		printerr("FAIL: OSF process not running after tracker ready")
		quit(1)
		return
	var pid = tracker.process.pid
	print("OK: tracker started pid=", pid)
	tracker.stop_tracking()
	await create_timer(0.5).timeout
	if tracker.is_process_running() or _alive(pid):
		printerr("FAIL: process alive after stop_tracking")
		quit(1)
		return
	print("OK: stop_tracking killed process")
	if not tracker.restart_tracking():
		printerr("FAIL: restart_tracking")
		quit(1)
		return
	await create_timer(1.5).timeout
	if not tracker.is_process_running():
		printerr("FAIL: not running after restart")
		quit(1)
		return
	print("OK: restart_tracking pid=", tracker.process.pid)
	pid = tracker.process.pid
	tracker.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.5).timeout
	if _alive(pid):
		printerr("FAIL: orphan process after queue_free pid=", pid)
		quit(1)
		return
	print("OK: no orphan after tracker freed")
	# Config script parses
	var cfg = load("res://lib/tracking/camera/openseeface/osf_config.gd")
	if cfg == null:
		printerr("FAIL: osf_config failed to load")
		quit(1)
		return
	print("OK: osf_config loads")
	quit(0)
