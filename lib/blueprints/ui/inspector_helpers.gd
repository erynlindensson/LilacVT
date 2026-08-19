extends RefCounted
class_name BlueprintInspectorHelpers

static func add_section_label(parent: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	parent.add_child(label)
	return label

static func add_field_row(
	parent: Control,
	label_text: String,
	control: Control
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 96
	row.add_child(label)

	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row

static func add_readonly_row(parent: Control, label_text: String, value: String) -> void:
	var line := LineEdit.new()
	line.text = value
	line.editable = false
	add_field_row(parent, label_text, line)

static func add_line_edit_row(
	parent: Control,
	label_text: String,
	value: String,
	on_change: Callable
) -> LineEdit:
	var line := LineEdit.new()
	line.text = value
	line.text_changed.connect(func(text: String): on_change.call(text))
	add_field_row(parent, label_text, line)
	return line

static func add_spinbox_row(
	parent: Control,
	label_text: String,
	value: float,
	on_change: Callable,
	min_v: float = 0.0,
	max_v: float = 100.0,
	step: float = 0.01
) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.value = value
	spin.value_changed.connect(on_change)
	add_field_row(parent, label_text, spin)
	return spin

static func add_checkbox_row(
	parent: Control,
	label_text: String,
	value: bool,
	on_change: Callable
) -> CheckBox:
	var check := CheckBox.new()
	check.text = label_text
	check.button_pressed = value
	check.toggled.connect(on_change)
	parent.add_child(check)
	return check

static func add_separator(parent: Control) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)

static func link_spinboxes(a: SpinBox, b: SpinBox) -> void:
	a.set_value_no_signal(b.value)
	a.value_changed.connect(func(v: float): b.set_value_no_signal(v))
	b.value_changed.connect(func(v: float): a.set_value_no_signal(v))

static func link_editable_spinboxes(a: SpinBox, b: SpinBox) -> void:
	a.set_value_no_signal(b.value)
	var syncing := [false]
	a.value_changed.connect(func(v: float):
		if syncing[0]:
			return
		syncing[0] = true
		b.value = v
		syncing[0] = false
	)
	b.value_changed.connect(func(v: float):
		if syncing[0]:
			return
		syncing[0] = true
		a.value = v
		syncing[0] = false
	)
