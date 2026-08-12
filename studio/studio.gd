extends Node

const OsfProcess = preload("res://lib/tracking/camera/openseeface/osf_process.gd")

func _ready() -> void:
	Preferences.load_data.call_deferred()
	if not Engine.is_embedded_in_editor():
		get_window().borderless = false
		
	DisplayServer.window_set_min_size(Vector2i(540,360), 0)
	
	await RenderingServer.frame_post_draw
	_ensure_openseeface_setup.call_deferred()

## One-time OSF venv install for release layouts that ship thirdparty/openseeface.
func _ensure_openseeface_setup() -> void:
	if OS.has_feature("editor"):
		return
	# Linux export enables the openseeface custom feature; also run whenever
	# the release layout is present next to the binary.
	var osf := OsfProcess.new()
	if not osf.has_sources():
		return
	if osf.is_ready():
		return
	osf.ensure_setup(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Preferences.save_data()

func save_settings(settings: Dictionary):
	var window_settings = settings.get("window", {})
	window_settings["position"] = get_window().position
	window_settings["size"] = get_window().size
	settings["window"] = window_settings
	
func load_settings(_settings: Dictionary):
	pass
	# var window_prefs = settings.get("window", {})
	
	#var size = Vector2i(window_prefs.get("size", Vector2i(
	#	ProjectSettings.get_setting("display/window/size/viewport_width"),
	#	ProjectSettings.get_setting("display/window/size/viewport_height")
	#)))
	#get_window().size = size
	#await get_tree().process_frame
	#get_window().move_to_center()
