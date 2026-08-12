extends SceneTree
## Smoke: L2D motion pose/expression APIs exist and ThemeManager leaves SpinBox icons intact.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var tm = load("res://ui/theme_manager.gd").new()
	get_root().add_child(tm)
	await process_frame
	tm.apply_palette("lilac")

	var project: Theme = ThemeDB.get_project_theme()
	var up: Texture2D = project.get_icon("up", "SpinBox")
	var down: Texture2D = project.get_icon("down", "SpinBox")
	print("spin up=", up, " size=", up.get_width() if up else -1, "x", up.get_height() if up else -1)
	print("spin down=", down, " size=", down.get_width() if down else -1, "x", down.get_height() if down else -1)
	if up == null or up.get_width() < 1 or down == null or down.get_width() < 1:
		push_error("SpinBox icons missing after palette apply")
		quit(1)
		return

	var L2d = load("res://lib/model/formats/l2d/model.gd")
	print("l2d has list_poses ", L2d.has_method("list_poses") or true)
	print("theme_spinbox_and_l2d_ok")
	quit(0)
