extends "../../vt_model.gd"

const Collections = preload("res://lib/utils/collections.gd")
const PoseLibrary = preload("./pose_library.gd")
const RuntimeExtensions = preload("./runtime_extensions.gd")
const ModelModifier = preload("../../modifier.gd")
const MeshModifier = preload("./modifiers/mesh_modifier.gd")

const VRM_BLENDSHAPES : PackedStringArray = [
	# emotions
	"happy",
	"angry",
	"sad",
	"relaxed",
	"surprised",
	# mouth shapes
	"aa",
	"ee",
	"ih",
	"oh",
	"ou",
	# eyes
	"blinkLeft",
	"blinkRight",
	"lookUp",
	"lookDown",
	"lookLeft",
	"lookRight",
	"neutral",
	# head
	"headRotX",
	"headRotY",
	"headRotZ",
]

const _MOOD_EXPRESSIONS: PackedStringArray = [
	"happy", "angry", "sad", "relaxed", "surprised",
]

## Ayagami-compatible expression entry for UI / blueprints.
class VrmExpressionRef:
	var name: String
	func _init(n: String) -> void:
		name = n
	func get_name() -> String:
		return name

## Ayagami-compatible expression controller surface.
class VrmExpressionController:
	var _model: Node
	var expressions: Array = []
	func _init(model_ref: Node, names: PackedStringArray) -> void:
		_model = model_ref
		expressions.clear()
		for n in names:
			expressions.append(VrmExpressionRef.new(n))
	func is_activated(expression_name: Variant) -> bool:
		var key := String(expression_name)
		if _model == null:
			return false
		return float(_model._parameter_values.get(key, 0.0)) > 0.5

var model: Node3D
var container: Node
var vp: SubViewport
var camera: Camera3D

var blendshapes_meshes = {}
## Model-local AABB at rest (ignores runtime position/scale/rotation).
var _rest_aabb: AABB = AABB()
var _face_move_offset: Vector2 = Vector2.ZERO
var _face_move_z: float = 0.0
## Live values written by blueprints / apply_parameters.
var _parameter_values: Dictionary[String, float] = {}
## Expression names that exist on this model's AnimationPlayer.
var _expression_names: PackedStringArray = PackedStringArray()
var _expression_controller: VrmExpressionController
## Set Expression pins that the mixer/blueprint should not overwrite.
var _pinned_expressions: Dictionary = {}
## Active body-pose bone rotations (bone name → Quaternion); Head/eyes excluded.
var _pose_overrides: Dictionary = {}
var _pose_tween: Tween
var _expression_tween: Tween


func load_data(path: String) -> ModelMeta:
	var model_file: String = ""
	for file in Array(DirAccess.get_files_at(path)):
		if file.ends_with(".vrm"):
			model_file = path.path_join(file)
	
	if model_file.is_empty():
		return null
	
	var meta = ModelMeta.new()
	
	var base_name = ""
	base_name = model_file.get_file()
	meta.name = base_name
	meta.id = base_name
	meta.model = model_file
	meta.path = path
	meta.format = "vrm"
	meta.openvt_parameters = "%s/%s.ovt.json" % [meta.model.get_base_dir(), base_name]
	
	return meta
	
func _ready() -> void:
	container = preload("./model_viewport.tscn").instantiate()
	vp = container.get_node("%SubViewport")
	camera = container.get_node("%Camera3D")
	add_child(container)

func _apply_model_viewport_quality() -> void:
	if vp != null:
		vp.msaa_3d = render_msaa
		vp.anisotropic_filtering_level = render_anisotropic

func _apply_transparent_aa_impl() -> void:
	if container == null:
		return
	var viewport_container := container.get_node_or_null("ModelViewport") as SubViewportContainer
	if viewport_container != null:
		TransparentAa.apply_viewport_container(
			viewport_container,
			render_transparent_aa,
			_transparent_window_for_compositing(),
		)
	TransparentAa.apply_subviewport(vp, render_transparent_aa)
	if model != null:
		TransparentAa.apply_materials(model, alpha_to_coverage_enabled())

func is_initialized():
	return model != null
	
