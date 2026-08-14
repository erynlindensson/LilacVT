extends SceneTree

## Headless smoke test for model discovery + import.
## Run: godot4-ayagami --headless --path /home/eryn/open-vt -s res://scripts/test_model_import.gd

const Files = preload("res://lib/utils/files.gd")

var _failed := 0

func _initialize() -> void:
	_run.call_deferred()

func _fail(message: String) -> void:
	printerr("FAIL: ", message)
	_failed += 1

func _ok(message: String) -> void:
	print("OK: ", message)

func _run() -> void:
	# Autoloads finish _ready on the first idle frame.
	await process_frame
	await process_frame

	var mm = root.get_node_or_null("/root/ModelManager")
	if mm == null:
		_fail("ModelManager autoload missing")
		quit(1)
		return

	# --- Discovery: wrap bare VRM + scan VrmModels ---
	var models: Array = mm.refresh_models()
	var ids: PackedStringArray = PackedStringArray()
	for meta in models:
		ids.append(meta.id)
		print("  listed: [%s] %s (%s)" % [meta.format, meta.id, meta.path])

	var vrm_dir := ProjectSettings.globalize_path("user://VrmModels")
	var wrapped := "%s/AvatarSample_D_Darkness/AvatarSample_D_Darkness.vrm" % vrm_dir
	if FileAccess.file_exists(wrapped):
		_ok("bare VRM wrapped into folder layout")
	else:
		# may already have been wrapped previously
		if DirAccess.dir_exists_absolute("%s/AvatarSample_D_Darkness" % vrm_dir):
			_ok("VRM folder layout already present")
		else:
			_fail("expected wrapped VRM at %s" % wrapped)

	var found_vrm := false
	for meta in models:
		if meta.format == "vrm" and String(meta.id).begins_with("AvatarSample_D_Darkness"):
			found_vrm = true
			break
	if found_vrm:
		_ok("VRM appears in model list after refresh")
	else:
		_fail("VRM missing from model list: %s" % ", ".join(ids))

	var found_l2d := false
	for meta in models:
		if meta.format == "l2d":
			found_l2d = true
			break
	if found_l2d:
		_ok("Live2D models still listed")
	else:
		_fail("no Live2D models listed")

	# --- Import VRM from a temp copy with a unique name ---
	var src_vrm := wrapped if FileAccess.file_exists(wrapped) else ""
	if src_vrm.is_empty():
		for f in DirAccess.get_files_at("%s/AvatarSample_D_Darkness" % vrm_dir):
			if f.ends_with(".vrm"):
				src_vrm = "%s/AvatarSample_D_Darkness/%s" % [vrm_dir, f]
				break
	if src_vrm.is_empty() or not FileAccess.file_exists(src_vrm):
		_fail("no source VRM available for import test")
	else:
		var tmp_vrm := "/tmp/openvt_import_test_AvatarSample.vrm"
		DirAccess.copy_absolute(src_vrm, tmp_vrm)
		# Ensure clean destination name
		var import_name := "openvt_import_test_AvatarSample"
		var dest := "%s/%s" % [vrm_dir, import_name]
		if DirAccess.dir_exists_absolute(dest):
			_rm_rf(dest)
		var err_msg: String = mm.import_model(&"vrm", tmp_vrm)
		if err_msg.is_empty():
			_ok("import_model(vrm) succeeded")
		else:
			_fail("import_model(vrm): %s" % err_msg)
		if FileAccess.file_exists("%s/%s.vrm" % [dest, import_name]):
			_ok("imported VRM file present on disk")
		else:
			_fail("imported VRM file missing at %s" % dest)
		# cleanup imported test model
		_rm_rf(dest)
		DirAccess.remove_absolute(tmp_vrm)

	# --- Import Live2D package from a temp copy ---
	var haru_src := ProjectSettings.globalize_path("user://Live2DModels/haru")
	if not DirAccess.dir_exists_absolute(haru_src):
		_fail("haru package missing for Live2D import test")
	else:
		var tmp_pkg := "/tmp/openvt_haru_import_test"
		_rm_rf(tmp_pkg)
		var copy_err := Files.copy_recursive(haru_src, tmp_pkg)
		if copy_err != OK:
			_fail("failed to stage Live2D package copy: %s" % error_string(copy_err))
		else:
			var model3 := ""
			for f in DirAccess.get_files_at(tmp_pkg):
				if f.ends_with(".model3.json"):
					model3 = tmp_pkg.path_join(f)
					break
			if model3.is_empty():
				_fail("no .model3.json in staged Live2D package")
			else:
				var l2d_dest := ProjectSettings.globalize_path("user://Live2DModels/openvt_haru_import_test")
				_rm_rf(l2d_dest)
				var err_msg2: String = mm.import_model(&"l2d", model3)
				if err_msg2.is_empty():
					_ok("import_model(l2d) succeeded")
				else:
					_fail("import_model(l2d): %s" % err_msg2)
				if DirAccess.dir_exists_absolute(l2d_dest):
					_ok("imported Live2D package present on disk")
				else:
					_fail("imported Live2D package missing")
				_rm_rf(l2d_dest)
		_rm_rf(tmp_pkg)

	# --- Duplicate import should refuse ---
	if FileAccess.file_exists(src_vrm):
		var err_dup: String = mm.import_model(&"vrm", src_vrm)
		if err_dup.contains("already exists"):
			_ok("duplicate VRM import rejected")
		else:
			_fail("expected duplicate rejection, got: '%s'" % err_dup)

	if _failed == 0:
		print("ALL TESTS PASSED")
		quit(0)
	else:
		printerr("%d TEST(S) FAILED" % _failed)
		quit(1)

func _rm_rf(path: String) -> void:
	var abs := ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(abs):
		for f in DirAccess.get_files_at(abs):
			DirAccess.remove_absolute(abs.path_join(f))
		for d in DirAccess.get_directories_at(abs):
			_rm_rf(abs.path_join(d))
		DirAccess.remove_absolute(abs)
	elif FileAccess.file_exists(abs):
		DirAccess.remove_absolute(abs)
