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

func _on_import_live2d_button_pressed() -> void:
	_import_format = &"l2d"
	file_dialog.title = "Import Live2D Model"
	file_dialog.clear_filters()
	file_dialog.add_filter("*.model3.json", "Live2D Model")
	file_dialog.popup_centered_ratio(0.7)

func _on_import_vrm_button_pressed() -> void:
	_import_format = &"vrm"
	file_dialog.title = "Import VRM Model"
	file_dialog.clear_filters()
	file_dialog.add_filter("*.vrm", "VRM Model")
	file_dialog.popup_centered_ratio(0.7)

func _on_import_file_selected(path: String) -> void:
	var error_message := ModelManager.import_model(_import_format, path)
	if error_message.is_empty():
		_alert("Model imported")
		setup()
	else:
		_alert(error_message)
