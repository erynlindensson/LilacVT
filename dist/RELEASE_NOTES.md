# LilacVT v0.1.7 — Linux x86_64

- Artifact: `lilacvt-0.1.7-linux-x86_64.tar.gz`
- SHA256: `76453210397446175b9c3062de904cce4fac446f39363f3930d233f9517e9ec8`

## Changes

- **Renamed to LilacVT** — independent fork of [open-vt](https://github.com/erodozer/open-vt) with its own roadmap; GitHub repo is [erynlindensson/LilacVT](https://github.com/erynlindensson/LilacVT).
- **New splash** — LilacVT wordmark on boot.
- **Live2D physics** — rebuilt Ayagami `.so` with Cubism-faithful global strength and per-group pendulum controls (0 disables a group). Missing physics files no longer panic.
- **MIT LICENSE** — dual copyright for upstream open-vt and LilacVT modifications.
- Carries forward v0.1.6 studio work (Open File, catalogs, face movement, item persistence, OSF smoothing, MediaPipe-on-AVX, themes).

## Requirements for tracking

- `python3` and `python3-venv` (Debian/Ubuntu: `sudo apt install python3-venv`)
- First OpenSeeFace start needs internet for `pip install` of numpy/opencv/onnxruntime/Pillow
- MediaPipe (AVX CPUs only) uses a separate venv via `scripts/setup_mediapipe.sh` or first Start Tracking

## Smoke

- [ ] Window title / splash say LilacVT
- [ ] Fresh extract → first run creates `thirdparty/openseeface/.venv` if needed
- [ ] Live2D Model Settings physics groups change bounce independently
- [ ] Mediapipe option is absent on no-AVX CPUs, present on AVX
- [ ] `Ayagami blend modes registered` on boot