func load_vrm(path: String) -> Node:
	RuntimeExtensions.ensure_registered()

	var gltf: GLTFDocument = GLTFDocument.new()
	# vrm_extension.gd is VRM 0.x only and returns ERR_INVALID_DATA for VRMC_vrm.
	var vrm_0x: GLTFDocumentExtension = null
	if not RuntimeExtensions.file_uses_vrmc(path):
		vrm_0x = preload("res://addons/vrm/vrm_extension.gd").new()
		gltf.register_gltf_document_extension(vrm_0x, true)

	var state: GLTFState = GLTFState.new()
	# IgnoreHeadHiding: stage view needs the full head. Layers/Both crashes some VRM 1.0 files.
	state.set_additional_data(&"vrm/head_hiding_method", 5)
	state.set_additional_data(&"vrm/first_person_layers", 2)
	state.set_additional_data(&"vrm/third_person_layers", 4)

	var err = gltf.append_from_file(path, state, 16 | 8 | 2)
	if err != OK:
		if vrm_0x != null:
			gltf.unregister_gltf_document_extension(vrm_0x)
		return null

	var vrm: Node = gltf.generate_scene(state)

	if vrm_0x != null:
		gltf.unregister_gltf_document_extension(vrm_0x)

	return vrm
	
func _build_model():
	model = load_vrm(modelmeta.model) as Node3D
	await get_tree().process_frame
	
	if model == null:
		return false
	
	var anim: AnimationPlayer = _find_animation_player()
	_parameters = {
		"headRotX": _make_parameter("headRotX", "Head Rotation X", 0.0, -30.0, 30.0),
		"headRotY": _make_parameter("headRotY", "Head Rotation Y", 0.0, -30.0, 30.0),
		"headRotZ": _make_parameter("headRotZ", "Head Rotation Z", 0.0, -30.0, 30.0),
	}
	_parameter_values = {
		"headRotX": 0.0,
		"headRotY": 0.0,
		"headRotZ": 0.0,
	}
	blendshapes_meshes.clear()
	_expression_names = PackedStringArray()
	
	if anim != null:
		# Collect mesh morph targets from RESET (baseline bindings).
		if anim.has_animation("RESET"):
			_register_blendshape_tracks(anim.get_animation("RESET"), "")
		
		# Prefer VRM 1.0 expression animation names (godot-vrm normalizes 0.x → 1.0).
		for expr in VRM_BLENDSHAPES:
			if expr.begins_with("headRot"):
				continue
			if not anim.has_animation(expr):
				continue
			_expression_names.append(expr)
			_register_blendshape_tracks(anim.get_animation(expr), expr)
			if not _parameters.has(expr):
				_parameters[expr] = _make_parameter(expr, expr, 0.0, 0.0, 1.0)
				_parameter_values[expr] = 0.0
		
		# Custom VRM expressions beyond the standard whitelist.
		for clip_name in anim.get_animation_list():
			if clip_name == "RESET" or clip_name.begins_with("headRot"):
				continue
			if clip_name in _expression_names:
				continue
			_expression_names.append(clip_name)
			_register_blendshape_tracks(anim.get_animation(clip_name), clip_name)
			if not _parameters.has(clip_name):
				_parameters[clip_name] = _make_parameter(clip_name, clip_name, 0.0, 0.0, 1.0)
				_parameter_values[clip_name] = 0.0
	
	_expression_controller = VrmExpressionController.new(self, _expression_names)
	_pose_overrides.clear()
	
	vp.add_child(model)
	
	var skeleton: Skeleton3D = _get_skeleton()
	if skeleton != null:
		skeleton.reset_bone_poses()
	if anim != null and anim.has_animation("RESET"):
		anim.play("RESET")
		await get_tree().process_frame
		anim.stop()
	await get_tree().process_frame
	
	_meshes = model.find_children("*", "MeshInstance3D", true, false)
	mesh_settings.clear()
	for mesh_node in _meshes:
		if mesh_node is MeshInstance3D:
			mesh_settings[StringName(mesh_node.name)] = MeshModifier.new(mesh_node as MeshInstance3D)
	_rest_aabb = _compute_local_aabb()
	
	vp.size = Vector2i(1280, 720)
	
	var stage_size := get_viewport_rect().size
	if stage_size.x < 2.0 or stage_size.y < 2.0:
		stage_size = Vector2(1280, 720)
	size = Vector2(
		maxf(stage_size.x * 0.35, 280.0),
		maxf(stage_size.y * 0.7, 480.0)
	)
	centered = true
	
	if not transform_updated.is_connected(_on_transform_updated):
		transform_updated.connect(_on_transform_updated)
	set_notify_transform(true)
	_sync_stage_to_model()
	
	return true

