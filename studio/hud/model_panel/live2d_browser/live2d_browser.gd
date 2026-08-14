extends Window

const Catalog = preload("res://lib/model/catalog/model_catalog.gd")
const Fetcher = preload("res://lib/model/catalog/live2d_fetcher.gd")
const RowScene = preload("res://studio/hud/model_panel/live2d_browser/catalog_row.tscn")

signal model_imported

var kind: String = "l2d"

var _fetcher: Fetcher
var _spec: Dictionary = {}
var _format: StringName = &"l2d"
var _license_pref: String = ""
var _license_url: String = ""
var _terms_url: String = ""
var _rows: Array[Node] = []
var _pending_entry: Dictionary = {}
var _busy := false

@onready var _http_host: Node = $FetcherHost

func _ready() -> void:
	_spec = Catalog.spec_for(kind)
	_format = StringName(_spec.get("format", &"l2d"))
	_license_pref = String(_spec.get("license_pref", ""))
	_license_url = String(_spec.get("license_url", ""))
	_terms_url = String(_spec.get("terms_url", ""))
	title = String(_spec.get("title", title))
	%LicenseDialog.title = String(_spec.get("dialog_title", %LicenseDialog.title))
	%LicenseDialog.dialog_text = String(_spec.get("dialog_text", %LicenseDialog.dialog_text))
	%LicenseLink.text = String(_spec.get("license_link_text", %LicenseLink.text))
	%TermsLink.text = String(_spec.get("terms_link_text", %TermsLink.text))
	_fetcher = Fetcher.new()
	_http_host.add_child(_fetcher)
	_fetcher.configure(_spec)
	_fetcher.progress.connect(_on_progress)
	%Search.list = %ModelList
	%LicenseAgree.toggled.connect(_on_license_agree_toggled)
	_on_license_agree_toggled(%LicenseAgree.button_pressed)
	close_requested.connect(_on_close_requested)
	_load()

func _on_close_requested() -> void:
	hide()
	queue_free()

func _alert(message: String) -> void:
	var toast = get_tree().get_first_node_in_group("system:alert")
	if toast:
		toast.alert(message)
	else:
		push_warning(message)

func _load() -> void:
	%Status.text = "Loading catalog…"
	var catalog: Dictionary = await _fetcher.load_catalog()
	if not is_instance_valid(self):
		return
	var models: Array = Catalog.models_of(catalog)
	for child in %ModelList.get_children():
		child.queue_free()
	_rows.clear()
	if models.is_empty():
		%Status.text = "No models in catalog"
		return
	for entry in models:
		if not entry is Dictionary:
			continue
		var row = RowScene.instantiate()
		%ModelList.add_child(row)
		row.setup(entry, _format)
		row.download_requested.connect(_on_row_get_pressed)
		_rows.append(row)
	%Search.do_filter()
	var notice := String(catalog.get("license_notice", ""))
	%Status.text = notice if not notice.is_empty() else "%d models" % _rows.size()

func _on_row_get_pressed(entry: Dictionary) -> void:
	if _busy:
		return
	if Catalog.is_installed(_format, String(entry.get("dest_folder", ""))):
		_alert("Already installed")
		return
	if not bool(Preferences.get_setting(_license_pref, false)):
		_pending_entry = entry
		%LicenseDialog.popup_centered()
		return
	await _start_download(entry)

func _on_license_agree_toggled(pressed: bool) -> void:
	var ok: Button = %LicenseDialog.get_ok_button()
	if ok != null:
		ok.disabled = not pressed

func _on_license_confirmed() -> void:
	if not %LicenseAgree.button_pressed:
		return
	Preferences.set_setting(_license_pref, true)
	Preferences.save_data()
	var entry: Dictionary = _pending_entry
	_pending_entry = {}
	if not entry.is_empty():
		await _start_download(entry)

func _on_license_canceled() -> void:
	_pending_entry = {}

func _on_license_link_pressed() -> void:
	if not _license_url.is_empty():
		OS.shell_open(_license_url)

func _on_terms_link_pressed() -> void:
	if not _terms_url.is_empty():
		OS.shell_open(_terms_url)

func _start_download(entry: Dictionary) -> void:
	_busy = true
	_set_rows_busy(true)
	var error: String = await _fetcher.download_model(entry)
	if not is_instance_valid(self):
		return
	_busy = false
	_set_rows_busy(false)
	for row in _rows:
		if is_instance_valid(row):
			row.refresh_installed()
	if error.is_empty():
		ModelManager.refresh_models()
		model_imported.emit()
		_alert("Model imported")
		%Status.text = "Installed %s" % entry.get("name", "")
	else:
		_alert(error)
		%Status.text = error

func _set_rows_busy(busy: bool) -> void:
	for row in _rows:
		if is_instance_valid(row):
			row.set_busy(busy)

func _on_progress(current: int, total: int, message: String) -> void:
	%Status.text = message if total <= 1 else "%s (%d/%d)" % [message, current, total]
