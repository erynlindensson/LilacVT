extends RefCounted

## Manages the bundled OpenSeeFace facetracker.py child process.

const ROOT_REL := "res://thirdparty/openseeface"
const SETUP_HINT := "OpenSeeFace is not set up. Run scripts/setup_openseeface.sh"

var pid: int = -1
var last_error: String = ""

func is_running() -> bool:
	if pid <= 0:
		return false
	# Prefer /proc on Linux so we don't trip Godot's child-only PID checks
	# after the process has already exited.
	if DirAccess.dir_exists_absolute("/proc/%d" % pid):
		return true
	pid = -1
	return false

func root_dir() -> String:
	return ProjectSettings.globalize_path(ROOT_REL)

func python_path() -> String:
	var venv_python := root_dir().path_join(".venv/bin/python")
	if FileAccess.file_exists(venv_python):
		return venv_python
	# Windows fallback for completeness; Linux/mac use python3.
	var venv_win := root_dir().path_join(".venv/Scripts/python.exe")
	if FileAccess.file_exists(venv_win):
		return venv_win
	return "python3"

func is_ready() -> bool:
	var root := root_dir()
	if not FileAccess.file_exists(root.path_join("facetracker.py")):
		last_error = SETUP_HINT
		return false
	if not DirAccess.dir_exists_absolute(root.path_join("models")):
		last_error = SETUP_HINT
		return false
	var py := python_path()
	if py == "python3":
		# Allow system python, but prefer alerting if no venv.
		last_error = SETUP_HINT
		# Still usable if system deps exist; warn but don't block.
	return true

func start(port: int = 11573, camera_id: int = 0) -> bool:
	if is_running():
		return true
	
	if not FileAccess.file_exists(root_dir().path_join("facetracker.py")):
		last_error = SETUP_HINT
		return false
	if not DirAccess.dir_exists_absolute(root_dir().path_join("models")):
		last_error = SETUP_HINT
		return false
	
	var py := python_path()
	var script := root_dir().path_join("facetracker.py")
	var model_dir := root_dir().path_join("models")
	
	var args: PackedStringArray = [
		script,
		"-i", "127.0.0.1",
		"-p", str(port),
		"-c", str(camera_id),
		"-W", "1280",
		"-H", "720",
		"--model-dir", model_dir,
		"--discard-after", "0",
		"--scan-every", "0",
		"--no-3d-adapt", "1",
		"--max-feature-updates", "900",
	]
	if not OS.is_debug_build():
		args.append_array(PackedStringArray(["--silent", "1"]))
	
	pid = OS.create_process(py, args, false)
	if pid <= 0:
		last_error = "Failed to start OpenSeeFace (%s). %s" % [py, SETUP_HINT]
		pid = -1
		return false
	
	last_error = ""
	return true

func stop() -> void:
	if pid <= 0:
		return
	var to_kill := pid
	pid = -1
	if not DirAccess.dir_exists_absolute("/proc/%d" % to_kill):
		return
	var err := OS.kill(to_kill)
	if err != OK:
		OS.execute("kill", PackedStringArray(["-TERM", str(to_kill)]))
		OS.delay_msec(100)
		if DirAccess.dir_exists_absolute("/proc/%d" % to_kill):
			OS.execute("kill", PackedStringArray(["-KILL", str(to_kill)]))
