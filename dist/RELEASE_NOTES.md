# OpenVT Lilac v0.1.6 — Linux x86_64

- Artifact: `open-vt-0.1.6-linux-x86_64.tar.gz`
- SHA256: `ba869cdd9126cf40e2495d07f66aa00ca2368a64c197921c191e7720156fabc6`

## Changes

- **Open File…** — import and spawn a local `.model3.json` or `.vrm` from the model panel.
- **Free Live2D catalog** — in-app browser for official sample models.
- **Face movement** — FacePosition X/Y/Z drives Live2D offset/scale and VRM stage motion when movement is enabled.
- **Persist items** — spawned accessories restore across launches.
- **OSF smoothing** — 1€ filter slider in OpenSeeFace camera settings.
- **Live2D physics** — strength / mode / per-group controls in Model Settings.
- **Godot Dark** — fifth UI palette alongside Lilac, Classic, Rose, and Slate.
- **Mediapipe (Experimental)** — Face Landmarker on AVX CPUs only; hidden otherwise (wheels SIGILL without AVX). Use OpenSeeFace on this class of CPU.
- **Blueprint tabs** — double-click a tab to rename, enable, or delete.
- **VTS colors** — deserialize `{r,g,b,a}` dictionaries from vtube.json.
- **VRM quality** — antialiasing, anisotropic filtering, and optional transparent SSAA (from post-0.1.5 main).
- Carries forward v0.1.5 themes, SpinBox arrows, Live2D poses, and OpenSeeFace first-launch setup.

## Requirements for tracking

- `python3` and `python3-venv` (Debian/Ubuntu: `sudo apt install python3-venv`)
- First OpenSeeFace start needs internet for `pip install` of numpy/opencv/onnxruntime/Pillow
- MediaPipe (AVX CPUs only) uses a separate venv via `scripts/setup_mediapipe.sh` or first Start Tracking

## Smoke

- [ ] Fresh extract → first run creates `thirdparty/openseeface/.venv` if needed
- [ ] OpenSeeFace Start Tracking moves the model; smoothing slider damps jitter
- [ ] Mediapipe option is absent on no-AVX CPUs, present on AVX
- [ ] Open File… loads a Live2D or VRM and spawns it
- [ ] Spawned item still present after restart
- [ ] Face movement unlocked → head X/Y shifts the model; lock keeps it planted
- [ ] UI Theme includes Godot Dark
- [ ] `Ayagami blend modes registered` on boot
