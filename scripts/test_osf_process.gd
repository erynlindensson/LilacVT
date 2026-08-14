extends SceneTree
func _initialize():
	_run.call_deferred()
func _run():
	await process_frame
	var OsfProcess = load("res://lib/tracking/camera/openseeface/osf_process.gd")
	var proc = OsfProcess.new()
	print("python=", proc.python_path())
	print("root=", proc.root_dir())
	if not proc.start(11574, 0):
		printerr("FAIL start: ", proc.last_error)
		quit(1)
		return
	print("OK: started pid=", proc.pid)
	await create_timer(2.0).timeout
	if not proc.is_running():
		printerr("FAIL: process not running after start")
		quit(1)
		return
	print("OK: process running")
	proc.stop()
	await create_timer(0.5).timeout
	if proc.is_running():
		printerr("FAIL: process still running after stop")
		quit(1)
		return
	print("OK: process stopped")
	quit(0)
