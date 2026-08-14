extends "res://studio/hud/side_panel.gd"

const Tracker = preload("res://lib/tracking/tracker.gd")
const TrackingSystem = preload("res://lib/tracking/tracking_system.gd")
const CpuFeatures = preload("res://lib/utils/cpu_features.gd")

signal update_bg_color(color: Color)

@onready var tracking_system: TrackingSystem = get_tree().get_first_node_in_group("system:tracking")
@onready var transparency_toggle: CheckButton = %TransparencyToggle
@onready var mic_toggle: CheckButton = %MicrophoneToggle
@onready var face_trackers: OptionButton = %TrackingSource
@onready var fps_option: OptionButton = %FPS
@onready var ui_theme_option: OptionButton = %UITheme

@onready var parameter_list = %ParameterList
@onready var v4l2_stream: VirtualCamera = get_tree().get_first_node_in_group("output:v4l2")

func _get_title():
	return "Settings"

func _ready() -> void:
	_populate_ui_theme_options()
	if OS.has_feature("openseeface") or OS.is_debug_build():
		face_trackers.add_item("OpenSeeFace (Webcam)")
		face_trackers.set_item_metadata(face_trackers.item_count - 1, preload("res://lib/tracking/camera/openseeface/osf_tracker.gd"))
	
	face_trackers.add_item("VTubeStudio (iOS/Android)")
	face_trackers.set_item_metadata(face_trackers.item_count - 1, preload("res://lib/tracking/camera/vts/vts_tracker.gd"))

	# MediaPipe's pip wheel is AVX-only and SIGILLs otherwise. Webcam
	# tracking on those CPUs is OpenSeeFace.
	if CpuFeatures.has_avx():
		face_trackers.add_item("Mediapipe (Experimental)")
		face_trackers.set_item_metadata(face_trackers.item_count - 1, preload("res://lib/tracking/camera/mediapipe/mp_tracker.gd"))
	
	for tracker in tracking_system.get_children():
		var config = tracker.create_config()
		if config != null:
			%Tracking.add_child(config)
	
	Registry.parameter_list_changed.connect(
		func ():
			for c in parameter_list.get_children():
				c.free()
			
			for i in Registry.parameters():
				var box = HBoxContainer.new()
				var l = Label.new()
				l.text = i.id
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				box.add_child(l)
				var v = Label.new()
				v.name = "Value"
				box.add_child(v)
				box.name = i.id
				parameter_list.add_child.call_deferred(box)
	)
		
	if tracking_system:
		tracking_system.tracker_changed.connect(_on_tracker_system_tracker_changed)
		tracking_system.parameters_updated.connect(_on_tracker_system_parameters_updated)
		face_trackers.item_selected.connect(
			func (idx):
				var _tracker = face_trackers.get_item_metadata(idx)
				tracking_system.activate_tracker(_tracker.new())
		)
		
	if OS.has_feature("linux") and v4l2_stream:
		var feeds = v4l2_stream.get_devices()
		
		for feed in feeds:
			%VirtualCameraDevice.add_item(feed.name)
			%VirtualCameraDevice.set_item_metadata(%VirtualCameraDevice.item_count - 1, feed.id)
		if len(feeds) > 0:
			%VirtualCameraDevice.select(0)
		var vp = get_tree().get_first_node_in_group("system:stage").capture_viewport
	else:
		%VirtualWebcam.queue_free()

func _populate_ui_theme_options() -> void:
	ui_theme_option.clear()
	for palette_id in ThemeManager.get_palette_ids():
		var idx := ui_theme_option.item_count
		ui_theme_option.add_item(ThemeManager.get_palette_display_name(palette_id))
		ui_theme_option.set_item_metadata(idx, palette_id)
	_select_ui_theme_option(ThemeManager.active_palette_id)

func _select_ui_theme_option(palette_id: String) -> void:
	for i in range(ui_theme_option.item_count):
		if String(ui_theme_option.get_item_metadata(i)) == palette_id:
			ui_theme_option.select(i)
			return
	if ui_theme_option.item_count > 0:
		ui_theme_option.select(0)

