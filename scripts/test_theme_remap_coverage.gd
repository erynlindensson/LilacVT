extends SceneTree
## Report how many theme colors/styleboxes change under lilac with current ThemeManager.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var tm = load("res://ui/theme_manager.gd").new()
	get_root().add_child(tm)
	await process_frame

	var base: Theme = preload("res://ui/ui_theme.tres")
	tm.apply_palette("lilac")
	var themed: Theme = tm._active_theme

	var color_total := 0
	var color_changed := 0
	var sb_total := 0
	var sb_changed := 0
	for type_name in base.get_type_list():
		for color_name in base.get_color_list(type_name):
			color_total += 1
			var a := base.get_color(color_name, type_name)
			var b := themed.get_color(color_name, type_name)
			if a != b:
				color_changed += 1
			elif a.a > 0.01 and not (absf(a.r - a.g) < 0.02 and absf(a.g - a.b) < 0.02):
				print("unchanged color ", type_name, "/", color_name, " ", a)
		for style_name in base.get_stylebox_list(type_name):
			var sba := base.get_stylebox(style_name, type_name)
			var sbb := themed.get_stylebox(style_name, type_name)
			if sba is StyleBoxFlat and sbb is StyleBoxFlat:
				sb_total += 1
				if (sba as StyleBoxFlat).bg_color != (sbb as StyleBoxFlat).bg_color \
					or (sba as StyleBoxFlat).border_color != (sbb as StyleBoxFlat).border_color:
					sb_changed += 1
				elif (sba as StyleBoxFlat).bg_color.a > 0.01:
					var bg := (sba as StyleBoxFlat).bg_color
					if not (absf(bg.r - bg.g) < 0.02 and absf(bg.g - bg.b) < 0.02):
						print("unchanged sb ", type_name, "/", style_name, " bg=", bg)

	print("colors %d/%d changed" % [color_changed, color_total])
	print("styleboxes %d/%d changed" % [sb_changed, sb_total])
	print("button font lilac=", themed.get_color("font_color", "Button"))
	var btn_normal = themed.get_stylebox("normal", "Button")
	if btn_normal is StyleBoxFlat:
		print("button normal bg=", (btn_normal as StyleBoxFlat).bg_color)
	elif btn_normal != null:
		print("button normal type=", btn_normal.get_class())
		if btn_normal is PaddedStylebox:
			var inner = (btn_normal as PaddedStylebox).stylebox
			if inner is StyleBoxFlat:
				print("button padded bg=", (inner as StyleBoxFlat).bg_color)
	quit(0)
