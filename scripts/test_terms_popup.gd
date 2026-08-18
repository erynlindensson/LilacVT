extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var terms_scene: PackedScene = load("res://studio/hud/terms/terms.tscn")
	var terms := terms_scene.instantiate()
	root.add_child(terms)
	await process_frame
	await process_frame
	var rtl: RichTextLabel = terms.get_node("%RichTextLabel")
	var text := rtl.text
	print("rtl_text_len=", text.length())
	if text.is_empty():
		printerr("FAIL: RichTextLabel text empty")
		quit(1)
		return
	if not text.contains("MIT License"):
		printerr("FAIL: expected LilacVT MIT license header")
		quit(1)
		return
	if not text.contains("erynlindensson"):
		printerr("FAIL: expected LilacVT copyright line")
		quit(1)
		return
	print("head=", text.substr(0, min(80, text.length())))
	print("terms_ok")
	quit(0)
