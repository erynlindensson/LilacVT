extends SceneTree
## Headless smoke test for ThemeManager palette remapping.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var tm := get_root().get_node_or_null("ThemeManager")
	if tm == null:
		# Autoloads may not exist when running -s; instantiate manually.
		tm = load("res://ui/theme_manager.gd").new()
		get_root().add_child(tm)
		await process_frame

	assert(tm.DEFAULT_PALETTE == "lilac")
	assert(tm.get_palette_ids().size() == 5)

	tm.apply_palette("lilac")
	assert(tm.active_palette_id == "lilac")
	var lilac_ink: Color = tm.ink
	assert(absf(lilac_ink.r - 0.239) < 0.02)

	tm.apply_palette("classic")
	assert(tm.active_palette_id == "classic")
	var classic_ink: Color = tm.ink
	assert(absf(classic_ink.r - 0.298039) < 0.02)

	tm.apply_palette("rose")
	assert(tm.active_palette_id == "rose")
	tm.apply_palette("slate")
	assert(tm.active_palette_id == "slate")
	tm.apply_palette("godot_dark")
	assert(tm.active_palette_id == "godot_dark")

	var theme: Theme = tm._active_theme
	assert(theme != null)
	var btn_font := theme.get_color("font_color", "Button")
	# Slate ink should be applied to button font if it was classic ink in base theme.
	assert(absf(btn_font.r - tm.ink.r) < 0.05)

	print("theme_manager_ok")
	quit(0)