func _on_ui_theme_item_selected(index: int) -> void:
	var palette_id := String(ui_theme_option.get_item_metadata(index))
	ThemeManager.apply_palette(palette_id)
	Preferences.save_data()

func _on_tracker_system_tracker_changed(new_tracker: Tracker) -> void:
	var config = Control.new()
	if new_tracker != null:
		config = new_tracker.create_config()
	config.name = "Config"
	
	%FaceTracking/Config.queue_free()
	await get_tree().process_frame
	%FaceTracking.add_child(config)

func _on_tracker_system_parameters_updated(parameters: Dictionary, _delta) -> void:
	if !is_node_ready():
		return
	for p in Registry.parameters():
		var node = parameter_list.get_node(NodePath(p.id))
		if node == null:
			continue
		node.get_node("Value").text = "%.02f" % parameters.get(p.id, 0)

func _on_preview_background_color_color_changed(color: Color) -> void:
	update_bg_color.emit(color)

func _on_transparency_toggle_toggled(toggled_on: bool) -> void:
	get_tree().get_first_node_in_group("system:stage").toggle_bg(toggled_on)

func load_settings(data: Dictionary):
	transparency_toggle.button_pressed = data.get("window", {}).get("transparent", false)
	var saved_tracker := int(data.get("camera", {}).get("tracking", 0))
	if saved_tracker < 0 or saved_tracker >= face_trackers.item_count:
		saved_tracker = 0
	face_trackers.select(saved_tracker)
	fps_option.select(data.get("window", {}).get("fps", 0))
	_on_fps_value_item_selected(fps_option.get_selected_id())
	var palette_id := String(data.get("ui", {}).get("palette", ThemeManager.DEFAULT_PALETTE))
	ThemeManager.apply_palette(palette_id)
	_select_ui_theme_option(ThemeManager.active_palette_id)
	if tracking_system:
		var tracker_script: Variant = face_trackers.get_selected_metadata()
		if tracker_script != null:
			tracking_system.activate_tracker(tracker_script.new())
		mic_toggle.button_pressed = data.get("microphone", true)
		_apply_osf_smoothing(data)
	
func save_settings(data: Dictionary):
	var w = data.get("window", {})
	w["transparent"] = transparency_toggle.button_pressed
	w["fps"] = fps_option.get_selected_id()
	var c = data.get("camera", {})
	c["tracking"] = face_trackers.get_selected_id()
	c["osf_smoothing"] = _osf_smoothing_value()
	var ui = data.get("ui", {})
	ui["palette"] = ThemeManager.active_palette_id
	data["window"] = w
	data["camera"] = c
	data["ui"] = ui
	data["microphone"] = mic_toggle.button_pressed

func _osf_smoothing_value() -> float:
	if tracking_system == null:
		return 0.45
	var tracker = tracking_system.get_node_or_null("FaceTracker")
	if tracker != null and "tracking_smoothing" in tracker:
		return float(tracker.tracking_smoothing)
	return float(Preferences.get_setting("camera.osf_smoothing", 0.45))

func _apply_osf_smoothing(data: Dictionary) -> void:
	if tracking_system == null:
		return
	var tracker = tracking_system.get_node_or_null("FaceTracker")
	if tracker == null or not ("tracking_smoothing" in tracker):
		return
	tracker.tracking_smoothing = float(data.get("camera", {}).get("osf_smoothing", 0.45))

func _on_fps_value_item_selected(index: int) -> void:
	match index:
		0: # 60 FPS
			Engine.max_fps = 60
		1: # 30 FPS
			Engine.max_fps = 30
		_: # Uncapped
			Engine.max_fps = 0

func _on_microphone_toggle_toggled(toggled_on: bool) -> void:
	if not tracking_system:
		return
	tracking_system.get_node("MicrophoneTracker").enabled = toggled_on

func _on_loopback_item_selected(index: int) -> void:
	_on_v4l2_toggled(%V4L2Toggle.button_pressed)

func _on_v4l2_toggled(toggled_on: bool) -> void:
	if toggled_on:
		var index = %VirtualCameraDevice.selected
		if index >= 0:
			var device_id: String = %VirtualCameraDevice.get_item_metadata(index)
			v4l2_stream.loopback_device = device_id
			return
	v4l2_stream.loopback_device = ""
