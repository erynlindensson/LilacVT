# System for loading models from VTubeStudio's format
# and spawning them into the scene to be managed
extends "../../vt_model.gd"

const Collections = preload("res://lib/utils/collections.gd")

var model: AyagamiModel
var container: Node

const ModelModifier = preload("../../modifier.gd")
const ParameterModifier = preload("./modifiers/parameter_modifier.gd")
const PartModifier = preload("./modifiers/part_modifier.gd")
const MeshModifier = preload("./modifiers/mesh_modifier.gd")

var param_settings: Dictionary[StringName, ModelModifier] = {}
var part_settings: Dictionary[StringName, ModelModifier] = {}
var mesh_settings: Dictionary[StringName, ModelModifier] = {}
var physics_strength: float = 1.0
var physics_mode: int = 0
var physics_groups: Dictionary = {}
var modifier_map = {
	"modifiers/parts/": part_settings,
	"modifiers/meshes/": mesh_settings,
	"modifiers/parameters/": param_settings
}

func _ready() -> void:
	container = preload("./pixel_subviewport.tscn").instantiate()
	add_child(container)

func is_initialized() -> bool:
	return model != null
	
func get_meshes() -> Array:
	return model.get_node("Meshes").get_children()
	
func get_parts() -> Array:
	return model.get_parts()
	
func get_size() -> Vector2:
	return model.size
	
func get_origin() -> Vector2:
	return model.origin
	
func get_parameters() -> Dictionary:
	return model.get_parameters().reduce(
		func (acc, p):
			acc[p] = {
				"default": model.get("parameters/%s/default" % p),
				"range": model.get("parameters/%s/range" % p) 
			}
			return acc,
		{}
	)
	
func _get(property: StringName) -> Variant:
	if property.begins_with("parameters/") or property.begins_with("parts/"):
		return model.get(property)
	for prefix in modifier_map:
		if not property.begins_with(prefix):
			continue
		var modifiers = modifier_map[prefix]
		var segments = property.trim_prefix(prefix).split("/")
		var part = segments[0]
		var field = segments[1]
		var modifier: ModelModifier = modifiers.get(part)
		if modifier:
			return modifier.get(field)
	return null

func _property_get_revert(property: StringName) -> Variant:
	if property.begins_with("parameters/") or property.begins_with("parts/"):
		return model.property_get_revert(property)
	
	for prefix in modifier_map:
		if not property.begins_with(prefix):
			continue
		
		var segments = property.trim_prefix(prefix).split("/")
		var part = segments[0]
		var field = segments[1]
		
		var settings: ModelModifier = modifier_map[prefix][part]
		return settings.property_get_revert(field)
		
	return null

func _set(property: StringName, value: Variant) -> bool:
	if property.begins_with("parameters/"):
		if not property.ends_with("/range") and not property.ends_with("/default"):
			model.set(property, value)
			return true
	
	for p in modifier_map:
		if not property.begins_with(p):
			continue
		var parts = property.trim_prefix(p).split("/")
		var param = parts[0]
		var field = parts[1]
		var modifier: ModelModifier = modifier_map[p].get(param)
		if modifier:
			var old_value = modifier.get(field)
			modifier.set(field, value)
			modifier_updated.emit.call_deferred(
				property, value, old_value
			)
			return true

	if property == "texture_filter":
		texture_filter = value
		_adjust_filter()
		return true

	return false
		
func _adjust_filter():
	var nearest := texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST \
		or texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS \
		or texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	if nearest and smoothing:
		container.model = model
	else:
		model.reparent(self, false)
		container.model = null

func _apply_model_viewport_quality() -> void:
	if container == null:
		return
	var model_vp := container.get_node_or_null("SubViewport") as SubViewport
	if model_vp != null:
		model_vp.msaa_2d = render_msaa
		model_vp.anisotropic_filtering_level = render_anisotropic

func _apply_transparent_aa_impl() -> void:
	if container == null:
		return
	TransparentAa.apply_viewport_container(
		container as SubViewportContainer,
		render_transparent_aa,
		_transparent_window_for_compositing(),
	)
	if model != null:
		TransparentAa.apply_materials(model, alpha_to_coverage_enabled())
		
