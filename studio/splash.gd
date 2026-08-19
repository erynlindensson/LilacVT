extends CanvasLayer
class_name StudioSplash
## Startup splash screen controller with asynchronous threaded scene loading,
## model initialization synchronization, and live progress bar feedback.

signal loading_completed

@onready var color_rect: ColorRect = $ColorRect
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var status_label: Label = %StatusLabel
@onready var percent_label: Label = %PercentLabel

const Files = preload("res://lib/utils/files.gd")
const TARGET_SCENE_PATH := "res://studio/studio.tscn"
const USER_SETTINGS := "user://settings.json"

var _current_progress: float = 0.0
var _is_transitioning: bool = false
var _loaded_scene: PackedScene

func _ready() -> void:
	_apply_styles()
	_update_ui(0.0)
	if status_label != null:
		status_label.text = "Starting LilacVT..."

	if get_tree() != null and get_tree().current_scene == self:
		if DisplayServer.get_name() == "headless":
			_load_sync_and_switch.call_deferred()
			return

		var err := ResourceLoader.load_threaded_request(TARGET_SCENE_PATH, "PackedScene")
		if err != OK:
			push_warning("Failed to start threaded loading for %s: %s" % [TARGET_SCENE_PATH, error_string(err)])
			_load_sync_and_switch.call_deferred()

func _apply_styles() -> void:
	if progress_bar == null:
		return

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.12, 0.10, 0.16, 0.85)
	bg_style.corner_radius_top_left = 6
	bg_style.corner_radius_top_right = 6
	bg_style.corner_radius_bottom_left = 6
	bg_style.corner_radius_bottom_right = 6
	bg_style.border_width_left = 1
	bg_style.border_width_top = 1
	bg_style.border_width_right = 1
	bg_style.border_width_bottom = 1
	bg_style.border_color = Color(0.35, 0.30, 0.45, 0.6)
	bg_style.content_margin_top = 2
	bg_style.content_margin_bottom = 2
	bg_style.content_margin_left = 2
	bg_style.content_margin_right = 2

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.71, 0.58, 0.88, 0.95)
	fill_style.corner_radius_top_left = 5
	fill_style.corner_radius_top_right = 5
	fill_style.corner_radius_bottom_left = 5
	fill_style.corner_radius_bottom_right = 5

	progress_bar.add_theme_stylebox_override("background", bg_style)
	progress_bar.add_theme_stylebox_override("fill", fill_style)

func _process(_delta: float) -> void:
	if _is_transitioning:
		return

	var progress_arr: Array = []
	var status := ResourceLoader.load_threaded_get_status(TARGET_SCENE_PATH, progress_arr)

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			# Map scene bytecode loading to 0% - 60% of total boot progress
			var raw_pct: float = progress_arr[0] if not progress_arr.is_empty() else 0.0
			var mapped_pct := raw_pct * 60.0
			var target := maxf(_current_progress, mapped_pct)
			_smooth_step_to(target, "Loading studio interface...")
		ResourceLoader.THREAD_LOAD_LOADED:
			_loaded_scene = ResourceLoader.load_threaded_get(TARGET_SCENE_PATH) as PackedScene
			_is_transitioning = true
			_instantiate_and_wait_for_ready()
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("Threaded loading failed for %s" % TARGET_SCENE_PATH)
			_load_sync_and_switch()

func _smooth_step_to(target: float, status_msg: String) -> void:
	if not status_msg.is_empty() and status_label != null:
		status_label.text = status_msg
	_update_ui(lerpf(_current_progress, target, 0.3))

func _instantiate_and_wait_for_ready() -> void:
	_update_ui(65.0)
	if status_label != null:
		status_label.text = "Initializing studio..."

	var studio_node: Node = _loaded_scene.instantiate()
	get_tree().root.add_child(studio_node)
	get_tree().current_scene = studio_node

	# Let the studio node enter the tree and run _ready() and Preferences.load_data()
	await get_tree().process_frame
	await get_tree().process_frame

	_update_ui(75.0)
	if status_label != null:
		status_label.text = "Loading model and settings..."

	var stage = get_tree().get_first_node_in_group("system:stage")
	var prefs := Files.read_json(USER_SETTINGS)
	var has_saved_model: bool = not String(prefs.get("active_model", "")).is_empty()

	if stage != null and has_saved_model and stage.active_model == null:
		_update_ui(85.0)
		if status_label != null:
			status_label.text = "Loading avatar model..."

		var model_loaded := [false]
		var on_model_changed := func(_m): model_loaded[0] = true
		stage.model_changed.connect(on_model_changed)
		var wait_start := Time.get_ticks_msec()
		while not model_loaded[0] and (Time.get_ticks_msec() - wait_start < 8000):
			await get_tree().process_frame
			if stage.active_model != null:
				break
		if stage.model_changed.is_connected(on_model_changed):
			stage.model_changed.disconnect(on_model_changed)

	_update_ui(95.0)
	if status_label != null:
		status_label.text = "Rendering interface..."

	# Ensure the full scene has completed draw calls to the screen buffer
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	_update_ui(100.0)
	if status_label != null:
		status_label.text = "Ready"

	loading_completed.emit()

	if DisplayServer.get_name() == "headless":
		queue_free()
		return

	var t := create_tween()
	t.tween_property(color_rect, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(queue_free)

func _load_sync_and_switch() -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_update_ui(100.0)
	loading_completed.emit()
	if get_tree() != null and get_tree().current_scene == self:
		get_tree().change_scene_to_file.call_deferred(TARGET_SCENE_PATH)
	else:
		queue_free()

func _update_ui(pct: float) -> void:
	_current_progress = clampf(pct, 0.0, 100.0)
	if progress_bar != null:
		progress_bar.value = _current_progress
	if percent_label != null:
		percent_label.text = "%d%%" % int(_current_progress)

func set_progress(val: float, status: String = "", _duration: float = 0.0) -> void:
	if not status.is_empty() and status_label != null:
		status_label.text = status
	_update_ui(val * 100.0)

func complete_and_fade(_duration: float = 0.0) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_update_ui(100.0)
	loading_completed.emit()
	queue_free()
