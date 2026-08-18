extends Window

const LICENSE_PATHS: PackedStringArray = ["res://LICENSE", "res://LICENSE.txt"]
const FALLBACK_TEXT := (
	"License text could not be loaded.\n\n"
	+ "See LICENSE in the LilacVT install directory."
)

var accepted: String = ""
var _pending_show := false

func _ready() -> void:
	%RichTextLabel.text = _load_license_text()
	%RichTextLabel.add_theme_color_override("default_color", ThemeManager.ink)
	visible = false

func save_settings(settings: Dictionary) -> void:
	if not accepted.is_empty():
		queue_free()

	settings["accepted_terms"] = accepted

func load_settings(settings: Dictionary) -> void:
	accepted = settings.get("accepted_terms", "")
	if not accepted.is_empty():
		queue_free()
	else:
		_pending_show = true
		_present_when_ready.call_deferred()

func _load_license_text() -> String:
	for path in LICENSE_PATHS:
		if not FileAccess.file_exists(path):
			continue
		var text := FileAccess.get_file_as_string(path)
		if not text.is_empty():
			return text.strip_edges()
		push_error("Terms: license file is empty: %s" % path)
	push_error("Terms: no license file found at %s" % ", ".join(LICENSE_PATHS))
	return FALLBACK_TEXT

func _present_when_ready() -> void:
	if not _pending_show or not is_inside_tree():
		return
	await _wait_for_splash()
	if not _pending_show or not is_instance_valid(self):
		return
	popup_centered()

func _wait_for_splash() -> void:
	var splash := get_parent().get_node_or_null("Splash")
	if splash == null or not is_instance_valid(splash):
		return
	await splash.tree_exited

func _on_accept_pressed() -> void:
	accepted = "%d" % Time.get_unix_time_from_system()
	Preferences.save_data.call_deferred()
	hide()

func _on_reject_pressed() -> void:
	get_tree().quit()

func _on_close_requested() -> void:
	_on_reject_pressed()
