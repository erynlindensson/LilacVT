extends RefCounted
class_name BlueprintInspectorParameterPanel

const ParameterGrouping = preload("res://lib/blueprints/ui/parameter_grouping.gd")
const ParameterRow = preload("res://lib/blueprints/ui/parameter_row.gd")
const ParameterList = preload("res://lib/blueprints/ui/parameter_list.gd")
const Helpers = preload("res://lib/blueprints/ui/inspector_helpers.gd")
const VtAction = preload("res://lib/blueprints/vt_action.gd")

static func build(action: VtAction, parent: VBoxContainer) -> void:
	var list: BlueprintParameterList = action.get_parameter_list() if action.has_method(
		&"get_parameter_list"
	) else null
	var rows := _collect_rows(action)
	if rows.is_empty():
		return

	var filter := LineEdit.new()
	filter.placeholder_text = "Search parameters…"
	filter.clear_button_enabled = true
	if list != null:
		filter.text = list.filter_text
		filter.text_changed.connect(func(text: String):
			list.filter_text = text
			if list.filter_edit != null:
				list.filter_edit.text = text
			list.finalize_layout()
			_sync_panel_visibility(parent, list)
		)
	Helpers.add_field_row(parent, "Filter", filter)

	var grouped: Dictionary = {}
	for row in rows:
		var group_name := ParameterGrouping.infer_group(row.parameter_name)
		if group_name not in grouped:
			grouped[group_name] = []
		grouped[group_name].append(row)

	for group_name in ParameterGrouping.sorted_group_names(grouped):
		var group_rows: Array = grouped[group_name]
		var header := Button.new()
		header.focus_mode = Control.FOCUS_NONE
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.flat = true
		header.set_meta("group_name", group_name)
		header.pressed.connect(func():
			if list == null:
				return
			var collapsed: bool = list.collapsed_groups.get(group_name, true)
			list.set_group_collapsed(group_name, not collapsed)
			_refresh_header_text(header, group_name, group_rows.size(), list)
			_sync_panel_visibility(parent, list)
			if list._group_headers.has(group_name):
				list._group_headers[group_name].text = header.text
		)
		if list != null:
			_refresh_header_text(header, group_name, group_rows.size(), list)
		else:
			header.text = "▼ %s (%d)" % [group_name, group_rows.size()]
		parent.add_child(header)

		for source_row in group_rows:
			var block := VBoxContainer.new()
			block.set_meta("group_name", group_name)
			block.set_meta("param_name", source_row.parameter_name)
			parent.add_child(block)

			var title_row := HBoxContainer.new()
			block.add_child(title_row)

			var toggle := Button.new()
			toggle.text = "▶" if not source_row.is_details_visible() else "▼"
			toggle.custom_minimum_size = Vector2(24, 0)
			toggle.flat = true
			toggle.focus_mode = Control.FOCUS_NONE
			title_row.add_child(toggle)

			var name_label := Label.new()
			name_label.text = source_row.parameter_name
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			title_row.add_child(name_label)

			var details := HBoxContainer.new()
			details.visible = source_row.is_details_visible()
			block.add_child(details)

			var min_spin := SpinBox.new()
			min_spin.step = 0.01
			min_spin.editable = true
			min_spin.suffix = "min"
			min_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			details.add_child(min_spin)

			var max_spin := SpinBox.new()
			max_spin.step = 0.01
			max_spin.editable = true
			max_spin.suffix = "max"
			max_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			details.add_child(max_spin)

			var cur_spin := SpinBox.new()
			cur_spin.step = 0.01
			cur_spin.editable = true
			cur_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			details.add_child(cur_spin)

			Helpers.link_spinboxes(min_spin, source_row.min_value)
			Helpers.link_spinboxes(max_spin, source_row.max_value)
			Helpers.link_spinboxes(cur_spin, source_row.current_value)

			toggle.pressed.connect(func():
				var show_details := not details.visible
				details.visible = show_details
				source_row.set_details_visible(show_details)
				toggle.text = "▼" if show_details else "▶"
			)

	if list != null:
		_sync_panel_visibility(parent, list)

static func _collect_rows(action: VtAction) -> Array[ParameterRow]:
	var rows: Array[ParameterRow] = []
	for child in action.get_children():
		if child is ParameterRow:
			rows.append(child)
	return rows

static func _refresh_header_text(
	header: Button,
	group_name: String,
	count: int,
	list: BlueprintParameterList
) -> void:
	var collapsed: bool = list.collapsed_groups.get(group_name, true)
	var prefix := "▼" if not collapsed else "▶"
	header.text = "%s %s (%d)" % [prefix, group_name, count]

static func _sync_panel_visibility(parent: VBoxContainer, list: BlueprintParameterList) -> void:
	var filter := list.filter_text.strip_edges().to_lower()
	for child in parent.get_children():
		if child.has_meta("group_name") and child.has_meta("param_name"):
			var group_name: String = child.get_meta("group_name")
			var param_name: String = child.get_meta("param_name")
			var collapsed: bool = list.collapsed_groups.get(group_name, true)
			var matches := filter.is_empty() or param_name.to_lower().contains(filter)
			child.visible = matches and not collapsed
		elif child is Button and child.has_meta("group_name"):
			var group_name: String = child.get_meta("group_name")
			var collapsed: bool = list.collapsed_groups.get(group_name, true)
			var has_match := false
			if filter.is_empty():
				has_match = true
			else:
				for row in list._group_rows.get(group_name, []):
					if row.parameter_name.to_lower().contains(filter):
						has_match = true
						break
			child.visible = has_match or filter.is_empty()
			_refresh_header_text(child, group_name, list._group_rows.get(group_name, []).size(), list)
