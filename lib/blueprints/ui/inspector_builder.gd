extends RefCounted
class_name BlueprintInspectorBuilder

const Helpers = preload("res://lib/blueprints/ui/inspector_helpers.gd")
const ParameterPanel = preload("res://lib/blueprints/ui/inspector_parameter_panel.gd")
const VtAction = preload("res://lib/blueprints/vt_action.gd")
const Blueprint = preload("res://lib/blueprints/blueprint.gd")

static func build_action(action: VtAction, parent: VBoxContainer) -> void:
	Helpers.add_readonly_row(parent, "Type", String(action.get_type()))
	if not action.title.is_empty():
		Helpers.add_line_edit_row(parent, "Title", action.title, func(text: String):
			action.title = text
		)

	match action.get_type():
		&"smoothing":
			_build_smoothing(action, parent)
		&"arithmetic":
			_build_arithmetic(action, parent)
		&"breathe":
			_build_breathe(action, parent)
		&"blink":
			_build_blink(action, parent)
		&"hotkey":
			_build_hotkey(action, parent)
		&"screen_button":
			_build_screen_button(action, parent)
		&"tracking_input":
			_build_tracker(action, parent)
		&"model_output":
			_build_model_output(action, parent)
		&"expression":
			_build_expression(action, parent)
		&"animation":
			_build_animation(action, parent)

static func build_frame(frame: GraphFrame, graph: Blueprint, parent: VBoxContainer) -> void:
	Helpers.add_readonly_row(parent, "Type", "Group")
	Helpers.add_line_edit_row(parent, "Title", frame.title, func(text: String):
		frame.title = text
		if graph.has_method(&"refresh_group_handles_for_frame"):
			graph.refresh_group_handles_for_frame(frame)
	)
	Helpers.add_checkbox_row(parent, "Autoshrink", frame.autoshrink_enabled, func(on: bool):
		frame.autoshrink_enabled = on
	)
	Helpers.add_checkbox_row(parent, "Resizable", frame.resizable, func(on: bool):
		frame.resizable = on
	)
	Helpers.add_checkbox_row(parent, "Tint", frame.tint_color_enabled, func(on: bool):
		frame.tint_color_enabled = on
	)

	var picker := ColorPickerButton.new()
	picker.color = frame.tint_color
	picker.color_changed.connect(func(color: Color): frame.tint_color = color)
	Helpers.add_field_row(parent, "Tint Color", picker)

	Helpers.add_separator(parent)
	Helpers.add_section_label(parent, "Members")

	var attached: Array = graph.get_attached_nodes_of_frame(frame.name)
	if attached.is_empty():
		Helpers.add_readonly_row(parent, "Nodes", "(none)")
	else:
		for node_name in attached:
			var node := graph.get_node_or_null(NodePath(node_name))
			var label := String(node_name)
			if node is GraphNode:
				label = node.title
			Helpers.add_readonly_row(parent, "", label)

static func _build_smoothing(action: VtAction, parent: VBoxContainer) -> void:
	Helpers.add_spinbox_row(
		parent,
		"Smoothing",
		action.smoothing * 100.0,
		func(v: float): action.smoothing = v / 100.0,
		0.0,
		100.0,
		1.0
	)

static func _build_arithmetic(action: VtAction, parent: VBoxContainer) -> void:
	var option := OptionButton.new()
	for i in action.Operator.size():
		option.add_item(action.Operator.keys()[i], i)
	option.selected = int(action.operator)
	option.item_selected.connect(func(idx: int): action.operator = idx)
	Helpers.add_field_row(parent, "Operator", option)

	Helpers.add_spinbox_row(parent, "A", action.a, func(v: float): action.a = v)
	Helpers.add_spinbox_row(parent, "B", action.b, func(v: float): action.b = v)

static func _build_breathe(action: VtAction, parent: VBoxContainer) -> void:
	Helpers.add_spinbox_row(
		parent,
		"Frequency",
		action.frequency,
		func(v: float): action.frequency = v,
		100.0,
		10000.0,
		10.0
	)

