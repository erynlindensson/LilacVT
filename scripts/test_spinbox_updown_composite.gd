extends SceneTree
func _init():
	call_deferred("run")
func run():
	await process_frame
	var tm = load("res://ui/theme_manager.gd").new()
	root.add_child(tm)
	await process_frame
	tm.apply_palette("lilac")
	var ud = ThemeDB.get_project_theme().get_icon("updown", "SpinBox")
	print("updown=", ud, " w=", ud.get_width() if ud else -1, " h=", ud.get_height() if ud else -1)
	if ud == null or ud.get_width() < 8 or ud.get_height() < 16 or ud.get_height() > 64:
		push_error("bad updown size")
		quit(1)
		return
	print("spinbox_composite_ok")
	quit(0)
