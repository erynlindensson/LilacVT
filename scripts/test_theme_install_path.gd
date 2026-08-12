extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var tm = load("res://ui/theme_manager.gd").new()
	get_root().add_child(tm)
	await process_frame

	tm.apply_palette("lilac")
	var project: Theme = ThemeDB.get_project_theme()
	var icon_c := project.get_color("icon_normal_color", "Button")
	print("lilac project icon ", icon_c)
	if absf(icon_c.r - 0.239) >= 0.05:
		push_error("lilac icon not applied")
		quit(1)
		return

	tm.apply_palette("classic")
	icon_c = project.get_color("icon_normal_color", "Button")
	print("classic project icon ", icon_c)
	if absf(icon_c.r - 0.298) >= 0.05:
		push_error("classic icon not restored")
		quit(1)
		return

	tm.apply_palette("rose")
	tm.apply_palette("lilac")
	icon_c = project.get_color("icon_normal_color", "Button")
	print("lilac again project icon ", icon_c)
	if absf(icon_c.r - 0.239) >= 0.05:
		push_error("lilac re-apply failed")
		quit(1)
		return

	print("project_theme_sync_ok")
	quit(0)
