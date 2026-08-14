extends RefCounted

const Files = preload("res://lib/utils/files.gd")

const USER_AGENT := "OpenVT-Lilac/0.1 (https://github.com/erynlindensson/open-vt-lilac)"

const LIVE2D_BUNDLED := "res://lib/model/catalog/live2d_catalog.json"
const LIVE2D_REMOTE := "https://raw.githubusercontent.com/erynlindensson/open-vt-lilac/main/lib/model/catalog/live2d_catalog.json"
const LIVE2D_LICENSE_PREF := "live2d_sample_license_accepted"

const VRM_BUNDLED := "res://lib/model/catalog/vrm_catalog.json"
const VRM_REMOTE := "https://raw.githubusercontent.com/erynlindensson/open-vt-lilac/main/lib/model/catalog/vrm_catalog.json"
const VRM_LICENSE_PREF := "vrm_sample_license_accepted"

static func spec_for(kind: String) -> Dictionary:
	match kind:
		"vrm":
			return {
				"kind": "vrm",
				"title": "Free VRM Models",
				"bundled_path": VRM_BUNDLED,
				"remote_url": VRM_REMOTE,
				"license_pref": VRM_LICENSE_PREF,
				"format": &"vrm",
				"required_ext": ".vrm",
				"license_url": "https://vrm.dev/en/licenses/1.0/",
				"terms_url": "https://github.com/vrm-c/vrm-specification/tree/master/samples",
				"dialog_title": "VRM Sample License",
				"dialog_text": "Official VRM sample models are distributed under the VRM Public License 1.0. You must agree before downloading.",
				"license_link_text": "VRM Public License 1.0",
				"terms_link_text": "VRM specification sample models",
			}
		_:
			return {
				"kind": "l2d",
				"title": "Free Live2D Models",
				"bundled_path": LIVE2D_BUNDLED,
				"remote_url": LIVE2D_REMOTE,
				"license_pref": LIVE2D_LICENSE_PREF,
				"format": &"l2d",
				"required_ext": ".model3.json",
				"license_url": "https://www.live2d.com/eula/live2d-free-material-license-agreement_en.html",
				"terms_url": "https://www.live2d.com/en/learn/sample/",
				"dialog_title": "Live2D Sample License",
				"dialog_text": "Official Live2D sample models are free for learning and testing under Live2D’s Free Material License and Sample Data Terms of Use. You must agree before downloading.",
				"license_link_text": "Free Material License Agreement",
				"terms_link_text": "Cubism Sample Data Terms of Use",
			}

static func bundled_at(path: String) -> Dictionary:
	return Files.read_json(path)

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

static func dest_dir_for(format: StringName, dest_folder: String) -> String:
	var root := "user://VrmModels" if format == &"vrm" else "user://Live2DModels"
	return root.path_join(dest_folder)

static func is_installed(format: StringName, dest_folder: String) -> bool:
	if dest_folder.is_empty():
		return false
	return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dest_dir_for(format, dest_folder)))
