extends Node

const Catalog = preload("res://lib/model/catalog/live2d_catalog.gd")
const Files = preload("res://lib/utils/files.gd")

signal progress(current: int, total: int, message: String)

const USER_AGENT := Catalog.USER_AGENT

var _http: HTTPRequest

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 60.0
	_http.use_threads = true
	add_child(_http)

func load_catalog() -> Dictionary:
	progress.emit(0, 1, "Loading catalog…")
	var remote := await _request_text(Catalog.REMOTE_URL, [])
	if not remote.is_empty():
		var parsed := Catalog.parse_catalog(remote)
		if not parsed.is_empty():
			progress.emit(1, 1, "Catalog loaded")
			return parsed
	progress.emit(1, 1, "Using bundled catalog")
	return Catalog.bundled_catalog()

func download_model(entry: Dictionary) -> String:
	var dest_folder := String(entry.get("dest_folder", "")).strip_edges()
	if dest_folder.is_empty():
		return "Catalog entry is missing dest_folder"
	if Catalog.is_installed(dest_folder):
		return "A model named '%s' already exists" % dest_folder
	var source: Dictionary = entry.get("source", {})
	if source.is_empty():
		return "Catalog entry is missing source"
	match String(source.get("type", "")):
		"github_dir":
			return await _download_github_dir(source, dest_folder)
		"zip":
			return await _download_zip(source, dest_folder)
		_:
			return "Unsupported source type: %s" % source.get("type", "")

func fetch_preview(url: String) -> Texture2D:
	if url.is_empty():
		return null
	var body := await _request_bytes(url, [])
	if body.is_empty():
		return null
	var img := Image.new()
	var err := img.load_png_from_buffer(body)
	if err != OK:
		err = img.load_jpg_from_buffer(body)
	if err != OK:
		err = img.load_webp_from_buffer(body)
	if err != OK:
		return null
	return ImageTexture.create_from_image(img)

func _download_github_dir(source: Dictionary, dest_folder: String) -> String:
	var repo := String(source.get("repo", ""))
	var path := String(source.get("path", "")).trim_prefix("/").trim_suffix("/")
	var ref := String(source.get("ref", "develop"))
	if repo.is_empty() or path.is_empty():
		return "github_dir source needs repo and path"
	progress.emit(0, 1, "Listing %s…" % dest_folder)
	var files := await _list_github_files(repo, path, ref)
	if files.is_empty():
		return "No files found at %s/%s" % [repo, path]
	var dest := Catalog.dest_dir(dest_folder)
	var abs_dest := ProjectSettings.globalize_path(dest)
	var err := DirAccess.make_dir_recursive_absolute(abs_dest)
	if err != OK:
		return "Unable to create model directory"
	var total := files.size()
	var done := 0
	for file_path in files:
		done += 1
		progress.emit(done, total, "Downloading %d/%d" % [done, total])
		var rel := file_path.trim_prefix(path).trim_prefix("/")
		if rel.is_empty() or rel.ends_with("/"):
			continue
		var cdn := "https://cdn.jsdelivr.net/gh/%s@%s/%s" % [repo, ref, file_path]
		var body := await _request_bytes(cdn, [])
		if body.is_empty():
			_remove_dir(abs_dest)
			return "Failed to download %s" % rel
		var out_path := dest.path_join(rel)
		var abs_out := ProjectSettings.globalize_path(out_path)
		err = DirAccess.make_dir_recursive_absolute(abs_out.get_base_dir())
		if err != OK and not DirAccess.dir_exists_absolute(abs_out.get_base_dir()):
			_remove_dir(abs_dest)
			return "Unable to write %s" % rel
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		if file == null:
			_remove_dir(abs_dest)
			return "Unable to write %s" % rel
		file.store_buffer(body)
		file.close()
	if Files.walk_files(dest, ".model3.json").is_empty():
		_remove_dir(abs_dest)
		return "Download finished, but no .model3.json was found"
	progress.emit(total, total, "Installed %s" % dest_folder)
	return ""

func _list_github_files(repo: String, path: String, ref: String) -> PackedStringArray:
	var url := "https://api.github.com/repos/%s/contents/%s?ref=%s" % [repo, path, ref]
	var text := await _request_text(url, _github_headers())
	var parsed: Variant = JSON.parse_string(text)
	var files: PackedStringArray = PackedStringArray()
	if parsed is Array:
		for item in parsed:
			if not item is Dictionary:
				continue
			var item_path := String(item.get("path", ""))
			var item_type := String(item.get("type", ""))
			if item_type == "file" and not item_path.is_empty():
				files.append(item_path)
			elif item_type == "dir" and not item_path.is_empty():
				files.append_array(await _list_github_files(repo, item_path, ref))
	return files