## Register blend-shape tracks. If expression_name is set, also index them under that preset.
func _register_blendshape_tracks(animation: Animation, expression_name: String) -> void:
	for track_index in range(0, animation.get_track_count()):
		if animation.track_get_type(track_index) != Animation.TYPE_BLEND_SHAPE:
			continue
		var track_path: NodePath = animation.track_get_path(track_index)
		var morph := String(track_path.get_subname(0))
		var meshes: Array = blendshapes_meshes.get(morph, [])
		if not meshes.has(track_path):
			meshes.append(track_path)
		blendshapes_meshes[morph] = meshes
		if not _parameters.has(morph):
			var default_v: float = 0.0
			# Only RESET should define rest weights. Expression clips store the *on* value.
			if expression_name.is_empty() and animation.track_get_key_count(track_index) > 0:
				default_v = float(animation.track_get_key_value(track_index, 0))
			_parameters[morph] = _make_parameter(morph, morph, default_v, 0.0, 1.0)
			_parameter_values[morph] = default_v
		if not expression_name.is_empty():
			var expr_meshes: Array = blendshapes_meshes.get(expression_name, [])
			if not expr_meshes.has(track_path):
				expr_meshes.append(track_path)
			blendshapes_meshes[expression_name] = expr_meshes

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_initialized():
		_sync_stage_to_model()

func _on_transform_updated(
	stage_position: Vector2,
	stage_scale: Vector2,
	_stage_rotation_deg: float,
	_offset: Vector2,
	ypr: Vector3
) -> void:
	_apply_stage_transform(stage_position, stage_scale, ypr)

func _sync_stage_to_model() -> void:
	_apply_stage_transform(global_position, scale, free_rotation)

func _apply_stage_transform(stage_position: Vector2, stage_scale: Vector2, ypr: Vector3) -> void:
	if model == null or camera == null:
		return
	# Stage parks new models at Vector2.INF until spawn finishes.
	if not stage_position.is_finite() or not stage_scale.is_finite():
		return
	# Camera lives in the VRM SubViewport; map from stage canvas coords into that space.
	var stage_vp := get_viewport()
	var src_size: Vector2 = stage_vp.get_visible_rect().size if stage_vp else Vector2(vp.size)
	var dst_size := Vector2(vp.size)
	var moved_stage := stage_position + _face_move_offset
	var mapped := Vector2(
		moved_stage.x / maxf(src_size.x, 1.0) * dst_size.x,
		moved_stage.y / maxf(src_size.y, 1.0) * dst_size.y
	)
	if not mapped.is_finite():
		return
	var depth := camera.position.z
	var s := maxf(stage_scale.x, 0.01) * (1.0 + _face_move_z)
	var local_center := _rest_aabb.get_center()
	var projected: Vector3 = camera.project_position(mapped, depth)
	if not projected.is_finite():
		return
	# Anchor the visual center on the projected stage point.
	model.scale = Vector3.ONE * s
	model.rotation = ypr
	model.position = projected - local_center * s

func _compute_local_aabb() -> AABB:
	var aabb := AABB()
	var first := true
	if model == null:
		return aabb
	# Prefer mesh instances anywhere under the VRM root (not only skeleton children).
	for c in model.find_children("*", "VisualInstance3D", true, false):
		if not (c is VisualInstance3D):
			continue
		var mesh_aabb: AABB = (c as VisualInstance3D).get_aabb()
		if mesh_aabb.size.length() <= 0.0:
			continue
		# Convert mesh-local AABB into model-local space.
		var model_space: AABB = (model.global_transform.affine_inverse() * (c as Node3D).global_transform) * mesh_aabb
		if first:
			aabb = model_space
			first = false
		else:
			aabb = aabb.merge(model_space)
	return aabb

func get_size_3d() -> AABB:
	if model != null and _rest_aabb.size.length() > 0.0:
		return AABB(_rest_aabb.position * model.scale.x + model.position, _rest_aabb.size * model.scale.x)
	return _compute_local_aabb()

