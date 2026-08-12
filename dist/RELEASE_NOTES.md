# OpenVT Lilac v0.1.4 — Linux x86_64

- Artifact: `open-vt-0.1.4-linux-x86_64.tar.gz`
- SHA256: `9d46c50a8fceaecb226d803803732a7d87807d70d3101b9e1e351f7b4a680cbf`

## Changes

- **Bundle OpenSeeFace** in the release (`thirdparty/openseeface/` + `scripts/setup_openseeface.sh`).
- **Auto-setup on first launch** — creates the Python venv next to the app (requires `python3` / `python3-venv` and network once).
- OSF process looks beside the executable instead of inside the packed `res://` tree.

## Requirements for tracking

- `python3` and `python3-venv` (Debian/Ubuntu: `sudo apt install python3-venv`)
- First launch needs internet for `pip install` of numpy/opencv/onnxruntime/Pillow

## Smoke

- [ ] Fresh extract → first run shows OSF setup toast and creates `thirdparty/openseeface/.venv`
- [ ] Start Tracking works without manually running the setup script