func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	var base_properties = model.get_property_list()
	
	for param in Collections.select(base_properties, "name", RegEx.create_from_string("^parameters/")):
		var p_name = param.name.trim_prefix("parameters/")
		properties.append(param)
	
	for prefix in modifier_map:
		var settings = modifier_map[prefix]
		for p in settings:
			var modifier = settings[p]
			for prop in modifier.get_property_list():
				properties.append(prop.merged({
					"name": "{0}{1}/{2}".format([prefix, p, prop.name])
				}, true))
	
	return properties
	
func _build_model():
	var reload = is_initialized()
	if reload:
		model.queue_free()
		model = null
		await get_tree().process_frame
		
	print_debug("loading model from %s" % modelmeta.model)
	model = AyagamiLoader.load_model(modelmeta.model)
	if model == null:
		push_error("could not load model %s" % modelmeta.model)
		return false
	# adjust anchor to be top-left to match godot's control coordinate system
	add_child(model)
	await get_tree().process_frame # wait for the model to initialize
	
	for m in get_meshes():
		if (m as MeshInstance2D).mesh.get_surface_count() <= 0:
			continue
		var center = Math.v32xy(Math.centroid(m.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]))
		m.set_meta("centroid", center)
		m.set_meta("start_centroid", center)
	
	var anim_lib = AyagamiLoader.load_motion_library(model)
	var idle_anim: AnimationPlayer = model.get_node("MotionController")
	if idle_anim.has_animation_library(""):
		idle_anim.remove_animation_library("") # remove just in case
	idle_anim.add_animation_library("", anim_lib)
	
	# emotion controller
	var expression_library = AyagamiLoader.load_expression_library(modelmeta.model.get_base_dir())
	var expression_controller: AyagamiExpressionMutator = model.get_node("ExpressionController")
	expression_controller.expressions = expression_library.keys()
	for e in expression_library.keys():
		var group = expression_library[e]
		if group != "":
			expression_controller.set("expression_groups/%s" % e.get_name(), group)
	
	# add ONE_SHOT animation player
	var os_lib = AnimationLibrary.new()
	for anim in anim_lib.get_animation_list():
		var a = anim_lib.get_animation(anim)
		var os_a = a.duplicate(true)
		os_a.loop_mode = Animation.LOOP_NONE
		os_lib.add_animation(anim, os_a)
	var one_shot = AyagamiMotionMutator.new()
	one_shot.add_animation_library("", os_lib)
	one_shot.name = "OneshotMotionController"
	model.add_child(one_shot)
	
	#var physics = GDCubismEffectPhysics.new()
	#loaded_model.add_child(physics)
	#physics.name = "Physics"
	_apply_physics_settings()
	
	for m in get_meshes():
		if (m as MeshInstance2D).mesh.get_surface_count() <= 0:
			continue
		
		var center = Math.v32xy(Math.centroid(m.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]))
		m.set_meta("centroid", center)
		m.set_meta("start_centroid", center)
		
		mesh_settings[m.name] = MeshModifier.new(m)
		
	for p in get_parameters():
		param_settings[p] = ParameterModifier.new()
	
	for p in get_parts():
		part_settings[p] = PartModifier.new(self, p)
					
	await get_tree().process_frame
	
	model.position = Vector2.ZERO
	size = model.size
	centered = true
			
	return true

func apply_parameters(values: Dictionary):
	for p_name in values:
		model.set(p_name, values.get(p_name, 0.0))
	
func tracking_updated(tracking_data: Dictionary, _delta: float):
	if model == null:
		return
	if not movement_enabled:
		model.position = Vector2.ZERO
		model.scale = Vector2.ONE
		return

	var movement := face_movement_from_tracking(tracking_data)
	model.position = Vector2(movement.x, -movement.y) * Vector2(model.size) * FACE_MOVE_SPAN
	if locked:
		model.position = Vector2.ZERO
	model.scale = Vector2.ONE + (Vector2.ONE * movement.z)

func get_texture() -> Texture2D:
	if container is SubViewportContainer:
		return (container.get_child(0) as SubViewport).get_texture()
	return null
	
