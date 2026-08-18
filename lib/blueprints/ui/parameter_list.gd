extends RefCounted
class_name BlueprintParameterList

const ParameterGrouping = preload("res://lib/blueprints/ui/parameter_grouping.gd")
const ParameterRow = preload("res://lib/blueprints/ui/parameter_row.gd")
const VtAction = preload("res://lib/blueprints/vt_action.gd")

signal layout_changed

var host: VtAction
var filter_edit: LineEdit
var collapsed_groups: Dictionary = {}
var filter_text: String = ""

var ports: Dictionary = {}
var slots: Dictionary = {}
var port_count: int = 0

var _group_headers: Dictionary = {}
var _group_rows: Dictionary = {}
var _rows: Dictionary = {}
var _row_enabled: Dictionary = {}
var _chrome: VBoxContainer

func _init(action: VtAction) -> void:
	host = action

func clear() -> void:
	for child in host.get_children():
		child.queue_free()
	ports.clear()
	slots.clear()
	port_count = 0
	_group_headers.clear()
	_group_rows.clear()
	_rows.clear()
	_row_enabled.clear()
	filter_edit = null
	_chrome = null

func build_filter_row() -> void:
	_chrome = VBoxContainer.new()
	_chrome.name = "_Chrome"
	host.add_child(_chrome)

	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 4)
	_chrome.add_child(filter_row)

	var filter_label := Label.new()
	filter_label.text = "Filter"
	filter_row.add_child(filter_label)

	filter_edit = LineEdit.new()
	filter_edit.placeholder_text = "Search parameters…"
	filter_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_edit.clear_button_enabled = true
	filter_edit.text = filter_text
	filter_edit.text_changed.connect(_on_filter_changed)
	filter_row.add_child(filter_edit)

	var slot := host.get_child_count() - 1
	host.set_slot_enabled_left(slot, false)
	host.set_slot_enabled_right(slot, false)

func add_group_header(group_name: String, param_count: int) -> Button:
	var header := Button.new()
	header.name = "_Group_%s" % group_name
	header.focus_mode = Control.FOCUS_NONE
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.flat = true
	header.text = _group_label(group_name, param_count, not collapsed_groups.get(group_name, true))
	header.pressed.connect(_on_group_header_pressed.bind(group_name))
	host.add_child(header)

	var slot := host.get_child_count() - 1
	host.set_slot_enabled_left(slot, false)
	host.set_slot_enabled_right(slot, false)

	_group_headers[group_name] = header
	_group_rows[group_name] = []
	return header

func add_parameter_row(
	param: String,
	value_range: Vector2,
	default_value: float,
	port_side: StringName,
	port_type: int,
	visible: bool = true
) -> ParameterRow:
	var group_name := ParameterGrouping.infer_group(param)
	if group_name not in _group_rows:
		push_error("BlueprintParameterList: missing group header for %s" % group_name)
		return null

	var row: ParameterRow = ParameterRow.create(param, value_range, default_value)
	host.add_child(row)
	_rows[param] = row
	_row_enabled[param] = visible
	_group_rows[group_name].append(row)

	var slot := host.get_child_count() - 1
	var port_enabled := false
	match port_side:
		&"input":
			host.set_slot_enabled_left(slot, true)
			host.set_slot_type_left(slot, port_type)
			port_enabled = visible
		&"output":
			host.set_slot_enabled_right(slot, true)
			host.set_slot_type_right(slot, port_type)
			port_enabled = visible

	host.apply_slot_color(slot, port_side if port_side != &"" else &"both")

	if port_enabled:
		ports[param.to_lower()] = port_count
		slots[port_count] = slot
		port_count += 1

	_update_group_header(group_name)
	return row

func finalize_layout(label_width: float = 0.0) -> void:
	for row in _rows.values():
		if label_width > 0.0:
			row.set_label_width(label_width)
	_sync_visibility()
	layout_changed.emit()

func set_group_collapsed(group_name: String, collapsed: bool) -> void:
	collapsed_groups[group_name] = collapsed
	_sync_visibility()

func set_default_collapse(unless_groups: Array = []) -> void:
	for group_name in _group_rows:
		if group_name in unless_groups:
			collapsed_groups[group_name] = false
		elif group_name not in collapsed_groups:
			collapsed_groups[group_name] = true

func get_ui_state() -> Dictionary:
	return {
		"collapsed_groups": collapsed_groups.keys(),
		"filter": filter_text,
	}

func load_ui_state(data: Dictionary) -> void:
	collapsed_groups.clear()
	for group_name in data.get("collapsed_groups", []):
		collapsed_groups[String(group_name)] = true
	filter_text = String(data.get("filter", ""))
	if filter_edit != null:
		filter_edit.text = filter_text

func _on_group_header_pressed(group_name: String) -> void:
	var collapsed: bool = collapsed_groups.get(group_name, true)
	collapsed_groups[group_name] = not collapsed
	_sync_visibility()

func _on_filter_changed(text: String) -> void:
	filter_text = text
	_sync_visibility()

func set_row_enabled(param: String, enabled: bool) -> void:
	_row_enabled[param] = enabled
	if _rows.has(param):
		var slot := (_rows[param] as ParameterRow).get_index()
		host.set_slot_enabled_left(slot, enabled)
	_sync_visibility()

func _sync_visibility() -> void:
	for group_name in _group_rows:
		var collapsed: bool = collapsed_groups.get(group_name, true)
		var matching_count := 0

		for row in _group_rows[group_name]:
			var matches_filter := _row_matches_filter(row)
			var enabled: bool = _row_enabled.get(row.parameter_name, true)
			if matches_filter and enabled:
				matching_count += 1
			row.visible = enabled and matches_filter and not collapsed

		if _group_headers.has(group_name):
			_group_headers[group_name].text = _group_label(
				group_name,
				_group_rows[group_name].size(),
				not collapsed
			)
			_group_headers[group_name].visible = (
				matching_count > 0 or filter_text.strip_edges().is_empty()
			)

	host.size.y = 0

func _row_matches_filter(row: ParameterRow) -> bool:
	var query := filter_text.strip_edges().to_lower()
	return query.is_empty() or row.parameter_name.to_lower().contains(query)

func _update_group_header(group_name: String) -> void:
	if not _group_headers.has(group_name):
		return
	var collapsed: bool = collapsed_groups.get(group_name, true)
	_group_headers[group_name].text = _group_label(
		group_name,
		_group_rows[group_name].size(),
		not collapsed
	)

func _group_label(group_name: String, count: int, expanded: bool) -> String:
	var prefix := "▼" if expanded else "▶"
	return "%s %s (%d)" % [prefix, group_name, count]
