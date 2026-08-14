extends RefCounted

const ModelCatalog = preload("res://lib/model/catalog/model_catalog.gd")

const BUNDLED_PATH := ModelCatalog.LIVE2D_BUNDLED
const REMOTE_URL := ModelCatalog.LIVE2D_REMOTE
const LICENSE_PREF := ModelCatalog.LIVE2D_LICENSE_PREF
const USER_AGENT := ModelCatalog.USER_AGENT

static func bundled_catalog() -> Dictionary:
	return ModelCatalog.bundled_at(BUNDLED_PATH)

static func parse_catalog(text: String) -> Dictionary:
	return ModelCatalog.parse_catalog(text)

static func models_of(catalog: Dictionary) -> Array:
	return ModelCatalog.models_of(catalog)

static func dest_dir(dest_folder: String) -> String:
	return ModelCatalog.dest_dir_for(&"l2d", dest_folder)

static func is_installed(dest_folder: String) -> bool:
	return ModelCatalog.is_installed(&"l2d", dest_folder)

