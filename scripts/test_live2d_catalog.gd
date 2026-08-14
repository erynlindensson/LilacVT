extends SceneTree

const Catalog = preload("res://lib/model/catalog/live2d_catalog.gd")

func _initialize() -> void:
	var bundled := Catalog.bundled_catalog()
	assert(not bundled.is_empty(), "bundled catalog must parse")
	assert(int(bundled.get("catalog_version", 0)) >= 1)
	var models := Catalog.models_of(bundled)
	assert(models.size() >= 8, "expected official sample entries")
	var ids: Dictionary = {}
	for entry in models:
		assert(entry is Dictionary)
		assert(not String(entry.get("id", "")).is_empty())
		assert(not String(entry.get("name", "")).is_empty())
		assert(not String(entry.get("dest_folder", "")).is_empty())
		assert(not String(entry.get("license_url", "")).is_empty())
		var source: Dictionary = entry.get("source", {})
		assert(source.get("type") in ["github_dir", "zip", "file"])
		if source.get("type") == "github_dir":
			assert(not String(source.get("repo", "")).is_empty())
			assert(not String(source.get("path", "")).is_empty())
		else:
			assert(not String(source.get("url", "")).is_empty())
		ids[entry["id"]] = true
	assert(ids.has("live2d-haru"))
	assert(ids.has("live2d-mao"))

	var parsed := Catalog.parse_catalog("{\"catalog_version\":1,\"models\":[]}")
	assert(parsed.get("models") is Array)
	assert(Catalog.parse_catalog("not-json").is_empty())
	assert(Catalog.parse_catalog("[]").is_empty())

	print("live2d_catalog: all checks passed")
	quit()