func get_size() -> Vector2:
	if size.x > 1.0 and size.y > 1.0:
		return size
	var stage_size := get_viewport_rect().size
	if stage_size.x < 2.0 or stage_size.y < 2.0:
		stage_size = Vector2(1280, 720)
	return Vector2(
		maxf(stage_size.x * 0.35, 280.0),
		maxf(stage_size.y * 0.7, 480.0)
	)

func get_origin() -> Vector2:
	return vp.size / 2.0

var _meshes = []
var mesh_settings: Dictionary[StringName, ModelModifier] = {}
var modifier_map = {
	"modifiers/meshes/": mesh_settings,
}

func get_meshes() -> Array:
	return _meshes
	
var _parameters: Dictionary[String, Dictionary] = {}
func get_parameters() -> Dictionary[String, Dictionary]:
	return _parameters

func _make_parameter(id: String, display_name: String, default_value: float, min_value: float, max_value: float) -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"default": default_value,
		"min": min_value,
		"max": max_value,
		"range": Vector2(min_value, max_value),
	}

func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	for prefix in modifier_map:
		var settings: Dictionary = modifier_map[prefix]
		for part_name in settings:
			var modifier: ModelModifier = settings[part_name]
			for prop in modifier.get_property_list():
				if not (int(prop.usage) & PROPERTY_USAGE_STORAGE):
					continue
				if String(prop.name) == "script":
					continue
				properties.append(prop.merged({
					"name": "%s%s/%s" % [prefix, String(part_name), String(prop.name)]
				}, true))
	return properties

func _get(property: StringName) -> Variant:
	var prop := String(property)
	if prop.begins_with("parameters/"):
		var rest := prop.trim_prefix("parameters/")
		if rest.ends_with("/range"):
			var id := rest.trim_suffix("/range")
			return _parameters.get(id, {}).get("range", Vector2(0, 1))
		if rest.ends_with("/default"):
			var id2 := rest.trim_suffix("/default")
			return _parameters.get(id2, {}).get("default", 0.0)
		if _parameter_values.has(rest):
			return _parameter_values[rest]
		return _parameters.get(rest, {}).get("default", 0.0)
	if prop.begins_with("modifiers/parameters/") and prop.ends_with("/visible"):
		var pid := prop.trim_prefix("modifiers/parameters/").trim_suffix("/visible")
		return _parameters.has(pid)
	for prefix in modifier_map:
		if not prop.begins_with(prefix):
			continue
		var modifiers: Dictionary = modifier_map[prefix]
		var segments: PackedStringArray = prop.trim_prefix(prefix).split("/")
		if segments.size() < 2:
			return null
		var modifier: ModelModifier = modifiers.get(StringName(segments[0]))
		if modifier:
			return modifier.get(segments[1])
	return null

func _set(property: StringName, value: Variant) -> bool:
	var prop := String(property)
	if prop.begins_with("parameters/"):
		if prop.ends_with("/range") or prop.ends_with("/default"):
			return false
		var id := prop.trim_prefix("parameters/")
		if not _parameters.has(id):
			return false
		if _pinned_expressions.has(id):
			return true
		_parameter_values[id] = float(value)
		_apply_current_parameters()
		return true
	for prefix in modifier_map:
		if not prop.begins_with(prefix):
			continue
		var modifiers: Dictionary = modifier_map[prefix]
		var segments: PackedStringArray = prop.trim_prefix(prefix).split("/")
		if segments.size() < 2:
			return false
		var modifier: ModelModifier = modifiers.get(StringName(segments[0]))
		if modifier:
			var old_value: Variant = modifier.get(segments[1])
			modifier.set(segments[1], value)
			modifier_updated.emit.call_deferred(property, value, old_value)
			return true
	return false

func _property_get_revert(property: StringName) -> Variant:
	var prop := String(property)
	if prop.begins_with("parameters/") and not prop.ends_with("/range") and not prop.ends_with("/default"):
		var id := prop.trim_prefix("parameters/")
		return _parameters.get(id, {}).get("default", 0.0)
	for prefix in modifier_map:
		if not prop.begins_with(prefix):
			continue
		var segments: PackedStringArray = prop.trim_prefix(prefix).split("/")
		if segments.size() < 2:
			return null
		var settings: ModelModifier = modifier_map[prefix].get(StringName(segments[0]))
		if settings:
			return settings.property_get_revert(segments[1])
	return null

