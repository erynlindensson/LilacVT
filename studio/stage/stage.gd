extends Node

const GROUP_NAME = "system:stage"

const VtObject = preload("res://lib/vtobject.gd")
const VtModel = preload("res://lib/model/vt_model.gd")
const VtItem = preload("res://lib/items/vt_item.gd")
const Serializers = preload("res://lib/utils/serializers.gd")

const INDEX_RANGE = 30

var active_model: VtModel
var _pending_items: Array = []
var _restoring_items: bool = false
@onready var canvas = %ModelLayer
@onready var capture_viewport = %SubViewport
var _last_viewport_size := Vector2.ZERO

## Global VRM stage lighting (applied when the active model supports it).
const DEFAULT_LIGHTING_COLOR := Color.WHITE
const DEFAULT_LIGHTING_INTENSITY := 0.5

var lighting_color: Color = DEFAULT_LIGHTING_COLOR
var lighting_intensity: float = DEFAULT_LIGHTING_INTENSITY

signal model_changed(model: VtModel)
signal item_added(item: VtItem)
signal item_removed(item: VtItem)
signal lighting_changed(color: Color, intensity: float)

var objects: Array :
	get():
		return canvas.get_children()

func toggle_ndi(enabled: bool) -> void:
	%NDIOutput.enable_video_output = enabled

func is_transparent_window() -> bool:
	return not %Bg.visible

func toggle_bg(enabled: bool) -> void:
	get_tree().root.transparent_bg = enabled
	get_window().transparent = enabled
	get_window().transparent_bg = enabled
	%Bg.visible = not enabled
	if active_model != null:
		active_model.apply_transparent_aa()

func spawn_model(model: VtModel):
	if model == null:
		push_warning("invalid model attempted to load")
		return
	
	var prev_model
	if active_model != null:
		await Preferences.save_data()
		prev_model = active_model
		var t = create_tween().tween_property(
			active_model, "position", Vector2(0, (active_model.size.y * active_model.scale.y) + active_model.get_viewport_rect().size.y), 0.5
		).as_relative().set_trans(Tween.TRANS_CUBIC)
		await t.finished
		# clear all pinned items
		for i in canvas.get_children():
			if i is VtItem:
				i.model = null
				if i.pinned_to != null:
					remove_item(i, false)
		
		canvas.remove_child.call_deferred(active_model)
		
	model.position = Vector2.INF # initialize offscreen
	canvas.add_child(model)
	
	await model.loaded
	
	if model.is_queued_for_deletion():
		get_tree().get_first_node_in_group("system:alert").alert("Unable to load model")	
		return
	active_model = model
	_center_model_if_needed(model)
	
	create_tween().tween_property(
		model, "position",
		model.position,
		0.5
	).from(
		model.position + Vector2(0, model.get_viewport_rect().size.y)
	).set_trans(Tween.TRANS_CUBIC)

	# make carried over objects aware of the new model
	for i in canvas.get_children():
		if i is VtItem:
			i.model = model
			# remove an item if it was pinned to the previous model
			if i.pinned_to != null:
				remove_item(i, false)

	apply_lighting()
	model_changed.emit(active_model)
	if prev_model != null:
		prev_model.queue_free()
	if not _pending_items.is_empty():
		var items: Array = _pending_items
		_pending_items = []
		await _restore_items(items)

func set_lighting(color: Color, intensity: float) -> void:
	lighting_color = color
	lighting_intensity = maxf(intensity, 0.0)
	apply_lighting()
	lighting_changed.emit(lighting_color, lighting_intensity)

func apply_lighting() -> void:
	if active_model != null and active_model.has_method("set_stage_lighting"):
		active_model.set_stage_lighting(lighting_color, lighting_intensity)

func apply_viewport_quality(msaa: Viewport.MSAA, anisotropic: Viewport.AnisotropicFiltering) -> void:
	capture_viewport.msaa_2d = msaa
	capture_viewport.msaa_3d = msaa
	capture_viewport.anisotropic_filtering_level = anisotropic

func spawn_item(item: VtItem, animate = true, reposition = true):
	# do not allow spawning items if there is no active model
	if active_model == null:
		return
		
	# position to center of screen
	if reposition:
		var viewport_rect = get_viewport().get_visible_rect()
		item.model = active_model
		item.scale = Vector2.ONE * min(
			clampf(viewport_rect.size.y / item.size.y, 0.001, 1.0),
			1.0
		)
		item.global_position = (viewport_rect.size / 2) - (item.scale * item.center)
	
	# simply setting z_index does not work for control nodes, as Input order is not affected by it
	# instead we'll rely on child order in the stage to define the position
	if item.get_parent():
		item.reparent(canvas)
	else:
		canvas.add_child(item)
	item_added.emit(item)
	item.request_delete.connect(remove_item.bind(item))
	
	if not animate:
		return
	
	var t = create_tween()
	t.parallel().tween_property(
		item, "scale", item.scale, 0.4
	).from(Vector2.ONE * 0.3).set_trans(Tween.TRANS_CIRC)
	#t.parallel().tween_property(
	#	item, "rotation_degrees", 0, 0.4
	#).from(60).set_trans(Tween.TRANS_QUAD)
	t.parallel().tween_property(
		item, "modulate", Color.WHITE, 0.4
	).from(Color.TRANSPARENT).set_ease(Tween.EASE_IN)

## Keep models framed on screen when saved positions are off-stage or invalid.
func _center_model_if_needed(model: VtModel) -> void:
	var rect := model.get_viewport_rect()
	if rect.size.x < 2.0 or rect.size.y < 2.0:
		rect = Rect2(Vector2.ZERO, Vector2(capture_viewport.size))
	var center := rect.get_center()
	if not model.position.is_finite():
		model.position = center
		return
	# Allow a small margin so barely-on-edge placements still count as visible.
	var visible := rect.grow(maxf(rect.size.x, rect.size.y) * 0.05)
	if not visible.has_point(model.position):
		model.position = center

