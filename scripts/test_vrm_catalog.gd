extends SceneTree

const Catalog = preload("res://lib/model/catalog/model_catalog.gd")

func _initialize() -> void:
	var bundled := Catalog.bundled_at(Catalog.VRM_BUNDLED)
	assert(not bundled.is_empty(), "bundled VRM catalog must parse")
	assert(int(bundled.get("catalog_version", 0)) >= 1)
	var models := Catalog.models_of(bundled)
	assert(models.size() >= 2, "expected official VRM sample entries")
	var ids: Dictionary = {}
	for entry in models:
		assert(entry is Dictionary)
		assert(not String(entry.get("id", "")).is_empty())
		assert(not String(entry.get("name", "")).is_empty())
		assert(not String(entry.get("dest_folder", "")).is_empty())
		assert(not String(entry.get("license_url", "")).is_empty())
		var source: Dictionary = entry.get("source", {})
		assert(source.get("type") in ["github_dir", "zip", "file"])
		if source.get("type") == "file":
			assert(not String(source.get("url", "")).is_empty())
			assert(String(source.get("filename", "")).ends_with(".vrm"))
		ids[entry["id"]] = true
	assert(ids.has("vrm-seed-san"))

	var spec: Dictionary = Catalog.spec_for("vrm")
	assert(String(spec.get("format", "")) == "vrm")
	assert(String(spec.get("required_ext", "")) == ".vrm")
	assert(Catalog.dest_dir_for(&"vrm", "seed-san") == "user://VrmModels/seed-san")

	print("vrm_catalog: all checks passed")
	quit()
