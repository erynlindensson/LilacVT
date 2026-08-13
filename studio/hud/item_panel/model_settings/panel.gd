extends Window

const Collections = preload("res://lib/utils/collections.gd")
const VtModel = preload("res://lib/model/vt_model.gd")
const Stage = preload("res://studio/stage/stage.gd")

@onready var stage = get_tree().get_first_node_in_group("system:stage")
var model: VtModel

var _pause_signals = false

func _ready():
	assert(model != null)
	%Movement/XValue.value_changed.connect(_move_model)
	%Movement/YValue.value_changed.connect(_move_model)
	%Movement/ZValue.value_changed.connect(_move_model)
	%Movement/LockButton.toggled.connect(_on_movement_lock_button_toggled)
	
	# mesh modifier controls
	var categories = {}
	for property in model.get_property_list():
		if not property.name.begins_with("modifiers/"):
			continue
		var segments = property.name.trim_prefix("modifiers/").split("/")
		var category: String = segments[0]
		var part: String = segments[1]
		var field: String = segments[2]
		
		if category not in categories:
			var panel = preload("./modifier_settings.tscn").instantiate()
			panel.name = "%s Settings" % category.capitalize()
			%Accordion.add_child(panel)
			categories[category] = panel.get_node("%Items")
			
		var list = categories[category]
		if not list.has_node(part):
			var frame = PanelContainer.new()
			frame.name = part
			frame.theme_type_variation = "Section"
			var box = VBoxContainer.new()
			box.name = "Properties"
			var label = Label.new()
			label.text = part
			label.theme_type_variation = "BoldLabel"
		
			box.add_child(label)
			frame.add_child(box)
			list.add_child(frame)
		
		var fields = list.get_node("%s/Properties" % part)
		var f = HBoxContainer.new()
		var label = Label.new()
		label.text = field.replace("_", " ").capitalize()
		label.clip_text = true
		label.theme_type_variation = "FieldLabel"
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		f.add_child(label)
		match property.type:
			Variant.Type.TYPE_FLOAT:
				var range: PackedStringArray = property.hint_string.split(",")
				var control = SpinBox.new()
				control.alignment = HORIZONTAL_ALIGNMENT_RIGHT
				control.min_value = range[0].to_float()
				control.max_value = range[1].to_float()
				control.value = model.get(property.name)
				control.step = 0.01
				control.name = field
				control.value_changed.connect(
					func (v):
						model.set(property.name, v)
				)
				f.add_child(control)
			Variant.Type.TYPE_COLOR:
				var control = ColorPickerButton.new()
				control.custom_minimum_size = Vector2i(48, 0)
				control.color = model.get(property.name)
				control.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				control.color_changed.connect(
					func (c):
						model.set(property.name, c)
				)
				f.add_child(control)
			Variant.Type.TYPE_BOOL:
				var control = CheckBox.new()
				control.custom_minimum_size = Vector2i(48, 0)
				control.set_pressed_no_signal(model.get(property.name))
				control.size_flags_horizontal = Control.SIZE_SHRINK_END
				control.toggled.connect(
					func (t):
						model.set(property.name, t)
				)
				f.add_child(control)
			_:
				continue
		fields.add_child(f)
			
	# _model.renderer.transform_updated.connect(_update_transform)
		
	%IdleAnimation.clear()
	%IdleAnimation.add_item("None")
	var lib = model.get_idle_animation_player().get_animation_library("")
	if lib:
		for anim in lib.get_animation_list():
			if anim == "RESET":
				continue
			%IdleAnimation.add_item(anim)
			if anim == model.get_idle_animation_player().current_animation:
				%IdleAnimation.selected = %IdleAnimation.item_count - 1
	%IdleAnimation.disabled = not lib or lib.get_animation_list_size() == 0
		
	_sync_quality_controls()
	
	%Movement/XValue.set_value_no_signal(model.movement_scale.x)
	%Movement/YValue.set_value_no_signal(model.movement_scale.y)
	%Movement/ZValue.set_value_no_signal(model.movement_scale.z)
	
	model.request_delete.connect(close_requested.emit)
	
func _sync_quality_controls() -> void:
	%TextureFilter.select(0 if VtModel.is_nearest_texture_filter(model.texture_filter) else 1)
	%Antialiasing.select(_msaa_option_index(model.render_msaa))
	%AnisotropicFilter.select(_anisotropic_option_index(model.render_anisotropic))
	%TransparentAa.set_pressed_no_signal(model.render_transparent_aa)
	_update_transparent_aa_state()
	_update_smooth_scaling_state()