func _download_zip(source: Dictionary, dest_folder: String) -> String:
	var zip_url := String(source.get("url", ""))
	if zip_url.is_empty():
		return "zip source needs url"
	progress.emit(0, 1, "Downloading archive…")
	var body := await _request_bytes(zip_url, [])
	if body.is_empty():
		return "Failed to download zip"
	var cache_dir := ProjectSettings.globalize_path("user://.cache/live2d_browser")
	DirAccess.make_dir_recursive_absolute(cache_dir)
	var zip_path := cache_dir.path_join("download.zip")
	var zip_file := FileAccess.open(zip_path, FileAccess.WRITE)
	if zip_file == null:
		return "Unable to cache zip"
	zip_file.store_buffer(body)
	zip_file.close()
	var extract_dir := cache_dir.path_join("extract")
	_remove_dir(extract_dir)
	DirAccess.make_dir_recursive_absolute(extract_dir)
	var extract_err := _extract_zip(zip_path, extract_dir, String(source.get("strip_prefix", "")))
	DirAccess.remove_absolute(zip_path)
	if extract_err != OK:
		_remove_dir(extract_dir)
		return "Unable to extract zip"
	var model_files := Files.walk_files(extract_dir, ".model3.json")
	if model_files.is_empty():
		_remove_dir(extract_dir)
		return "Zip did not contain a .model3.json"
	var package_dir := model_files[0].get_base_dir()
	for candidate in model_files:
		if candidate.get_base_dir().count("/") < package_dir.count("/"):
			package_dir = candidate.get_base_dir()
	var dest := Catalog.dest_dir(dest_folder)
	if Catalog.is_installed(dest_folder):
		_remove_dir(extract_dir)
		return "A model named '%s' already exists" % dest_folder
	var copy_err := Files.copy_recursive(package_dir, dest)
	_remove_dir(extract_dir)
	if copy_err != OK:
		return "Unable to copy extracted model"
	progress.emit(1, 1, "Installed %s" % dest_folder)
	return ""

func _extract_zip(zip_path: String, dest_dir: String, strip_prefix: String) -> Error:
	var reader := ZIPReader.new()
	var err := reader.open(zip_path)
	if err != OK:
		return err
	var prefix := strip_prefix.trim_prefix("/").trim_suffix("/")
	if not prefix.is_empty():
		prefix += "/"
	for inner in reader.get_files():
		var name := String(inner).replace("\\", "/")
		if name.ends_with("/"):
			continue
		if not prefix.is_empty():
			if not name.begins_with(prefix):
				continue
			name = name.trim_prefix(prefix)
		if name.is_empty():
			continue
		var out_path := dest_dir.path_join(name)
		err = DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		if err != OK and not DirAccess.dir_exists_absolute(out_path.get_base_dir()):
			reader.close()
			return err
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		if file == null:
			reader.close()
			return FileAccess.get_open_error()
		file.store_buffer(reader.read_file(inner))
		file.close()
	reader.close()
	return OK

func _github_headers() -> PackedStringArray:
	return PackedStringArray([
		"User-Agent: %s" % USER_AGENT,
		"Accept: application/vnd.github+json",
	])

func _request_text(url: String, headers: PackedStringArray) -> String:
	var body := await _request_bytes(url, headers)
	if body.is_empty():
		return ""
	return body.get_string_from_utf8()

func _request_bytes(url: String, headers: PackedStringArray) -> PackedByteArray:
	var req_headers := headers.duplicate()
	if req_headers.is_empty():
		req_headers = PackedStringArray(["User-Agent: %s" % USER_AGENT])
	var err := _http.request(url, req_headers)
	if err != OK:
		push_warning("HTTP request failed to start: %s (%s)" % [url, error_string(err)])
		return PackedByteArray()
	var completed: Array = await _http.request_completed
	var result: int = completed[0]
	var code: int = completed[1]
	var body: PackedByteArray = completed[3]
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		push_warning("HTTP %s failed: result=%s code=%s" % [url, result, code])
		return PackedByteArray()
	return body

func _remove_dir(abs_path: String) -> void:
	if abs_path.is_empty() or not DirAccess.dir_exists_absolute(abs_path):
		return
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return
	for file_name in dir.get_files():
		dir.remove(file_name)
	for dir_name in dir.get_directories():
		_remove_dir(abs_path.path_join(dir_name))
	DirAccess.remove_absolute(abs_path)