func tracking_updated(tracking_data: Dictionary, _delta: float):
	if not movement_enabled:
		if _face_move_offset != Vector2.ZERO or not is_zero_approx(_face_move_z):
			_face_move_offset = Vector2.ZERO
			_face_move_z = 0.0
			_sync_stage_to_model()
		return
	var movement := face_movement_from_tracking(tracking_data)
	_face_move_offset = face_movement_offset(movement)
	_face_move_z = movement.z
	_sync_stage_to_model()

func apply_parameters(values: Dictionary[String, float]):
	if model == null or not model.is_inside_tree():
		return
	# Mixer may call with {}; keep last blueprint-driven values instead of resetting.
	if not values.is_empty():
		for key in values.keys():
			var id := String(key)
			if _pinned_expressions.has(id):
				continue
			_parameter_values[id] = float(values[key])
	_apply_current_parameters()

func _apply_blendshape_param(param_name: String, weight: float) -> void:
	var blend_meshes: Array = blendshapes_meshes.get(param_name, [])
	for path in blend_meshes:
		var node_path: NodePath = path
		var mesh_node: Node = model.get_node_or_null(NodePath(node_path.get_concatenated_names()))
		if mesh_node == null:
			mesh_node = model.get_node_or_null(node_path)
		if mesh_node == null:
			continue
		var morph := String(node_path.get_concatenated_subnames())
		if morph.is_empty():
			morph = String(node_path.get_subname(0))
		if morph.is_empty():
			morph = param_name
		mesh_node.set("blend_shapes/%s" % morph, weight)

func _apply_current_parameters() -> void:
	if model == null or not model.is_inside_tree():
		return

	# Rest morphs first, then expression presets so they win (RESET keys are 0 and
	# would otherwise clobber Set Expression after dictionary insertion order).
	var expr_set: Dictionary = {}
	for expr in _expression_names:
		expr_set[expr] = true
	for param_name in _parameter_values.keys():
		if param_name.begins_with("headRot") or expr_set.has(param_name):
			continue
		_apply_blendshape_param(String(param_name), float(_parameter_values[param_name]))
	for expr in _expression_names:
		if _parameter_values.has(expr):
			_apply_blendshape_param(String(expr), float(_parameter_values[expr]))
	
	# Head: FaceAngleX→yaw(Y), FaceAngleY→pitch(X), FaceAngleZ→roll(Z); values in degrees.
	var skeleton := _get_skeleton()
	if skeleton == null:
		return
	var has_head := (
		_parameter_values.has("headRotX")
		or _parameter_values.has("headRotY")
		or _parameter_values.has("headRotZ")
	)
	if has_head:
		var head_bone := skeleton.find_bone("Head")
		if head_bone >= 0:
			var pitch := -deg_to_rad(float(_parameter_values.get("headRotY", 0.0)))
			var yaw := deg_to_rad(float(_parameter_values.get("headRotX", 0.0)))
			var roll := deg_to_rad(float(_parameter_values.get("headRotZ", 0.0)))
			skeleton.set_bone_pose_rotation(head_bone, Quaternion.from_euler(Vector3(pitch, yaw, roll)))
	_apply_pose_overrides(skeleton)

func get_expression_controller() -> VrmExpressionController:
	return _expression_controller

func toggle_expression(
	expression_name: String,
	activate: bool = true,
	duration: float = 1.0,
	exclusive: bool = false
) -> void:
	var targets: Dictionary = {}
	if expression_name.is_empty():
		_pinned_expressions.clear()
		for name in _expression_names:
			if _parameter_values.has(name):
				targets[name] = 0.0
		_tween_expression_values(targets, duration)
		return
	if not _parameter_values.has(expression_name) and not _parameters.has(expression_name):
		return
	# Dialog / exclusive: clear every other expression so blendshapes don't stack.
	if activate and exclusive:
		_pinned_expressions.clear()
		_pinned_expressions[expression_name] = true
		for name in _expression_names:
			if name == expression_name:
				continue
			if _parameter_values.has(name) and float(_parameter_values.get(name, 0.0)) != 0.0:
				targets[name] = 0.0
	elif activate and expression_name in _MOOD_EXPRESSIONS:
		for mood in _MOOD_EXPRESSIONS:
			_pinned_expressions.erase(mood)
			if mood == expression_name:
				continue
			if _parameter_values.has(mood) and float(_parameter_values.get(mood, 0.0)) != 0.0:
				targets[mood] = 0.0
		_pinned_expressions[expression_name] = true
	elif not activate:
		_pinned_expressions.erase(expression_name)
	else:
		_pinned_expressions[expression_name] = true
	targets[expression_name] = 1.0 if activate else 0.0
	_tween_expression_values(targets, duration)

