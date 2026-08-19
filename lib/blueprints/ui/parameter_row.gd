extends VBoxContainer
class_name ParameterRow

signal min_value_changed(param: String, val: float)
signal max_value_changed(param: String, val: float)
signal current_value_changed(param: String, val: float)
signal smoothing_changed(param: String, strength: float)

var parameter_name: String = ""
var _toggle: Button
var _details: HBoxContainer
var min_value: SpinBox
var max_value: SpinBox
var current_value: SpinBox
var smoothing_value: SpinBox

static func create(param: String, value_range: Vector2, default_value: float) -> ParameterRow:
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

	min_value = _make_editable_spinbox("min", value_range.x)
	min_value.tooltip_text = "Minimum bound"
	min_value.value_changed.connect(_on_min_value_changed)
	_details.add_child(min_value)

	max_value = _make_editable_spinbox("max", value_range.y)
	max_value.tooltip_text = "Maximum bound"
	max_value.value_changed.connect(_on_max_value_changed)
	_details.add_child(max_value)

	current_value = _make_editable_spinbox("", default_value)
	current_value.tooltip_text = "Current / manual value"
	current_value.value_changed.connect(_on_current_value_changed)
	_details.add_child(current_value)

	smoothing_value = _make_editable_spinbox("% smth", 0.0, 0.0, 100.0, 1.0)
	smoothing_value.tooltip_text = "Smoothing strength % (0 = off, 100 = maximum)"
	smoothing_value.visible = false
	smoothing_value.value_changed.connect(_on_smoothing_value_changed)
	_details.add_child(smoothing_value)

	set_details_visible(false)

func _make_editable_spinbox(
	suffix: String,
	value: float,
	min_v: float = -999999.0,
	max_v: float = 999999.0,
	step_v: float = 0.01
) -> SpinBox:
	var spin := SpinBox.new()
	spin.step = step_v
	spin.min_value = min_v
	spin.max_value = max_v
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.rounded = false
	spin.value = value
	spin.suffix = suffix
	spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.editable = true
	return spin

func set_min_value(val: float) -> void:
	if min_value != null and not is_equal_approx(min_value.value, val):
		min_value.set_value_no_signal(val)

func get_min_value() -> float:
	return min_value.value if min_value != null else 0.0

func set_max_value(val: float) -> void:
	if max_value != null and not is_equal_approx(max_value.value, val):
		max_value.set_value_no_signal(val)

func get_max_value() -> float:
	return max_value.value if max_value != null else 1.0

func set_current_value(val: float) -> void:
	if current_value != null and not is_equal_approx(current_value.value, val):
		current_value.set_value_no_signal(val)

func get_current_value() -> float:
	return current_value.value if current_value != null else 0.0

func set_value_range(val_range: Vector2) -> void:
	set_min_value(val_range.x)
	set_max_value(val_range.y)

func get_value_range() -> Vector2:
	return Vector2(get_min_value(), get_max_value())

func _on_min_value_changed(val: float) -> void:
	min_value_changed.emit(parameter_name, val)

func _on_max_value_changed(val: float) -> void:
	max_value_changed.emit(parameter_name, val)

func _on_current_value_changed(val: float) -> void:
	current_value_changed.emit(parameter_name, val)

func set_smoothing_enabled(enabled: bool) -> void:
	if smoothing_value != null:
		smoothing_value.visible = enabled

func set_smoothing_value(strength: float) -> void:
	if smoothing_value != null:
		smoothing_value.set_value_no_signal(clampf(strength * 100.0, 0.0, 100.0))

func get_smoothing_value() -> float:
	if smoothing_value != null:
		return smoothing_value.value / 100.0
	return 0.0

func _on_smoothing_value_changed(val: float) -> void:
	smoothing_changed.emit(parameter_name, val / 100.0)

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
