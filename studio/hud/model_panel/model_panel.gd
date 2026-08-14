extends "res://studio/hud/side_panel.gd"

const Stage = preload("res://studio/stage/stage.gd")
const Preview = preload("./model_selector.tscn")

@onready var stage: Stage = get_tree().get_first_node_in_group(Stage.GROUP_NAME)
@onready var list = %ModelList
@onready var file_dialog: FileDialog = %ImportFileDialog

var _import_format: StringName = &""

func teardown():
	for f in list.get_children():
		f.queue_free()

func setup():
	var models = ModelManager.refresh_models()
	
	for f in list.get_children():
		f.queue_free()
	
	for i in models:
		var btn = Preview.instantiate()
		btn.model = i
		btn.pressed.connect(
			func ():
				var model = ModelManager.make_model(i.id)
				stage.spawn_model(model)
		)
		list.add_child(btn)

func _alert(message: String) -> void:
	var toast = get_tree().get_first_node_in_group("system:alert")
	if toast:
		toast.alert(message)

func _on_directory_button_pressed() -> void:
	OS.shell_open(ProjectSettings.globalize_path("user://"))

func _on_import_file_selected(path: String) -> void:
	var format: StringName = _import_format
	if format == &"auto" or format == &"":
		if path.ends_with(".vrm"):
			format = &"vrm"
		elif path.ends_with(".model3.json"):
			format = &"l2d"
		else:
			_alert("Unsupported model file")
			return
	var error_message := ModelManager.import_model(format, path)
	var already := error_message.begins_with("A model named")
	if error_message.is_empty() or already:
		if already:
			_alert(error_message)
		else:
			_alert("Model imported")
		setup()
		_spawn_from_import(format, path)
	else:
		_alert(error_message)

func _spawn_from_import(format: StringName, source_path: String) -> void:
	if not ModelManager.formats.has(String(format)):
		return
	var fmt = ModelManager.formats[String(format)]
	var dest_dir: String
	if String(format) == "vrm":
		dest_dir = fmt.model_directory().path_join(
			source_path.get_file().trim_suffix(fmt.supported_extension())
		)
	else:
		dest_dir = fmt.model_directory().path_join(source_path.get_base_dir().get_file())
	var meta = fmt.load_data(dest_dir)
	if meta == null:
		return
	ModelManager.refresh_models()
	var model = ModelManager.make_model(meta.id)
	if model:
		stage.spawn_model(model)

func _on_open_file_button_pressed() -> void:
	_import_format = &"auto"
	file_dialog.title = "Open Model File"
	file_dialog.clear_filters()
	file_dialog.add_filter("*.model3.json", "Live2D Model")
	file_dialog.add_filter("*.vrm", "VRM Model")
	file_dialog.popup_centered_ratio(0.7)

func _on_browse_live2d_button_pressed() -> void:
	_open_catalog_browser("l2d")

func _on_browse_vrm_button_pressed() -> void:
	_open_catalog_browser("vrm")

func _open_catalog_browser(kind: String) -> void:
	var browser = preload("res://studio/hud/model_panel/live2d_browser/live2d_browser.tscn").instantiate()
	browser.kind = kind
	browser.model_imported.connect(setup)
	add_child(browser)
	browser.popup_centered()

