# Live2D mask clipping / idle white-out fix

## Symptom

At rest and with OpenSeeFace tracking, Live2D models look normal. Playing idle or
other motions (e.g. `haru_g_idle`) turns clipped regions into a solid white
silhouette. Setting Idle Animation to **None** restores textures.

## Root causes (Claude isolation)

Two independent issues were isolated; **both** must be present in the build:

### 1. Runaway artmesh opacity (primary white fill)

During idle motion, the vendored ayagami core driver’s form-blend can return
`Visual.opacity` that is non-finite or huge (~1e37) on clipped artmeshes.
Feeding that into `MeshInstance2D.self_modulate.a` saturates the region to
**solid white**. Rest and light tracking never hit those blend combinations.

**Fix:** in `AyagamiModel::update_meshes`, clamp opacity to `[0, 1]` (use `1.0`
if non-finite) before `set_self_modulate`.

### 2. Undersized / thrashing mask viewports

Sizing mask `SubViewport`s from a rest-pose mesh AABB (even padded / grow-only)
lets idle deformation push geometry outside the mask; clipped samples then fail
under `blend_ayagami_*`. Resizing viewports mid-flight can also invalidate
`ViewportTexture`.

**Fix:** in `update_masks`, size each mask viewport **once** to the Live2D
canvas (`self.size`) with `mask_offset = -origin` (canvas top-left in vertex
space), `UPDATE_ALWAYS`, rebind `tex_mask` on that single resize, never
`set_size` again.

## Verification

1. Rebuild ayagami release `.so` and install into `addons/ayagami/lib/`.
2. Fully quit and restart `godot4-ayagami` (extensions don’t hot-reload).
3. Load Haru → rest OK → OSF OK → play `haru_g_idle` → no white silhouette.
4. Idle → None restores cleanly.