func _reset_all_expressions(duration: float) -> void:
	var targets: Dictionary = {}
	for name in _expression_names:
		if _parameter_values.has(name):
			targets[name] = 0.0
	_tween_expression_values(targets, duration)

func _tween_expression_values(targets: Dictionary, duration: float) -> void:
	if targets.is_empty():
		return
	if duration <= 0.0:
		for expression_name in targets.keys():
			_parameter_values[String(expression_name)] = float(targets[expression_name])
		_apply_current_parameters()
		return
	var from: Dictionary = {}
	for expression_name in targets.keys():
		from[expression_name] = float(_parameter_values.get(String(expression_name), 0.0))
	if _expression_tween != null and _expression_tween.is_valid():
		_expression_tween.kill()
	_expression_tween = create_tween()
	_expression_tween.tween_method(
		func(t: float) -> void:
			for expression_name in targets.keys():
				_parameter_values[String(expression_name)] = lerpf(
					float(from[expression_name]),
					float(targets[expression_name]),
					t
				)
			_apply_current_parameters(),
		0.0,
		1.0,
		duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func list_poses() -> PackedStringArray:
	return PoseLibrary.list_poses()

func apply_pose(pose_name: String, duration: float = 0.3) -> void:
	var target: Dictionary = PoseLibrary.get_pose(pose_name)
	_tween_pose_overrides(target, duration)

func reset_pose(duration: float = 0.3) -> void:
	apply_pose(PoseLibrary.NEUTRAL, duration)

func _tween_pose_overrides(target: Dictionary, duration: float) -> void:
	var skeleton := _get_skeleton()
	if skeleton == null:
		return
	# Pose library values are deltas from rest; compose as rest * delta on apply.
	var from: Dictionary = {}
	var all_bones: Dictionary = {}
	for bone_name in _pose_overrides.keys():
		all_bones[bone_name] = true
	for bone_name in target.keys():
		all_bones[bone_name] = true
	for bone_name in all_bones.keys():
		from[bone_name] = _pose_overrides.get(bone_name, Quaternion.IDENTITY)
	var to: Dictionary = {}
	for bone_name in all_bones.keys():
		if target.has(bone_name):
			to[bone_name] = target[bone_name]
		else:
			to[bone_name] = Quaternion.IDENTITY
	if duration <= 0.0:
		_pose_overrides = target.duplicate()
		_apply_pose_overrides(skeleton)
		return
	if _pose_tween != null and _pose_tween.is_valid():
		_pose_tween.kill()
	_pose_tween = create_tween()
	_pose_tween.tween_method(
		func(t: float) -> void:
			_pose_overrides.clear()
			for bone_name in all_bones.keys():
				var blended: Quaternion = (from[bone_name] as Quaternion).slerp(to[bone_name], t)
				if target.has(bone_name):
					_pose_overrides[bone_name] = blended
				else:
					# Keep transient blend toward rest until finished.
					_pose_overrides[bone_name] = blended
			_apply_pose_overrides(skeleton),
		0.0,
		1.0,
		duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pose_tween.finished.connect(func() -> void:
		_pose_overrides = target.duplicate()
		_apply_pose_overrides(skeleton)
	)

func _get_skeleton() -> Skeleton3D:
	if model == null:
		return null
	var named: Skeleton3D = model.get_node_or_null("GeneralSkeleton") as Skeleton3D
	if named != null:
		return named
	var unique_skel: Skeleton3D = model.get_node_or_null("%GeneralSkeleton") as Skeleton3D
	if unique_skel != null:
		return unique_skel
	var found: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	return found[0] as Skeleton3D

func _find_animation_player() -> AnimationPlayer:
	if model == null:
		return null
	var named: AnimationPlayer = model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if named != null:
		return named
	var found: Array[Node] = model.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return null
	return found[0] as AnimationPlayer

func _apply_pose_overrides(skeleton: Skeleton3D = null) -> void:
	if skeleton == null:
		skeleton = _get_skeleton()
	if skeleton == null:
		return
	for bone_name in _pose_overrides.keys():
		if PoseLibrary.is_face_bone(String(bone_name)):
			continue
		var bone_idx := skeleton.find_bone(String(bone_name))
		if bone_idx < 0:
			continue
		var rest_q := skeleton.get_bone_rest(bone_idx).basis.get_rotation_quaternion()
		var delta: Quaternion = _pose_overrides[bone_name]
		skeleton.set_bone_pose_rotation(bone_idx, rest_q * delta)

func get_texture() -> Texture2D:
	return (container.get_child(0).get_child(0) as SubViewport).get_texture()

const _BASE_KEY_ENERGY := 1.15
const _BASE_FILL_ENERGY := 0.45
const _BASE_AMBIENT_ENERGY := 0.9

## Tint key/fill/ambient lights for stage-level lighting controls.
func set_stage_lighting(color: Color, intensity: float) -> void:
	if container == null:
		return
	var key := container.find_child("KeyLight", true, false) as DirectionalLight3D
	var fill := container.find_child("FillLight", true, false) as DirectionalLight3D
	var energy := maxf(intensity, 0.0)
	if key:
		key.light_color = color
		key.light_energy = _BASE_KEY_ENERGY * energy
	if fill:
		fill.light_color = color
		fill.light_energy = _BASE_FILL_ENERGY * energy
	if camera != null and camera.environment != null:
		camera.environment.ambient_light_color = color
		camera.environment.ambient_light_energy = _BASE_AMBIENT_ENERGY * energy
		
func save_model_settings(settings: Dictionary):
	super.save_model_settings(settings)
	settings["modifiers"] = {
		"meshes": Collections.remap(mesh_settings, func (v): return Serializers.ObjSerializer.to_json(v)),
	}

func load_model_settings(settings: Dictionary):
	super.load_model_settings(settings)
	var saved_meshes: Dictionary = settings.get("modifiers", {}).get("meshes", {})
	for mesh_name in mesh_settings:
		var modifier: ModelModifier = mesh_settings[mesh_name]
		var saved: Dictionary = saved_meshes.get(String(mesh_name), {})
		if not saved.is_empty():
			Serializers.ObjSerializer.from_json(saved, modifier)

func apply_modifier(part: Node, modifier: Dictionary):
	var modifiers = get_modifiers(part)
	
	if modifier.type == "Color":
		var prev = modifiers.get("Color", {})
		var albedo: Color = Collections.get_deep([modifier, prev], "colors.albedo", Color.WHITE)
		var emission: Color = Collections.get_deep([modifier, prev], "colors.emission", Color.WHITE)
		var enabled: bool = Collections.get_deep([modifier, prev], "enabled", false)
		modifiers["Color"] = {
			"enabled": enabled,
			"colors": {
				"albedo": albedo,
				"emission": emission
			}
		}
		
		var m = part as MeshInstance3D
		var count = m.mesh.get_surface_count()
		if enabled:
			for i in range(count):
				var mat: BaseMaterial3D = m.mesh.surface_get_material(i)
				var override_mat = mat.duplicate()
				m.set_surface_override_material(i, override_mat)
				override_mat.albedo_color = albedo
				override_mat.emission = emission
		else:
			for i in range(count):
				m.set_surface_override_material(i, null)
		# Rebuilding overrides drops whatever transparent AA wrote into them.
		apply_transparent_aa()
	
	part.set_meta("modifiers", modifiers)
	
func get_modifiers(part: Node):
	return part.get_meta("modifiers", {
		"Color": {
			"enabled": false,
			"colors": {
				"albedo": Color.WHITE,
				"emission": Color.WHITE,
			}
		}
	})

func get_idle_animation_player() -> AnimationPlayer:
	return _find_animation_player()
	
func get_animation_player() -> AnimationPlayer:
	return null
	