func remove_item(item: VtItem, animated = true):
	if animated:
		var t = create_tween()
		t.parallel().tween_property(
			item, "scale", item.scale * 0.3, 0.4
		).from(item.scale).set_trans(Tween.TRANS_CIRC)
		#t.parallel().tween_property(
		#	item, "rotation_degrees", 0, 0.4
		#).from(60).set_trans(Tween.TRANS_QUAD)
		t.parallel().tween_property(
			item, "modulate", Color.TRANSPARENT, 0.4
		).from(Color.WHITE).set_ease(Tween.EASE_IN)
		t.finished.connect(item.queue_free)
	else:
		item.queue_free()
	item_removed.emit(item)
	
func clear_items(group_name: StringName = &"*"):
	for i in canvas.get_children():
		if i is VtItem:
			if group_name == &"*" or i.group_name == group_name:
				remove_item(i)

func load_settings(data):
	_pending_items = data.get("items", [])
	if "active_model" in data:
		var mm = get_tree().get_first_node_in_group("system:model")
		var model = mm.make_model(data["active_model"])
		if model:
			spawn_model(model)
	
	toggle_bg(data.get("window", {}).get("transparent", false))
	
func save_settings(data):
	if active_model != null and active_model.modelmeta != null:
		data["active_model"] = active_model.modelmeta.id
	data["items"] = _serialize_items()
	# window.transparent is owned by camera_panel (Bg.visible is the inverse)

func _serialize_items() -> Array:
	var out: Array = []
	for child in canvas.get_children():
		if not (child is VtItem):
			continue
		var item: VtItem = child
		var entry := {
			"path": item.path,
			"position": Serializers.Vec2Serializer.to_json(item.position),
			"scale": item.scale.x,
			"rotation": item.rotation_degrees,
			"pinnable": item.pinnable,
			"pinned_to": item.pinned_to.name if item.pinned_to != null else "",
			"sort_order": item.sort_order,
			"group_name": String(item.group_name),
			"locked": item.locked,
		}
		if item.item_type == VtItem.ItemType.ANIMATED and item.render is AnimatedSprite2D:
			var frames: SpriteFrames = item.render.sprite_frames
			if frames != null:
				entry["fps"] = item.render.speed_scale * frames.get_animation_speed("default")
		out.append(entry)
	return out

func _restore_items(items: Array) -> void:
	if items.is_empty() or active_model == null:
		return
	_restoring_items = true
	ItemManager.refresh_assets()
	var ordered: Array = items.duplicate()
	ordered.sort_custom(
		func (a, b):
			return int(a.get("sort_order", 0)) < int(b.get("sort_order", 0))
	)
	for entry in ordered:
		if not (entry is Dictionary):
			continue
		var path := String(entry.get("path", ""))
		if path.is_empty():
			continue
		var item: VtItem = await ItemManager.create_item(path)
		if item == null:
			push_warning("Unable to restore item: %s" % path)
			continue
		item.scale = Vector2.ONE * float(entry.get("scale", 1.0))
		item.rotation_degrees = float(entry.get("rotation", 0.0))
		item.position = Serializers.Vec2Serializer.from_json(
			entry.get("position", {}),
			get_viewport().get_visible_rect().get_center()
		)
		item.pinnable = bool(entry.get("pinnable", false))
		item.locked = bool(entry.get("locked", false))
		item.sort_order = int(entry.get("sort_order", 0))
		var group := String(entry.get("group_name", ""))
		if not group.is_empty():
			item.group_name = StringName(group)
		if item.item_type == VtItem.ItemType.ANIMATED and item.render is AnimatedSprite2D:
			var frames: SpriteFrames = item.render.sprite_frames
			if frames != null and entry.has("fps"):
				var base_fps := frames.get_animation_speed("default")
				if base_fps > 0.0:
					item.render.speed_scale = float(entry["fps"]) / base_fps
		spawn_item(item, false, false)
		var pin_name := String(entry.get("pinned_to", ""))
		if not pin_name.is_empty():
			for mesh in active_model.get_meshes():
				if mesh.name == pin_name:
					item.pinned_to = mesh
					item.pin_changed.emit(mesh)
					break
	_restoring_items = false
	
func _ready() -> void:
	_last_viewport_size = Vector2(capture_viewport.size)
	capture_viewport.size_changed.connect(_on_capture_viewport_size_changed)
	# Opaque stage background until prefs / camera panel enable transparency.
	toggle_bg(false)

func _on_capture_viewport_size_changed() -> void:
	var new_size := Vector2(capture_viewport.size)
	if _last_viewport_size == Vector2.ZERO:
		_last_viewport_size = new_size
		return
	if new_size == _last_viewport_size or _last_viewport_size.y <= 0.0:
		_last_viewport_size = new_size
		return

	# Keep model/items framed relative to viewport center as the SubViewport grows
	# (e.g. maximize). Uniform scale by height matches VTS-style vertical framing.
	var factor := new_size.y / _last_viewport_size.y
	var old_center := _last_viewport_size * 0.5
	var new_center := new_size * 0.5
	for child in canvas.get_children():
		if child is Node2D or child is Control:
			var offset: Vector2 = child.position - old_center
			child.position = new_center + offset * factor
			child.scale *= factor

	_last_viewport_size = new_size

func _on_model_layer_child_order_changed() -> void:
	for i in canvas.get_children():
		i.sort_order = i.get_index()
