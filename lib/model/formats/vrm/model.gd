extends "../../vt_model.gd"

const Collections = preload("res://lib/utils/collections.gd")

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

var model: Node3D
var container: Node
var vp: SubViewport
var camera: Camera3D

var blendshapes_meshes = {}
## Model-local AABB at rest (ignores runtime position/scale/rotation).
var _rest_aabb: AABB = AABB()


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

func is_initialized():
	return model != null
	
func load_vrm(path: String):
		
	var gltf: GLTFDocument = GLTFDocument.new()
	var vrm_extension: GLTFDocumentExtension = preload("res://addons/vrm/vrm_extension.gd").new()
	gltf.register_gltf_document_extension(vrm_extension, true)
	
	var state: GLTFState = GLTFState.new()
	# state.handle_binary_image = GLTFState.HANDLE_BINARY_EMBED_AS_BASISU

	# Ensure Tangents is required for meshes with blend shapes as of Godot 4.2.
	# EditorSceneFormatImporter.IMPORT_GENERATE_TANGENT_ARRAYS = 8
	# EditorSceneFormatImporter may not be available in release builds, so hardcode 8 for flags
	state.set_additional_data(&"vrm/head_hiding_method", 3)
	state.set_additional_data(&"vrm/first_person_layers", 2)
	state.set_additional_data(&"vrm/third_person_layers", 4)
	
	var err = gltf.append_from_file(path, state, 16 | 8 | 2)
	if err != OK:
		gltf.unregister_gltf_document_extension(vrm_extension)
		return false
	
	var vrm = gltf.generate_scene(state)
	vrm.add_child(XRFaceModifier3D.new())
	vrm.add_child(XRBodyModifier3D.new())
	
	gltf.unregister_gltf_document_extension(vrm_extension)
	
	return vrm
	
func _build_model():
	model = load_vrm(modelmeta.model)
	await get_tree().process_frame
	
	if model == null:
		return false
	
	# scan through animations to build up blendshape parameters
	# Find all the "rest" values to blend with.
	var anim: AnimationPlayer = model.get_node("AnimationPlayer")
	_parameters = {
		# head
		"headRotX": _make_parameter("headRotX", "Head Rotation X", 0.0, -1.0, 1.0),
		"headRotY": _make_parameter("headRotY", "Head Rotation Y", 0.0, -0.5, 0.5),
		"headRotZ": _make_parameter("headRotZ", "Head Rotation Z", 0.0, -0.5, 0.5),
	}
	if anim.has_animation("RESET"):
		var a : Animation = anim.get_animation("RESET")
		for track_index in range(0, a.get_track_count()):
			var track_path : NodePath = a.track_get_path(track_index)
			if a.track_get_type(track_index) == Animation.TYPE_BLEND_SHAPE:
				var blend_shape = track_path.get_subname(0)
				var meshes = blendshapes_meshes.get(blend_shape, [])
				meshes.append(track_path)
				blendshapes_meshes[blend_shape] = meshes
				_parameters[blend_shape] = _make_parameter(
					blend_shape,
					blend_shape,
					a.track_get_key_value(track_index, 0),
					0.0,
					1.0
				)
	vp.add_child(model)
	
	(model.get_node("GeneralSkeleton") as Skeleton3D).reset_bone_poses() # force reset bones
	anim.play("RESET")
	await get_tree().process_frame
	
	_meshes = model.find_children("*", "VisualInstance3D")
	_rest_aabb = _compute_local_aabb()
	
	# Keep a stable 3D render resolution; SubViewportContainer.stretch can otherwise
	# shrink the RT to a tiny control size and break projection/hit-testing.
	vp.size = Vector2i(1280, 720)
	
	# Draggable hit box (defaults to 1x1 which makes VRM undraggable).
	# Size relative to the stage canvas — silhouette-perfect bounds aren't required.
	var stage_size := get_viewport_rect().size
	if stage_size.x < 2.0 or stage_size.y < 2.0:
		stage_size = Vector2(1280, 720)
	size = Vector2(
		maxf(stage_size.x * 0.35, 280.0),
		maxf(stage_size.y * 0.7, 480.0)
	)
	centered = true
	
	# Drive the 3D model from this Node2D's drag/zoom/orbit controls.
	if not transform_updated.is_connected(_on_transform_updated):
		transform_updated.connect(_on_transform_updated)
	set_notify_transform(true)
	_sync_stage_to_model()
	
	return true

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
	var mapped := Vector2(
		stage_position.x / maxf(src_size.x, 1.0) * dst_size.x,
		stage_position.y / maxf(src_size.y, 1.0) * dst_size.y
	)
	if not mapped.is_finite():
		return
	var depth := camera.position.z
	var s := maxf(stage_scale.x, 0.01)
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
		# Live2D / blueprint UI contract
		"range": Vector2(min_value, max_value),
	}
	
func tracking_updated(tracking_data: Dictionary, delta: float):
	pass
	
func apply_parameters(values: Dictionary[String, float]):
	if model == null or not model.is_inside_tree():
		return
	# transform parameters into VRM blendshapes
	for blend_shape in values.keys():
		var blend_meshes = blendshapes_meshes.get(blend_shape, [])
		var weight = values.get(blend_shape, 0.0)
		for path in blend_meshes:
			var m = model.get_node(path)
			m.set("blend_shapes/%s" % blend_shape, weight)
			
	# apply parameters to Bones
	var target: Transform3D = Transform3D(
		Quaternion(
			values.get("headRotY", 0.0),
			values.get("headRotX", 0.0),
			values.get("headRotZ", 0.0),
			1.0
		)
	)
	var skeleton = (model.get_node("GeneralSkeleton") as Skeleton3D)
	
	var head_bone = skeleton.find_bone("Head")
	var neck_bone = skeleton.get_bone_parent(head_bone)
	var neck_transform: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(neck_bone)
	var head_transform: Transform3D = neck_transform.inverse() * target * (
		skeleton.transform * skeleton.get_bone_global_rest(head_bone)
	)
	skeleton.set_bone_pose_rotation(
		head_bone,
		head_transform.basis.get_rotation_quaternion()
	)
	
func get_texture() -> Texture2D:
	return (container.get_child(0).get_child(0) as SubViewport).get_texture()
		
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
	return get_node("AnimationPlayer")
	
func get_animation_player() -> AnimationPlayer:
	return null
	
