extends VBoxContainer
class_name ParameterRow

var parameter_name: String = ""
var _toggle: Button
var _details: HBoxContainer
var min_value: SpinBox
var max_value: SpinBox
var current_value: SpinBox

static func create(param: String, value_range: Vector2, default_value: float):
	var row: ParameterRow = load("res://lib/blueprints/ui/parameter_row.gd").new()
	row.parameter_name = param
	row.name = param
	row.add_theme_constant_override("separation", 2)
	row._build(value_range, default_value)
	return row

func _build(value_range: Vector2, default_value: float) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	add_child(header)

	_toggle = Button.new()
	_toggle.text = "▼"
	_toggle.custom_minimum_size = Vector2(24, 0)
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.flat = true
	_toggle.toggle_mode = false
	_toggle.pressed.connect(_on_toggle_pressed)
	header.add_child(_toggle)

	var label := Label.new()
	label.text = parameter_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_stretch_ratio = 2.0
	header.add_child(label)

	_details = HBoxContainer.new()
	_details.add_theme_constant_override("separation", 2)
	add_child(_details)

	min_value = _make_spinbox("min", value_range.x)
	_details.add_child(min_value)
	max_value = _make_spinbox("max", value_range.y)
	_details.add_child(max_value)
	current_value = _make_spinbox("", default_value)
	_details.add_child(current_value)
	set_details_visible(false)

func _make_spinbox(suffix: String, value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.step = 0.01
	spin.rounded = false
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.value = value
	spin.suffix = suffix
	spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.editable = false
	return spin

func set_details_visible(show_details: bool) -> void:
	_details.visible = show_details
	_toggle.text = "▼" if show_details else "▶"

func is_details_visible() -> bool:
	return _details.visible

func _on_toggle_pressed() -> void:
	set_details_visible(not _details.visible)

func set_label_width(width: float) -> void:
	var label: Label = (_toggle.get_parent() as HBoxContainer).get_child(1)
	label.custom_minimum_size.x = width