## Alpha-to-coverage resolves against MSAA samples, so the toggle needs antialiasing on.
func _update_transparent_aa_state() -> void:
	var has_msaa := model.render_msaa != Viewport.MSAA.MSAA_DISABLED
	%TransparentAa.disabled = not has_msaa
	%TransparentAa.tooltip_text = (
		"Supersamples the model at 2x and smooths cutout hair/outline edges, keeping the "
		+ "background fully transparent. WARNING: GPU-intensive!"
		if has_msaa
		else "Requires Antialiasing (MSAA) to be enabled."
	)

func _msaa_option_index(value: Viewport.MSAA) -> int:
	match value:
		Viewport.MSAA.MSAA_DISABLED:
			return 0
		Viewport.MSAA.MSAA_2X:
			return 1
		_:
			return 2

func _msaa_from_option_index(index: int) -> Viewport.MSAA:
	match index:
		0:
			return Viewport.MSAA.MSAA_DISABLED
		1:
			return Viewport.MSAA.MSAA_2X
		_:
			return Viewport.MSAA.MSAA_4X

func _anisotropic_option_index(value: Viewport.AnisotropicFiltering) -> int:
	match value:
		Viewport.AnisotropicFiltering.ANISOTROPY_DISABLED:
			return 0
		Viewport.AnisotropicFiltering.ANISOTROPY_2X:
			return 1
		Viewport.AnisotropicFiltering.ANISOTROPY_8X:
			return 3
		Viewport.AnisotropicFiltering.ANISOTROPY_16X:
			return 4
		_:
			return 2

func _anisotropic_from_option_index(index: int) -> Viewport.AnisotropicFiltering:
	match index:
		0:
			return Viewport.AnisotropicFiltering.ANISOTROPY_DISABLED
		1:
			return Viewport.AnisotropicFiltering.ANISOTROPY_2X
		3:
			return Viewport.AnisotropicFiltering.ANISOTROPY_8X
		4:
			return Viewport.AnisotropicFiltering.ANISOTROPY_16X
		_:
			return Viewport.AnisotropicFiltering.ANISOTROPY_4X

func _apply_texture_filter() -> void:
	var nearest: bool = %TextureFilter.selected == 0
	var anisotropic := model.render_anisotropic != Viewport.AnisotropicFiltering.ANISOTROPY_DISABLED
	model.texture_filter = VtModel.texture_filter_for_quality(nearest, anisotropic)
	_update_smooth_scaling_state()

func _update_smooth_scaling_state() -> void:
	%SmoothScaling.disabled = not VtModel.is_nearest_texture_filter(model.texture_filter)

func _move_model(_value):
	if not model:
		return
		
	_pause_signals = true
	model.movement_scale = Vector3(
		%Movement/XValue.value,
		%Movement/YValue.value,
		%Movement/ZValue.value
	)
	_pause_signals = false
	
func _on_texture_filter_item_selected(_index: int) -> void:
	_apply_texture_filter()

func _on_antialiasing_item_selected(index: int) -> void:
	model.render_msaa = _msaa_from_option_index(index)
	model.apply_render_quality()
	_update_transparent_aa_state()

func _on_anisotropic_filter_item_selected(index: int) -> void:
	model.render_anisotropic = _anisotropic_from_option_index(index)
	_apply_texture_filter()
	model.apply_render_quality()

func _on_transparent_aa_toggled(toggled_on: bool) -> void:
	model.render_transparent_aa = toggled_on
	model.apply_transparent_aa()

func _on_smooth_scaling_toggled(toggled_on: bool) -> void:
	model.smoothing = toggled_on

func _on_idle_animation_item_selected(index: int) -> void:
	var player = model.get_idle_animation_player()
	if index <= 0:
		player.stop()
		if player.has_animation("RESET"):
			player.play("RESET")
		return

	var anim = %IdleAnimation.get_item_text(index)
	if not player.has_animation(anim):
		push_warning("Idle animation not found: %s" % anim)
		return
	player.play(anim)

func _on_movement_lock_button_toggled(toggled_on: bool) -> void:
	model.movement_enabled = !toggled_on
	
	%Movement/XValue.editable = !toggled_on
	%Movement/YValue.editable = !toggled_on
	%Movement/ZValue.editable = !toggled_on

func _on_close_requested() -> void:
	queue_free()
