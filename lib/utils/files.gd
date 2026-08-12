extends Object
	
static func walk_files(dir: String, extension: String) -> Array[String]:
	var files: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(extension):
			files.append(dir.path_join(f))
		
	for d in DirAccess.get_directories_at(dir):
		files.append_array(walk_files(dir.path_join(d), extension))
	
	return files

## safely parses JSON data from a file
static func read_json(filepath: String) -> Dictionary:
	if not FileAccess.file_exists(filepath):
		return {}

	var file = FileAccess.get_file_as_string(filepath)
	if file.strip_edges().is_empty():
		return {}

	var data = JSON.parse_string(file)
	if data == null:
		push_error("Unable to parse JSON from file: ", filepath)
		return {}
	if not data is Dictionary:
		push_error("Expected a JSON object in file: ", filepath)
		return {}
	return data

## persists data into a readable JSON file
static func write_json(filepath: String, data: Dictionary) -> Error:
	var f = FileAccess.open(filepath, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	
	var out = JSON.stringify(data, "  ")
	f.store_string(out)
	f.close()
	
	return OK

## Recursively copy a file or directory. Paths may be `user://` or absolute.
static func copy_recursive(from: String, to: String) -> Error:
	var src := ProjectSettings.globalize_path(from)
	var dst := ProjectSettings.globalize_path(to)
	if not FileAccess.file_exists(src) and not DirAccess.dir_exists_absolute(src):
		return ERR_FILE_NOT_FOUND
	if DirAccess.dir_exists_absolute(src):
		var err := DirAccess.make_dir_recursive_absolute(dst)
		if err != OK and not DirAccess.dir_exists_absolute(dst):
			return err
		for file_name in DirAccess.get_files_at(src):
			err = DirAccess.copy_absolute(src.path_join(file_name), dst.path_join(file_name))
			if err != OK:
				return err
		for dir_name in DirAccess.get_directories_at(src):
			err = copy_recursive(src.path_join(dir_name), dst.path_join(dir_name))
			if err != OK:
				return err
		return OK
	var parent := dst.get_base_dir()
	var err := DirAccess.make_dir_recursive_absolute(parent)
	if err != OK and not DirAccess.dir_exists_absolute(parent):
		return err
	return DirAccess.copy_absolute(src, dst)
