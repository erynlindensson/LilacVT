extends RefCounted

## Manages the bundled MediaPipe Face Landmarker child process.

const CpuFeatures := preload("res://lib/utils/cpu_features.gd")

const ROOT_REL := "res://thirdparty/mediapipe"
const SETUP_HINT := "MediaPipe is not set up. OpenVT will try to install it automatically, or run scripts/setup_mediapipe.sh"
const NO_AVX_HINT := "This CPU has no AVX. MediaPipe is unavailable; use OpenSeeFace."

var pid: int = -1
var last_error: String = ""
var _setup_attempted: bool = false

func is_running() -> bool:
	if pid <= 0:
		return false
	if DirAccess.dir_exists_absolute("/proc/%d" % pid):
		return true
	pid = -1
	return false

func install_root() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").rstrip("/")
	return OS.get_executable_path().get_base_dir()

func root_dir() -> String:
	var beside := install_root().path_join("thirdparty/mediapipe")
	if FileAccess.file_exists(beside.path_join("facetracker.py")):
		return beside
	var from_res := ProjectSettings.globalize_path(ROOT_REL)
	if FileAccess.file_exists(from_res.path_join("facetracker.py")):
		return from_res
	return beside

func setup_script_path() -> String:
	var beside := install_root().path_join("scripts/setup_mediapipe.sh")
	if FileAccess.file_exists(beside):
		return beside
	var from_res := ProjectSettings.globalize_path("res://scripts/setup_mediapipe.sh")
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

func model_path() -> String:
	return root_dir().path_join("models/face_landmarker.task")

func has_sources() -> bool:
	return FileAccess.file_exists(root_dir().path_join("facetracker.py"))

func has_venv() -> bool:
	return not python_path().is_empty()

func has_model() -> bool:
	return FileAccess.file_exists(model_path())

func is_ready() -> bool:
	if not CpuFeatures.has_avx():
		last_error = NO_AVX_HINT
		return false
	if not has_sources():
		last_error = SETUP_HINT
		return false
	if not has_venv() or not has_model():
		last_error = SETUP_HINT
		return false
	last_error = ""
	return true

func ensure_setup(show_toast: bool = true) -> bool:
	if not CpuFeatures.has_avx():
		last_error = NO_AVX_HINT
		return false
	if is_ready():
		return true
	if not has_sources():
		last_error = "MediaPipe tracker is missing from this install (expected thirdparty/mediapipe next to the app)."
		return false
	if _setup_attempted:
		return is_ready()
	_setup_attempted = true

	var script := setup_script_path()
	if script.is_empty():
		last_error = "MediaPipe setup script missing (expected scripts/setup_mediapipe.sh)."
		return false

	if show_toast:
		_alert("Setting up MediaPipe (one-time install, may take a minute)…")

	var output: Array = []
	var code := OS.execute("bash", PackedStringArray([script]), output, true, false)
	if code != 0:
		last_error = "MediaPipe setup failed (exit %d). Need python3 + python3-venv and network. Output: %s" % [
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
		_alert("MediaPipe is ready. Use Start Tracking in Camera settings.")
	return true

func start(port: int = 11574, camera_id: int = 0) -> bool:
	if is_running():
		return true

	if not CpuFeatures.has_avx():
		last_error = NO_AVX_HINT
		return false

	if not ensure_setup(true):
		return false

	var py := python_path()
	if py.is_empty():
		last_error = SETUP_HINT
		return false

	var script := root_dir().path_join("facetracker.py")
	var args: PackedStringArray = [
		script,
		"-i", "127.0.0.1",
		"-p", str(port),
		"-c", str(camera_id),
		"-W", "1280",
		"-H", "720",
		"--model", model_path(),
	]
	if not OS.is_debug_build():
		args.append_array(PackedStringArray(["--silent", "1"]))

	pid = OS.create_process(py, args, false)
	if pid <= 0:
		last_error = "Failed to start MediaPipe (%s). %s" % [py, SETUP_HINT]
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