func get_idle_animation_player() -> AnimationPlayer:
	return model.get_node("MotionController")
	
func get_animation_player() -> AnimationPlayer:
	return model.get_node("OneshotMotionController")
	
func get_expression_controller() -> AyagamiExpressionMutator:
	if model == null:
		return null
	return model.get_node_or_null("ExpressionController")

func toggle_expression(expression_name: String, activate: bool = true, duration: float = 1.0, exclusive: bool = false):
	var expression_controller = get_expression_controller()
	if expression_controller == null:
		return
	if expression_name.is_empty():
		expression_controller.reset()
	elif activate:
		if exclusive:
			expression_controller.reset()
		expression_controller.set("expressions/%s" % expression_name, true)
	else:
		expression_controller.set("expressions/%s" % expression_name, false)

func list_poses() -> PackedStringArray:
	var poses := PackedStringArray(["Neutral"])
	for motion_name in _list_motion_names(true):
		poses.append(motion_name)
	return poses

func apply_pose(pose_name: String, _duration: float = 0.3) -> void:
	if pose_name.is_empty() or pose_name == "Neutral":
		reset_pose(_duration)
		return
	_play_oneshot_motion(pose_name)

func reset_pose(_duration: float = 0.3) -> void:
	_stop_oneshot_motion()

func _list_motion_names(exclude_idle: bool) -> PackedStringArray:
	var names := PackedStringArray()
	var anim := get_animation_player()
	if anim == null:
		return names
	var idle_name := ""
	var idle := get_idle_animation_player()
	if idle != null:
		idle_name = String(idle.current_animation)
	for motion_name in anim.get_animation_list():
		var key := String(motion_name)
		if exclude_idle and not idle_name.is_empty() and key == idle_name:
			continue
		if exclude_idle and key.to_lower().contains("idle"):
			continue
		names.append(key)
	return names

func _play_oneshot_motion(motion_name: String) -> void:
	var anim := get_animation_player()
	if anim == null or not anim.has_animation(motion_name):
		return
	anim.stop()
	anim.play(motion_name)

func _stop_oneshot_motion() -> void:
	var anim := get_animation_player()
	if anim == null:
		return
	anim.stop()

## save bidirectional vts compatible settings
func _save_to_vts():
	if modelmeta.studio_parameters.is_empty():
		return
	
	var vtube_data = Files.read_json(modelmeta.studio_parameters)
	# vtube_data["ParameterSettings"] = studio_parameters.map(func (x): return x.serialize())
	vtube_data["ArtMeshDetails"]["ArtMeshesExcludedFromPinning"] = get_meshes().reduce(
		func (acc, mesh):
			if mesh.name not in mesh_settings:
				return acc
			var pinnable = get("modifiers/meshes/%s/pinnable" % mesh.name)
			if pinnable:
				acc.append(mesh.name)
			return acc,
		[]
	)
	vtube_data["ArtMeshDetails"]["ArtMeshMultiplyAndScreenColors"] = get_meshes().reduce(
		func (acc, mesh):
			if mesh.name not in mesh_settings:
				return acc
			var override = get("modifiers/meshes/%s/color_override" % mesh.name)
			if override:
				acc.append({
					"ID": mesh.name,
					"Value": "%s|%s" % [
						(get("modifiers/meshes/%s/multiply_color" % mesh.name) as Color).to_html(true),
						(get("modifiers/meshes/%s/screen_color" % mesh.name) as Color).to_html(true),
					]
				})
			return acc,
		[]
	)
	vtube_data["FileReferences"]["IdleAnimation"] = get_idle_animation_player().current_animation
	
	Files.write_json(modelmeta.studio_parameters, vtube_data)
	
