extends PanelContainer

const Builder = preload("res://lib/blueprints/ui/inspector_builder.gd")
const VtAction = preload("res://lib/blueprints/vt_action.gd")
const Blueprint = preload("res://lib/blueprints/blueprint.gd")

const PANEL_WIDTH := 280.0

@onready var _header: Label = %HeaderLabel
@onready var _fields: VBoxContainer = %FieldsVBox

var _graph: Blueprint = null
var _target: GraphElement = null
var _slide_tween: Tween

func _ready() -> void:
	custom_minimum_size.x = 0.0
	visible = false
	%CloseButton.pressed.connect(hide_panel)

func bind_graph(graph: Blueprint) -> void:
	if _graph != null and _graph.selection_changed.is_connected(_on_graph_selection_changed):
		_graph.selection_changed.disconnect(_on_graph_selection_changed)
	_graph = graph
	if _graph != null:
		_graph.selection_changed.connect(_on_graph_selection_changed)
		_on_graph_selection_changed(_graph.get_selected_elements())

func show_element(element: GraphElement) -> void:
	_target = element
	if element is GraphFrame:
		_header.text = "Group"
	elif element is VtAction:
		_header.text = String(element.get_type()).capitalize()
	else:
		_header.text = "Selection"
	_rebuild_fields()
	_slide_open()

func hide_panel() -> void:
	_target = null
	_slide_closed()

func _on_graph_selection_changed(selected: Array) -> void:
	if selected.is_empty():
		hide_panel()
		return
	show_element(selected[selected.size() - 1])

func _rebuild_fields() -> void:
	for child in _fields.get_children():
		child.queue_free()
	if _target == null or _graph == null:
		return
	if _target is GraphFrame:
		Builder.build_frame(_target, _graph, _fields)
	elif _target is VtAction:
		Builder.build_action(_target, _fields)

func _slide_open() -> void:
	visible = true
	if _slide_tween:
		_slide_tween.kill()
	_slide_tween = create_tween()
	_slide_tween.tween_property(
		self,
		"custom_minimum_size:x",
		PANEL_WIDTH,
		0.25
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

func _slide_closed() -> void:
	if _slide_tween:
		_slide_tween.kill()
	_slide_tween = create_tween()
	_slide_tween.tween_property(
		self,
		"custom_minimum_size:x",
		0.0,
		0.25
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	_slide_tween.tween_callback(func():
		visible = false
		for child in _fields.get_children():
			child.queue_free()
	)
