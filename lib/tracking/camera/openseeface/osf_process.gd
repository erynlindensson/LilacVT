extends RefCounted

## Manages the bundled OpenSeeFace facetracker.py child process.
## Release builds resolve OSF next to the executable (not inside the PCK).

const ROOT_REL := "res://thirdparty/openseeface"
const SETUP_HINT := "OpenSeeFace is not set up. OpenVT will try to install it automatically, or run scripts/setup_openseeface.sh"

var pid: int = -1
var last_error: String = ""
var _setup_attempted: bool = false

func is_running() -> bool:
	if pid <= 0:
		return false
	# Prefer /proc on Linux so we don't trip Godot's child-only PID checks
	# after the process has already exited.
	if DirAccess.dir_exists_absolute("/proc/%d" % pid):
		return true
	pid = -1
	return false

## Directory containing the shipped binary (release) or project root (editor).
func install_root() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").rstrip("/")
	return OS.get_executable_path().get_base_dir()

func root_dir() -> String:
	var beside := install_root().path_join("thirdparty/openseeface")
	if FileAccess.file_exists(beside.path_join("facetracker.py")):
		return beside
	var from_res := ProjectSettings.globalize_path(ROOT_REL)
	if FileAccess.file_exists(from_res.path_join("facetracker.py")):
		return from_res
	return beside

func setup_script_path() -> String:
	var beside := install_root().path_join("scripts/setup_openseeface.sh")
	if FileAccess.file_exists(beside):
		return beside
	var from_res := ProjectSettings.globalize_path("res://scripts/setup_openseeface.sh")
	if FileAccess.file_exists(from_res):
		return from_res
	return ""

func python_path() -> String:
	var venv_python := root_dir().path_join(".venv/bin/python")
	if FileAccess.file_exists(venv_python):
		return venv_python
	var venv_win := root_dir().path_join(".venv/Scripts/python.exe")
	if FileAccess.file_exists(venv_win):
		return venv_win
	return ""

func has_sources() -> bool:
	var root := root_dir()
	return (
		FileAccess.file_exists(root.path_join("facetracker.py"))
		and DirAccess.dir_exists_absolute(root.path_join("models"))
	)

func has_venv() -> bool:
	return not python_path().is_empty()

func is_ready() -> bool:
	if not has_sources():
		last_error = SETUP_HINT
		return false
	if not has_venv():
		last_error = SETUP_HINT
		return false
	last_error = ""
	return true

## Create the OSF venv once if missing. Safe to call on every startup.
func ensure_setup(show_toast: bool = true) -> bool:
	if is_ready():
		return true
	if not has_sources():
		last_error = "OpenSeeFace files are missing from this install (expected thirdparty/openseeface next to the app)."
		return false
	if has_venv():
		return true
	if _setup_attempted:
		return is_ready()
	_setup_attempted = true

	var script := setup_script_path()
	if script.is_empty():
		last_error = "OpenSeeFace setup script missing (expected scripts/setup_openseeface.sh)."
		return false

	if show_toast:
		_alert("Setting up OpenSeeFace (one-time install, may take a minute)…")

	var output: Array = []
	var code := OS.execute("bash", PackedStringArray([script]), output, true, false)
	if code != 0:
		last_error = "OpenSeeFace setup failed (exit %d). Need python3 + python3-venv. Output: %s" % [
			code,
			"\n".join(PackedStringArray(output)).substr(0, 400)
		]
		if show_toast:
			_alert(last_error)
		return false

	if not is_ready():
		last_error = SETUP_HINT
		if show_toast:
			_alert(last_error)
		return false

	if show_toast:
		_alert("OpenSeeFace is ready. Use Start Tracking in Camera settings.")
	return true

func start(port: int = 11573, camera_id: int = 0) -> bool:
	if is_running():
		return true

	if not ensure_setup(true):
		return false

	var py := python_path()
	if py.is_empty():
		last_error = SETUP_HINT
		return false

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

func _alert(message: String) -> void:
	if message.is_empty():
		return
	push_warning(message)
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var toast = tree.get_first_node_in_group("system:alert")
	if toast:
		toast.alert(message)
