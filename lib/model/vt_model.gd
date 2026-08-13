# System for loading models from VTubeStudio's format
# and spawning them into the scene to be managed
@abstract extends "res://lib/vtobject.gd"

const Files = preload("res://lib/utils/files.gd")
const ExpressionController = preload("./parameters/expression_value_provider.gd")
const Tracker = preload("res://lib/tracking/tracker.gd")
const ModelMeta = preload("./metadata.gd")
const Serializers = preload("res://lib/utils/serializers.gd")
const TransparentAa = preload("res://lib/rendering/transparent_aa.gd")

var modelmeta: ModelMeta
@onready var mixer = %Mixer

var motions: Array :
	get():
		var anim = get_animation_player()
		if anim == null:
			return []
		return anim.get_animation_list()

@export var smoothing: bool = false :
	set(v):
		smoothing = v
		_adjust_filter()

var blueprints: Array :
	get():
		return %Actions.get_children()
	set(graphs):
		for g in graphs:
			if g.get_parent():
				g.reparent(%Actions)
			else:
				%Actions.add_child(g)
			g.visible = false
			
var texture : Texture2D
# item pinning
var rest_anchors: Dictionary = {}

# movement transforms
var movement_enabled: bool = false
var movement_scale: Vector3 = Vector3.ZERO

var render_msaa: Viewport.MSAA = Viewport.MSAA.MSAA_4X
var render_anisotropic: Viewport.AnisotropicFiltering = Viewport.AnisotropicFiltering.ANISOTROPY_4X
var render_transparent_aa: bool = false

signal initialized
signal loaded

var _loading = false

signal modifier_updated(field: StringName, new_value: Variant, old_value: Variant)

@abstract func is_initialized()
@abstract func get_meshes() -> Array

@abstract func _build_model()

func is_bound(parameter: Dictionary) -> bool:
	return has_node(parameter.id)

func _load_model():
	_loading = true
	
	if not (await _build_model()):
		queue_free()
		_loading = false
		loaded.emit()
		return 
	
	_load_settings()
	
	_loading = false
	loaded.emit()
	initialized.emit()
	
	BlueprintManager.register_graph(self)
		
@abstract func get_parameters() -> Dictionary
@abstract func get_idle_animation_player() -> AnimationPlayer
@abstract func get_animation_player() -> AnimationPlayer
@abstract func tracking_updated(tracking_data: Dictionary, _delta: float)
func _adjust_filter():
	pass
	
func hydrate(_settings: Dictionary):
	await _load_model()

func load_model_settings(settings: Dictionary):
	self.scale = Vector2.ONE * settings.get("transform", {}).get(
		"scale", 
		clampf(get_viewport_rect().size.y / size.y, 0.001, 2.0)
	)
	self.rotation_degrees = settings.get("transform", {}).get("rotation", 0)
	var quality: Dictionary = settings.get("quality", {})
	render_msaa = msaa_from_string(quality.get("msaa", "4x"))
	render_anisotropic = anisotropic_from_string(quality.get("anisotropic", "4x"))
	texture_filter = texture_filter_for_quality(
		quality.get("filter", "linear") == "nearest",
		render_anisotropic != Viewport.AnisotropicFiltering.ANISOTROPY_DISABLED
	)
	self.smoothing = quality.get("smoothing", false)
	render_transparent_aa = quality.get("transparent_aa", false)
		
	self.position = Serializers.Vec2Serializer.from_json(
		settings.get("transform", {}).get("position", {}),
		get_viewport_rect().get_center()
	)
	apply_render_quality()
		
func save_model_settings(settings: Dictionary):
	settings.merge({
		"quality": {
			"filter": "nearest" if is_nearest_texture_filter(texture_filter) else "linear",
			"smoothing": smoothing,
			"msaa": msaa_to_string(render_msaa),
			"anisotropic": anisotropic_to_string(render_anisotropic),
			"transparent_aa": render_transparent_aa,
		},
		"transform": {
			"position": Serializers.Vec2Serializer.to_json(self.position),
			"scale": self.scale.x,
			"rotation": self.rotation_degrees
		},
		"graphs": blueprints.reduce(
			func (acc, b):
				acc[b.name] = b.serialize()
				return acc,
			{}
		)
	})

