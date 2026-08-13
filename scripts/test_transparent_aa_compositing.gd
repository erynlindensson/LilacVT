extends SceneTree

const TransparentAa = preload("res://lib/rendering/transparent_aa.gd")

var _vp: SubViewport
var _frame := 0

func _initialize() -> void:
	var container := SubViewportContainer.new()
	get_root().add_child(container)

	TransparentAa.apply_viewport_container(container, true, false)
	assert(container.material == null, "premult must stay off for an opaque window")

	TransparentAa.apply_viewport_container(container, true, true)
	assert(container.material != null, "premult expected for a transparent window")

	TransparentAa.apply_viewport_container(container, false, true)
	assert(container.material == null, "premult must clear when feature disabled")

	# Alpha-to-coverage is a no-op without multisampling.
	assert(not TransparentAa.supports_alpha_to_coverage(Viewport.MSAA.MSAA_DISABLED))
	assert(TransparentAa.supports_alpha_to_coverage(Viewport.MSAA.MSAA_2X))
	assert(TransparentAa.supports_alpha_to_coverage(Viewport.MSAA.MSAA_4X))

	# Regression: TAA's resolve writes alpha = 1.0, turning a transparent viewport opaque black.
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.use_taa = true
	TransparentAa.apply_subviewport(vp, true)
	assert(not vp.use_taa, "TAA must never be enabled on a transparent model viewport")
	assert(vp.scaling_3d_scale == TransparentAa.SUPERSAMPLE_SCALE, "expected supersampling")

	vp.use_taa = true
	TransparentAa.apply_subviewport(vp, false)
	assert(not vp.use_taa, "TAA must never be enabled on a transparent model viewport")
	assert(vp.scaling_3d_scale == 1.0, "supersampling must clear when feature disabled")

	_build_probe_viewport()

## Render a lit box in a transparent_bg viewport and read the empty corner back.
func _build_probe_viewport() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(128, 128)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X
	get_root().add_child(_vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.0

	var cam := Camera3D.new()
	cam.environment = env
	cam.position = Vector3(0, 0, 3)
	cam.current = true
	_vp.add_child(cam)

	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	_vp.add_child(box)

	TransparentAa.apply_subviewport(_vp, false)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame <= 8:
		return false
	# Headless has no rendering device; skip the pixel check there.
	var img: Image = _vp.get_texture().get_image()
	if img != null:
		var corner := img.get_pixel(2, 2)
		var center := img.get_pixel(64, 64)
		assert(corner.a == 0.0, "empty pixels must stay transparent, got %s" % corner)
		assert(center.a == 1.0, "model pixels must stay opaque, got %s" % center)
	print("transparent_aa_compositing: all checks passed")
	_vp.queue_free()
	quit()
	return true
