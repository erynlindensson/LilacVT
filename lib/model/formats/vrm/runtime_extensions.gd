extends RefCounted

## godot-vrm's editor plugin registers VRMC_* extensions. That plugin does not
## run in the exported/game process, so VRM 1.0 files imported at runtime would
## otherwise load as plain glTF (no AnimationPlayer, no MToon, no expressions).

static var _registered := false
static var _keep_alive: Array = []

static func ensure_registered() -> void:
	if _registered or Engine.is_editor_hint():
		return
	_registered = true
	var scripts: Array = [
		preload("res://addons/vrm/1.0/VRMC_vrm.gd"),
		preload("res://addons/vrm/1.0/VRMC_node_constraint.gd"),
		preload("res://addons/vrm/1.0/VRMC_springBone.gd"),
		preload("res://addons/vrm/1.0/VRMC_materials_hdr_emissiveMultiplier.gd"),
		preload("res://addons/vrm/1.0/VRMC_materials_mtoon.gd"),
	]
	for script in scripts:
		var extension: GLTFDocumentExtension = script.new()
		_keep_alive.append(extension)
		GLTFDocument.register_gltf_document_extension(extension)

## True when the GLB/VRM JSON advertises the VRM 1.0 document extension.
static func file_uses_vrmc(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	if file.get_buffer(4).get_string_from_ascii() != "glTF":
		return false
	file.get_32()
	file.get_32()
	var chunk_len := file.get_32()
	var chunk_type := file.get_buffer(4).get_string_from_ascii()
	if chunk_type != "JSON":
		return false
	var take: int = mini(chunk_len, 1024 * 1024)
	var json := file.get_buffer(take).get_string_from_utf8()
	return json.contains("\"VRMC_vrm\"")

