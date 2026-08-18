extends SceneTree

func _init() -> void:
	var p := "res://LICENSE.txt"
	print("exists=", FileAccess.file_exists(p))
	var t := FileAccess.get_file_as_string(p)
	print("len=", t.length())
	if t.length() > 0:
		print("head=", t.substr(0, min(120, t.length())))
	else:
		printerr("FAIL: LICENSE.txt empty or missing")
		quit(1)
		return
	print("license_txt_ok")
	quit(0)
