extends PanelContainer

const Catalog = preload("res://lib/model/catalog/model_catalog.gd")
const Files = preload("res://lib/utils/files.gd")

signal download_requested(entry: Dictionary)

var entry: Dictionary = {}
var _format: StringName = &"l2d"

func setup(model_entry: Dictionary, format: StringName = &"l2d") -> void:
	entry = model_entry
	_format = format
	%Name.text = String(entry.get("name", "Untitled"))
	%Author.text = String(entry.get("author", ""))
	%License.text = String(entry.get("license", ""))
	set_meta("text", "%s %s %s" % [
		entry.get("name", ""),
		entry.get("author", ""),
		entry.get("description", ""),
	])
	tooltip_text = String(entry.get("description", ""))
	refresh_installed()
	_load_preview(String(entry.get("preview", "")))

func refresh_installed() -> void:
	var installed := Catalog.is_installed(_format, String(entry.get("dest_folder", "")))
	%Get.text = "Installed" if installed else "Get"
	%Get.disabled = installed

func set_busy(busy: bool) -> void:
	if Catalog.is_installed(_format, String(entry.get("dest_folder", ""))):
		%Get.disabled = true
		return
	%Get.disabled = busy

func _on_get_pressed() -> void:
	download_requested.emit(entry)

func _load_preview(url: String) -> void:
	if url.is_empty():
		return
	var http := HTTPRequest.new()
	http.timeout = 30.0
	http.use_threads = true
	add_child(http)
	var err := http.request(url, PackedStringArray(["User-Agent: %s" % Catalog.USER_AGENT]))
	if err != OK:
		http.queue_free()
		return
	var completed: Array = await http.request_completed
	http.queue_free()
	if not is_instance_valid(self):
		return
	var result: int = completed[0]
	var code: int = completed[1]
	var body: PackedByteArray = completed[3]
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
		return
	var img: Image = Files.image_from_buffer(body)
	if img == null:
		return
	%Preview.texture = ImageTexture.create_from_image(img)