## load bidirectional vts compatible settings
func _load_from_vts():
	if modelmeta.studio_parameters.is_empty():
		return
	
	var vtube_data = JSON.parse_string(FileAccess.get_file_as_string(modelmeta.studio_parameters))
	
	var idle_animation = vtube_data["FileReferences"]["IdleAnimation"]
	if idle_animation:
		get_idle_animation_player().play(idle_animation)
		
	var movement_settings = vtube_data.get("ModelPositionMovement", {})
	movement_enabled = movement_settings.get("Use", false)
	# VTS stores 10 as +100% of the FacePosition range.
	movement_scale = Vector3(
		inverse_lerp(0.0, 10.0, float(movement_settings.get("X", 0.0))),
		inverse_lerp(0.0, 10.0, float(movement_settings.get("Y", 0.0))),
		inverse_lerp(0.0, 10.0, float(movement_settings.get("Z", 0.0)))
	)

	var mesh_details = vtube_data.get("ArtMeshDetails", {})
	var pin_settings = mesh_details.get("ArtMeshesExcludedFromPinning", [])
		
	# color settings
	var tint = {}
	for v in mesh_details.get("ArtMeshMultiplyAndScreenColors", []):
		var colors = v.Value.split("|")
		tint[v.ID] = {
			"multiply": Color(colors[0]),
			"screen": Color(colors[1])
		}
	
	for mesh in get_meshes():
		if name not in mesh_settings:
			continue
		var settings = mesh_settings[mesh]
		var exclude = mesh.name in pin_settings
		settings.pinnable = not exclude
		
		settings.color_override = mesh.name in tint
		if mesh.name in tint:
			var colors = tint[mesh.name]
			settings.multiply_color = colors.multiply
			settings.screen_color = colors.creen

func save_model_settings(settings: Dictionary):
	super.save_model_settings(settings)
	
	var serializer = Serializers.ObjSerializer
	settings["modifiers"] = {
		"parameters": Collections.remap(param_settings, func (v): return Serializers.ObjSerializer.to_json(v)),
		"meshes": Collections.remap(mesh_settings, func (v): return Serializers.ObjSerializer.to_json(v)),
		"parts": Collections.remap(part_settings, func (v): return Serializers.ObjSerializer.to_json(v))
	}
	settings["physics"] = {
		"strength": physics_strength,
		"mode": physics_mode,
		"groups": physics_groups,
	}
	
	_save_to_vts()
	
func load_model_settings(settings: Dictionary):
	_load_from_vts()
	super.load_model_settings(settings)

	var physics: Dictionary = settings.get("physics", {})
	physics_strength = float(physics.get("strength", physics_strength))
	physics_mode = int(physics.get("mode", physics_mode))
	var saved_groups: Variant = physics.get("groups", {})
	if saved_groups is Dictionary:
		physics_groups = saved_groups
	_apply_physics_settings()

	for p in self.get_parameters():
		var modifier = param_settings[StringName(p)]
		var saved = settings.get("modifiers", {}).get("parameters", {}).get(p, {})
		Serializers.ObjSerializer.from_json(saved, modifier)
	
	for m in self.get_meshes():
		if m.name not in mesh_settings:
			continue
		var modifier = mesh_settings[m.name]
		var saved = settings.get("modifiers", {}).get("meshes", {}).get(m.name, {})
		# fallback to what's loaded from vts
		Serializers.ObjSerializer.from_json(saved, modifier)
		
	for p in self.get_parts():
		var modifier = part_settings[p]
		var saved = settings.get("modifiers", {}).get("parts", {}).get(p, {})
		Serializers.ObjSerializer.from_json(saved, modifier)

func get_physics_controller() -> Node:
	if model == null:
		return null
	return model.get_node_or_null("PhysicsController")

func get_physics_group_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	if modelmeta == null or String(modelmeta.physics).is_empty():
		return ids
	if not FileAccess.file_exists(modelmeta.physics):
		return ids
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(modelmeta.physics))
	if not (parsed is Dictionary):
		return ids
	for setting in parsed.get("PhysicsSettings", []):
		if setting is Dictionary:
			var group_id := String(setting.get("Id", ""))
			if not group_id.is_empty():
				ids.append(group_id)
	return ids

func _apply_physics_settings() -> void:
	var controller := get_physics_controller()
	if controller == null:
		return
	if "mode" in controller:
		controller.mode = physics_mode
	if "strength" in controller:
		var group_mul := 1.0
		if not physics_groups.is_empty():
			var sum := 0.0
			for key in physics_groups:
				sum += float(physics_groups[key])
			group_mul = sum / float(physics_groups.size())
		controller.strength = physics_strength * group_mul
	
