extends RefCounted

const PREMULT_MATERIAL := preload("res://lib/rendering/premult_alpha_viewport_material.tres")

## Transparent-edge AA for the VRM model viewport.
##
## Do not put `render_mode alpha_to_coverage` on shared MToon cutout shaders. VRM clothing
## often uses the cutout shader with non-binary albedo alpha; A2C then treats that as coverage
## and punches holes through jackets, sleeves, and layered meshes.

## Supersampling factor for the model viewport: the downsample averages premultiplied colour
## and alpha together, which is what actually smooths cutout hair and outline edges.
const SUPERSAMPLE_SCALE := 2.0

## Godot resolves transparent_bg viewports with premultiplied alpha. Over a transparent window
## the compositor expects exactly that, so the container must pass it through unmodified;
## straight-alpha blending would multiply by alpha a second time.
static func apply_viewport_container(
	container: SubViewportContainer,
	enabled: bool,
	transparent_window: bool,
) -> void:
	if container == null:
		return
	if enabled and transparent_window:
		container.material = PREMULT_MATERIAL
	else:
		container.material = null

## Supersample the 3D render and downsample back to viewport size. Unlike alpha-to-coverage this
## antialiases the alpha channel itself, so cutout silhouettes stay smooth over a transparent
## background. TAA is force-disabled here: its temporal resolve writes alpha = 1.0 to every pixel,
## which turns a transparent_bg viewport into an opaque black rect.
static func apply_subviewport(vp: SubViewport, enabled: bool) -> void:
	if vp == null:
		return
	vp.use_taa = false
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = SUPERSAMPLE_SCALE if enabled else 1.0

## Alpha-to-coverage needs multisampling; with a single sample it degrades to a 0.5 alpha test.
static func supports_alpha_to_coverage(msaa: Viewport.MSAA) -> bool:
	return msaa != Viewport.MSAA.MSAA_DISABLED

static func apply_materials(root: Node, enabled: bool) -> void:
	if root == null:
		return
	_walk_node(root, enabled)

static func _walk_node(node: Node, enabled: bool) -> void:
	if node is MeshInstance3D:
		_apply_mesh(node as MeshInstance3D, enabled)
	for child in node.get_children():
		_walk_node(child, enabled)

static func _apply_mesh(mesh_instance: MeshInstance3D, enabled: bool) -> void:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return
	for surface_idx in mesh.get_surface_count():
		var override_mat: Material = mesh_instance.get_surface_override_material(surface_idx)
		var source_mat: Material = override_mat
		if source_mat == null:
			source_mat = mesh.surface_get_material(surface_idx)
		if source_mat == null:
			continue
		# Only StandardMaterial3D cutouts get per-material A2C. MToon is ShaderMaterial and
		# must keep the original cutout discard path so clothing alpha does not become holes.
		if not (source_mat is BaseMaterial3D):
			continue
		var mat: Material = override_mat
		if mat == null:
			mat = _duplicate_material(source_mat)
			mesh_instance.set_surface_override_material(surface_idx, mat)
		_apply_material(mat, enabled)

## Material.duplicate() is shallow, so the outline shell hanging off next_pass would stay shared
## with the imported material (and with every other model loaded from the same file).
static func _duplicate_material(source: Material) -> Material:
	var copy: Material = source.duplicate()
	if source.next_pass != null:
		copy.next_pass = _duplicate_material(source.next_pass)
	return copy

## MToon hangs outlines off next_pass; they carry the same cutout and need the same treatment.
static func _apply_material(mat: Material, enabled: bool) -> void:
	var current: Material = mat
	while current != null:
		if current is BaseMaterial3D:
			_apply_base_material(current as BaseMaterial3D, enabled)
		elif current is ShaderMaterial:
			var shader_mat := current as ShaderMaterial
			if _shader_has_uniform(shader_mat, "_TransparentAa"):
				shader_mat.set_shader_parameter("_TransparentAa", 1.0 if enabled else 0.0)
		current = current.next_pass

static func _apply_base_material(base_mat: BaseMaterial3D, enabled: bool) -> void:
	# alpha_antialiasing_* is ignored unless the material actually cuts out fragments.
	if base_mat.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR \
		and base_mat.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_HASH:
		return
	base_mat.alpha_antialiasing_mode = (
		BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		if enabled
		else BaseMaterial3D.ALPHA_ANTIALIASING_OFF
	)
	base_mat.alpha_antialiasing_edge = 0.35 if enabled else 0.0

static func _shader_has_uniform(shader_mat: ShaderMaterial, uniform_name: String) -> bool:
	var shader: Shader = shader_mat.shader
	if shader == null:
		return false
	for uniform_info in shader.get_shader_uniform_list():
		if uniform_info.name == uniform_name:
			return true
	return false