static func _build_blink(action: VtAction, parent: VBoxContainer) -> void:
	Helpers.add_spinbox_row(
		parent,
		"Min Interval",
		action.frequency.x,
		func(v: float): action.frequency = Vector2(v, action.frequency.y),
		0.0,
		20000.0,
		10.0
	)
	Helpers.add_spinbox_row(
		parent,
		"Max Interval",
		action.frequency.y,
		func(v: float): action.frequency = Vector2(action.frequency.x, v),
		0.0,
		20000.0,
		10.0
	)
	Helpers.add_spinbox_row(
		parent,
		"Speed",
		action.speed,
		func(v: float): action.speed = v,
		0.0,
		2000.0,
		1.0
	)

static func _build_hotkey(action: VtAction, parent: VBoxContainer) -> void:
	var line := LineEdit.new()
	line.text = action.get_node("%Input").text
	line.editable = false
	var btn := Button.new()
	btn.text = "Set Hotkey…"
	btn.pressed.connect(action._on_input_pressed)
	var row := HBoxContainer.new()
	row.add_child(line)
	row.add_child(btn)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Helpers.add_field_row(parent, "Binding", row)

static func _build_screen_button(action: VtAction, parent: VBoxContainer) -> void:
	var group: ButtonGroup = action.button_group
	var option := OptionButton.new()
	option.add_item("(none)", -1)
	for i in group.get_buttons().size():
		option.add_item("Button %d" % (i + 1), i)
	var pressed := group.get_pressed_button()
	if pressed != null:
		option.selected = pressed.get_index() + 1
	option.item_selected.connect(func(idx: int):
		for b in group.get_buttons():
			b.set_pressed_no_signal(false)
		if idx >= 0:
			group.get_buttons()[idx].button_pressed = true
	)
	Helpers.add_field_row(parent, "Button", option)

static func _build_tracker(action: VtAction, parent: VBoxContainer) -> void:
	var kinds: Array = Registry.parameter_groups()
	var option := OptionButton.new()
	for i in kinds.size():
		option.add_item(String(kinds[i]))
		if StringName(kinds[i]) == action.kind:
			option.selected = i
	option.item_selected.connect(func(idx: int):
		action.kind = StringName(option.get_item_text(idx))
	)
	Helpers.add_field_row(parent, "Source", option)
	Helpers.add_separator(parent)
	ParameterPanel.build(action, parent)

static func _build_model_output(action: VtAction, parent: VBoxContainer) -> void:
	Helpers.add_separator(parent)
	ParameterPanel.build(action, parent)

static func _build_expression(action: VtAction, parent: VBoxContainer) -> void:
	var source: OptionButton = action.get_node("%Expression")
	var option := OptionButton.new()
	for i in source.item_count:
		option.add_item(source.get_item_text(i))
		option.set_item_metadata(option.item_count - 1, source.get_item_metadata(i))
	option.selected = source.selected
	option.item_selected.connect(func(idx: int):
		source.select(idx)
		action._on_expression_item_selected(idx)
	)
	Helpers.add_field_row(parent, "Expression", option)

	var fade: SpinBox = action.get_node("%Fade/Value")
	Helpers.add_spinbox_row(
		parent,
		"Fade (ms)",
		fade.value,
		func(v: float): fade.value = v,
		0.0,
		5000.0,
		10.0
	)

static func _build_animation(action: VtAction, parent: VBoxContainer) -> void:
	var source: OptionButton = action.get_node("%Animation")
	var option := OptionButton.new()
	for i in source.item_count:
		option.add_item(source.get_item_text(i))
		option.set_item_metadata(option.item_count - 1, source.get_item_metadata(i))
	option.selected = source.selected
	option.item_selected.connect(func(idx: int): source.select(idx))
	Helpers.add_field_row(parent, "Animation", option)

	var speed: SpinBox = action.get_node("%Speed/Value")
	Helpers.add_spinbox_row(
		parent,
		"Speed %",
		speed.value,
		func(v: float): speed.value = v,
		0.0,
		300.0,
		1.0
	)
	var fade: SpinBox = action.get_node("%Fade/Value")
	Helpers.add_spinbox_row(
		parent,
		"Fade (ms)",
		fade.value,
		func(v: float): fade.value = v,
		0.0,
		5000.0,
		10.0
	)
