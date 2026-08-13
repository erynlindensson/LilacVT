extends RefCounted

const Files = preload("res://lib/utils/files.gd")
const L2dLoader = preload("res://lib/model/formats/l2d/model_loader.gd")

const BUNDLED_PATH := "res://lib/model/catalog/live2d_catalog.json"
const REMOTE_URL := "https://raw.githubusercontent.com/erynlindensson/open-vt-lilac/main/lib/model/catalog/live2d_catalog.json"
const LICENSE_PREF := "live2d_sample_license_accepted"
const USER_AGENT := "OpenVT-Lilac/0.1 (https://github.com/erynlindensson/open-vt-lilac)"

static func bundled_catalog() -> Dictionary:
	return Files.read_json(BUNDLED_PATH)

static func parse_catalog(text: String) -> Dictionary:
	var data: Variant = JSON.parse_string(text)
	if data is Dictionary and data.get("models") is Array:
		return data
	return {}

static func models_of(catalog: Dictionary) -> Array:
	var models: Array = catalog.get("models", [])
	if models is Array:
		return models
	return []

static func dest_dir(dest_folder: String) -> String:
	var loader := L2dLoader.new()
	return loader.model_directory().path_join(dest_folder)

static func is_installed(dest_folder: String) -> bool:
	if dest_folder.is_empty():
		return false
	return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dest_dir(dest_folder)))

static func license_accepted() -> bool:
	return bool(Preferences.get_setting(LICENSE_PREF, false))

static func accept_license() -> void:
	Preferences.set_setting(LICENSE_PREF, true)
	Preferences.save_data()
