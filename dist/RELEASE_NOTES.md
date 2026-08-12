# OpenVT Lilac v0.1.5 — Linux x86_64

- Artifact: `open-vt-0.1.5-linux-x86_64.tar.gz`
- SHA256: _(filled after package)_

## Changes

- **Pickable UI themes** — Lilac (default), Classic, Rose, Slate in Camera → Application Settings; live remapping through the project theme.
- **SpinBox arrows** — compact stacked up/down icons that survive theme apply (no missing/giant placeholders).
- **Live2D Set Pose** — lists model motions (plus Neutral); Set Expression stays `.exp3.json`-only (“No Expressions Present” when none).
- **Ayagami rebuild** — opacity clamp + canvas-sized mask viewports for motion white-out (debug + release `.so`).
- Carries forward v0.1.4 OpenSeeFace bundling / first-launch setup.

## Requirements for tracking

- `python3` and `python3-venv` (Debian/Ubuntu: `sudo apt install python3-venv`)
- First launch needs internet for `pip install` of numpy/opencv/onnxruntime/Pillow

## Smoke

- [ ] Fresh extract → first run creates `thirdparty/openseeface/.venv` if needed
- [ ] UI Theme switch updates panels/icons without restart
- [ ] SpinBox arrows sized correctly on Transform fields
- [ ] Live2D Set Pose plays a motion; Haru clipped regions stay textured
- [ ] `Ayagami blend modes registered` on boot