static func msaa_from_string(value: String) -> Viewport.MSAA:
	match value.to_lower():
		"off", "disabled", "0":
			return Viewport.MSAA.MSAA_DISABLED
		"2x":
			return Viewport.MSAA.MSAA_2X
		_:
			return Viewport.MSAA.MSAA_4X

static func msaa_to_string(value: Viewport.MSAA) -> String:
	match value:
		Viewport.MSAA.MSAA_DISABLED:
			return "off"
		Viewport.MSAA.MSAA_2X:
			return "2x"
		_:
			return "4x"

static func anisotropic_from_string(value: String) -> Viewport.AnisotropicFiltering:
	match value.to_lower():
		"disabled", "off", "0":
			return Viewport.AnisotropicFiltering.ANISOTROPY_DISABLED
		"2x":
			return Viewport.AnisotropicFiltering.ANISOTROPY_2X
		"8x":
			return Viewport.AnisotropicFiltering.ANISOTROPY_8X
		"16x":
			return Viewport.AnisotropicFiltering.ANISOTROPY_16X
		_:
			return Viewport.AnisotropicFiltering.ANISOTROPY_4X

static func anisotropic_to_string(value: Viewport.AnisotropicFiltering) -> String:
	match value:
		Viewport.AnisotropicFiltering.ANISOTROPY_DISABLED:
			return "disabled"
		Viewport.AnisotropicFiltering.ANISOTROPY_2X:
			return "2x"
		Viewport.AnisotropicFiltering.ANISOTROPY_8X:
			return "8x"
		Viewport.AnisotropicFiltering.ANISOTROPY_16X:
			return "16x"
		_:
			return "4x"

static func is_nearest_texture_filter(filter: CanvasItem.TextureFilter) -> bool:
	return filter == CanvasItem.TEXTURE_FILTER_NEAREST \
		or filter == CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS \
		or filter == CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC

static func texture_filter_for_quality(nearest: bool, anisotropic: bool) -> CanvasItem.TextureFilter:
	if nearest:
		return CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC if anisotropic \
			else CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC if anisotropic \
		else CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func apply_render_quality() -> void:
	var stage_node := get_tree().get_first_node_in_group("system:stage")
	if stage_node != null and stage_node.has_method("apply_viewport_quality"):
		stage_node.apply_viewport_quality(render_msaa, render_anisotropic)
	_apply_model_viewport_quality()
	apply_transparent_aa()

func apply_transparent_aa() -> void:
	_apply_transparent_aa_impl()

func _transparent_window_for_compositing() -> bool:
	var stage_node := get_tree().get_first_node_in_group("system:stage")
	if stage_node != null and stage_node.has_method("is_transparent_window"):
		return stage_node.is_transparent_window()
	return false

## Alpha-to-coverage resolves against MSAA samples, so it is a no-op without multisampling.
## Supersampling and premultiplied compositing do not depend on it.
func alpha_to_coverage_enabled() -> bool:
	return render_transparent_aa and TransparentAa.supports_alpha_to_coverage(render_msaa)

func _apply_model_viewport_quality() -> void:
	pass

func _apply_transparent_aa_impl() -> void:
	pass

## load open-vt specific settings
func _load_settings():
	var model_preferences = Files.read_json(modelmeta.openvt_parameters)
	load_model_settings(model_preferences)

func save_settings(_settings: Dictionary):
	if not is_initialized():
		return
	
	var model_data = {}
	
	self.save_model_settings(model_data)
	for o in get_tree().get_nodes_in_group("persist:model"):
		o.save_settings(model_data)
	
	Files.write_json(modelmeta.openvt_parameters, model_data)
