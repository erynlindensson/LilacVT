extends GraphFrame
class_name GraphFrameGroup
## Group frame with native titlebar (always visible) and fully clickable tinted body.

const TITLEBAR_HEIGHT := 24.0

func _ready() -> void:
	var bar := get_titlebar_hbox()
	if bar:
		bar.visible = true
	clip_contents = false
	autoshrink_margin = 48
	selectable = true
	draggable = true
	resizable = true
	_update_drag_margin()
	_apply_selection_tint()
	item_rect_changed.connect(_on_layout_changed)
	position_offset_changed.connect(_on_layout_changed)
	node_selected.connect(_on_selection_changed)
	node_deselected.connect(_on_selection_changed)

func _update_drag_margin() -> void:
	# GraphFrame only hit-tests its drag_margin border in C++; fill the whole body.
	drag_margin = int(minf(size.x, size.y) * 0.5) + 4

func get_frame_id() -> String:
	return String(get_meta("id", name))

func get_titlebar_rect() -> Rect2:
	return Rect2(0, 0, size.x, TITLEBAR_HEIGHT)

func _has_point(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(point)

func _on_layout_changed(_arg = null) -> void:
	_update_drag_margin()

func _on_selection_changed() -> void:
	_apply_selection_tint()

func _apply_selection_tint() -> void:
	modulate = Color.WHITE if is_selected() else Color(0.78, 0.78, 0.82)

func refresh_title_handles() -> void:
	_apply_selection_tint()
