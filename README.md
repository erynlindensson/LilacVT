<p align="center">
  <img src="branding/monochrome.svg" width="180" />
</p>
<p align="center"><strong>OpenVT Lilac</strong> — a fork of OpenVT with enhanced VRM support</p>
<p align="center">
  <a href="https://github.com/erynlindensson/openvt-lilac/releases">Releases</a>
  ·
  <a href="https://github.com/erodozer/open-vt">Upstream OpenVT</a>
</p>

<p align="center">
  <img src="branding/screenshot-lilac.png" alt="OpenVT Lilac with selectable Lilac UI theme, VRM avatar, and OpenSeeFace tracking" width="900" />
</p>

## Credits

OpenVT Lilac is built on **[OpenVT](https://github.com/erodozer/open-vt)** by **[erodozer](https://github.com/erodozer)**.
The core Live2D VTubing app, Godot architecture, VTube Studio–oriented workflows, and Linux-first design are their work.
Lilac extends that foundation; please star and support upstream when you can.

## What is Lilac?

[OpenVT](https://github.com/erodozer/open-vt) is open-source software for 2D VTubing (Live2D-first, Godot 4).
**OpenVT Lilac** is a community fork focused on making **VRM avatars** more usable alongside Live2D: face tracking, expressions, simple body poses, scene lighting, pickable UI themes, and a smoother OpenSeeFace setup on Linux.

Latest packaged build: **[v0.1.5](https://github.com/erynlindensson/openvt-lilac/releases/tag/v0.1.5)**.

## Lilac highlights (vs upstream OpenVT)

- **Pickable UI themes** — Camera → Application Settings → **UI Theme** switches Lilac (default), Classic, Rose, or Slate live; upstream OpenVT ships a single beige chrome look.
- **Enhanced VRM support** — model discovery/import into `VrmModels`, viewport lighting, drag/zoom framing, and blueprint defaults for face tracking parameters.
- **OpenSeeFace integration** — facetracker is **vendored** under `thirdparty/openseeface/` with `scripts/setup_openseeface.sh`; tracking starts only when you press **Start Tracking** (not on mode select).
- **Expressions for VRM** — Set Expression lists standard VRM blendshapes (moods, visemes, blinks, customs) and applies them exclusively so morphs do not stack.
- **Easy Poses** — Set Pose next to Expressions with built-in body presets (Neutral, Wave, HandsOnHips, ArmsCrossed, Thinking, Point) that keep head tracking free.
- **Scene lighting controls** — Items panel **Lighting** group: HSV color wheel + intensity for VRM key/fill/ambient lights.
- **Opaque background by default** — toggle **Transparent Background** under Camera → Application Settings when you need OBS alpha capture.
- **Live2D fixes carried forward** — idle/mask white-out isolation and related tracking polish from the Lilac line of work.

Upstream strengths (Linux-native, open source, VTS-oriented assets, pixel filtering, popout controls) still apply.

### Supported trackers

- **OpenSeeFace** — bundled sources + setup script; use **Start Tracking** / **Stop Tracking** in Camera settings (feature tag: `openseeface`)
- **VTube Studio** — TCP over Wi-Fi (phone app), as in upstream

### Differences from closed-source alternatives

- native Linux support
- open source development and community-driven features
- transparent window support for alpha capture in OBS (opt-in in Lilac)
- adjustable filtering for sharper scaling of pixel art models
- multi-window popout controls

### VTube Studio compatibility

OpenVT (and Lilac) strive to stay largely compatible with [VTube Studio](https://denchisoft.com/).
Live2D assets can be shared without renaming; OpenVT-specific settings stay in separate files.
Feature parity with VTS remains a goal, excluding plugins and VNet.

## How is it built?

Most of the VTuber ecosystem uses Unity. OpenVT is built in **Godot 4**, using open-source face tracking and native model libraries, with Linux desktop as a priority.

Lilac keeps that approach: **GDScript** first, latest stable Godot **4.x**, plus vendored **godot-vrm** / **MToon** for VRM and a local OpenSeeFace tree for webcam tracking.

### Guidelines

Prefer Godot built-ins and low dependency overhead. Target the latest stable 4.x editor and export templates for standalone binaries.
Lilac currently builds against a custom Godot build with Ayagami (Live2D) support.

### Building dependencies

Run dependency builds before opening the project so GDExtension libraries are present.

Follow submodule / `thirdparty/` readmes as needed, then:

```bash
./build_dependencies.sh
./scripts/setup_openseeface.sh   # Lilac: OpenSeeFace venv + deps
```

Export Linux package (after a release export):

```bash
godot4-ayagami --headless --path . --export-release linux bin/linux/openvt.x86_64
VERSION=0.1.5 ./scripts/package_linux_release.sh
```

## References

- Upstream OpenVT: https://github.com/erodozer/open-vt
- VTube Studio: https://github.com/DenchiSoft/VTubeStudio
- OpenSeeFace: https://github.com/emilianavt/OpenSeeFace
- godot-vrm: https://github.com/V-Sekai/godot-vrm

## Licensing

Lilac inherits OpenVT’s licensing. Additional third-party licenses are under [`license/`](./license) and bundled release `licenses/`.
Respect Live2D, VRM model, and tracker license terms for any assets you use.
