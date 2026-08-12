extends Node

const Files = preload("res://lib/utils/files.gd")
const ModelMeta = preload("res://lib/model/metadata.gd")
const ModelLoader = preload("res://lib/model/formats/model_loader.gd")
const VtModel = preload("res://lib/model/vt_model.gd")

var formats: Dictionary[String, ModelLoader] = {}

var model_cache: Dictionary = {}
signal list_updated(models: Array)

func _ready() -> void:
	formats = {
		"l2d": preload("res://lib/model/formats/l2d/model_loader.gd").new(),
		"vrm": preload("res://lib/model/formats/vrm/model_loader.gd").new(),
	}
	refresh_models.call_deferred()
	add_to_group("system:model")
	
func _get(property: StringName) -> Variant:
	for f in formats.keys():
		if "loader/%s" % [f] == property:
			return formats[f]
	return null

func refresh_models():
	model_cache = {}

	for fmt in formats.values():
		var dir = fmt.model_directory()
		var abs_dir = ProjectSettings.globalize_path(dir)
		if not DirAccess.dir_exists_absolute(abs_dir):
			DirAccess.make_dir_recursive_absolute(abs_dir)
		
		_wrap_loose_model_files(dir, fmt)
		
		var model_folders = DirAccess.get_directories_at(dir)
		for i in model_folders:
			var fp = dir.path_join(i)
			var meta = fmt.load_data(fp)
			if meta:
				model_cache[meta.id] = meta
		
	var models = model_cache.values()
	list_updated.emit(models)
	
	return models

## Move bare model files at the format root into `<basename>/file` so loaders
## that expect a directory can find them (common with manually dropped `.vrm`).
## Live2D packages need sibling assets, so only VRM loose files are wrapped.
func _wrap_loose_model_files(dir: String, fmt: ModelLoader) -> void:
	if fmt.model_format() != &"vrm":
		return
	var ext := fmt.supported_extension()
	for file_name in DirAccess.get_files_at(dir):
		if not file_name.ends_with(ext):
			continue
		var src := dir.path_join(file_name)
		var folder_name := file_name.trim_suffix(ext)
		if folder_name.is_empty():
			folder_name = file_name.get_basename()
		var dest_dir := dir.path_join(folder_name)
		var abs_dest_dir := ProjectSettings.globalize_path(dest_dir)
		if DirAccess.dir_exists_absolute(abs_dest_dir):
			continue
		var err := DirAccess.make_dir_recursive_absolute(abs_dest_dir)
		if err != OK:
			push_warning("Unable to wrap model file %s: %s" % [src, error_string(err)])
			continue
		var dest := dest_dir.path_join(file_name)
		err = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(src),
			ProjectSettings.globalize_path(dest)
		)
		if err != OK:
			push_warning("Unable to move model file %s -> %s: %s" % [src, dest, error_string(err)])

## Import a model file into the correct user directory.
## Returns an empty string on success, or an error message.
func import_model(format: StringName, source_path: String) -> String:
	if not formats.has(String(format)):
		return "Unknown model format: %s" % format
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		return "File not found"
	
	var fmt: ModelLoader = formats[String(format)]
	var ext := fmt.supported_extension()
	if not source_path.get_file().ends_with(ext):
		return "Expected a %s file" % ext
	
	var root_dir := fmt.model_directory()
	var abs_root := ProjectSettings.globalize_path(root_dir)
	if not DirAccess.dir_exists_absolute(abs_root):
		DirAccess.make_dir_recursive_absolute(abs_root)
	
	var err: Error
	var dest_dir: String
	match String(format):
		"vrm":
			var file_name := source_path.get_file()
			var folder_name := file_name.trim_suffix(ext)
			dest_dir = root_dir.path_join(folder_name)
			if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dest_dir)):
				return "A model named '%s' already exists" % folder_name
			err = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest_dir))
			if err != OK:
				return "Unable to create model directory"
			err = DirAccess.copy_absolute(
				ProjectSettings.globalize_path(source_path),
				ProjectSettings.globalize_path(dest_dir.path_join(file_name))
			)
			if err != OK:
				return "Unable to copy VRM file"
		"l2d":
			var package_dir := source_path.get_base_dir()
			var folder_name := package_dir.get_file()
			if folder_name.is_empty():
				return "Unable to determine Live2D package folder"
			dest_dir = root_dir.path_join(folder_name)
			if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dest_dir)):
				return "A model named '%s' already exists" % folder_name
			err = Files.copy_recursive(package_dir, dest_dir)
			if err != OK:
				return "Unable to copy Live2D package"
		_:
			return "Unsupported import format: %s" % format
	
	var meta = fmt.load_data(dest_dir)
	if meta == null:
		return "Imported files, but model metadata could not be loaded"
	
	refresh_models()
	return ""

func make_model(model):
	var data: ModelMeta
	if model in model_cache:
		data = model_cache[model]
	else:
		for fmt in formats.values():
			data = fmt.load_data(model)
			if data != null:
				break
	
	if data == null:
		return
	
	var new_model = preload("./model/vt_model.tscn").instantiate()
	for fmt in formats:
		if data.format == fmt:
			var strategy = formats[fmt].strategy()
			new_model.set_script(strategy)
			new_model.modelmeta = data
			break
	
	var tracking = get_tree().get_first_node_in_group("system:tracking")
	if tracking != null:
		tracking.parameters_updated.connect(new_model.tracking_updated)
	
	new_model.display_name = data.name
	
	return new_model
