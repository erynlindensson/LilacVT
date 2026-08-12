# Live2D mask clipping fix (idle / motion white-out)

## Symptom

At rest and with OpenSeeFace tracking, Live2D models look normal. Playing idle or
other motions (e.g. `haru_g_idle`) turns clipped regions into a solid white
silhouette. Setting Idle Animation to **None** restores textures.

## Root cause

Ayagami draws Cubism clip masks into off-screen `SubViewport`s and samples them
as `tex_mask` in the `blend_ayagami_*` shaders. Earlier fixes sized those
viewports from the **mesh AABB** (rest pose, padded, or grow-only quantized).

Idle motion deforms artmeshes beyond that AABB. Fragments whose mask UVs fall
outside `[0,1]` are discarded / fail the clip sample and composite as **opaque
white** under the custom blend modes (not transparent).

Separately, resizing a `SubViewport` mid-flight can invalidate its
`ViewportTexture`, causing flash-then-white — also mitigated by never resizing
after the first lock.

## Fix (ported from Claude isolation)

In `AyagamiModel::update_masks` (`thirdparty/ayagami/src/model.rs`):

1. Size each mask viewport **once** to the model’s Live2D **canvas**
   (`self.size`), not a per-frame AABB.
2. Set `mask_offset` / canvas transform from Cubism **OriginInPixels**:
   canvas top-left in vertex space is `-origin`.
3. `UPDATE_ALWAYS` and rebind `tex_mask` only on that single resize.
4. Never call `set_size` again (`canvas_sized` meta flag).

Loader still creates mask viewports at 32×32; the first `update_masks` expands
them to the canvas and locks.

## Why rest / tracking looked fine

Face tracking and rest pose rarely expand the silhouette past the rest AABB.
Full idle curves (breathing, sway, hair) do — which is why isolation pointed at
motion-only failure.

## Verification

1. Rebuild ayagami release `.so` and install into `addons/ayagami/lib/`.
2. Run patched Godot (`godot4-ayagami`) or an export built with the patched
   template.
3. Load Haru → textures OK at rest → enable OSF → play `haru_g_idle` → clipped
   face/body stay textured (no white silhouette).
4. Idle → None restores cleanly.
