#!/usr/bin/env bash
# Create/update the local MediaPipe face-tracking venv used by open-vt.
# MediaPipe wheels require AVX. On CPUs without it, use OpenSeeFace instead.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MP_DIR="$ROOT/thirdparty/mediapipe"
VENV="$MP_DIR/.venv"
MODEL_DIR="$MP_DIR/models"
MP_MODEL="$MODEL_DIR/face_landmarker.task"
MP_MODEL_URL="https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task"

has_avx() {
  grep -m1 -E '^flags' /proc/cpuinfo 2>/dev/null | grep -qw avx
}

download() {
  local url="$1"
  local dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -L --fail --retry 3 -o "$dest" "$url"
  else
    python - "$url" "$dest" <<'PY'
import sys, urllib.request
urllib.request.urlretrieve(sys.argv[1], sys.argv[2])
PY
  fi
}

if [[ ! -f "$MP_DIR/facetracker.py" ]]; then
  echo "error: MediaPipe tracker missing at $MP_DIR/facetracker.py" >&2
  exit 1
fi

if ! has_avx; then
  echo "error: this CPU has no AVX. MediaPipe pip wheels SIGILL here." >&2
  echo "Use OpenSeeFace in Camera settings (scripts/setup_openseeface.sh)." >&2
  exit 1
fi

PYTHON="${PYTHON:-python3}"
if ! command -v "$PYTHON" >/dev/null 2>&1; then
  echo "error: $PYTHON not found" >&2
  exit 1
fi

echo "Using $PYTHON ($( "$PYTHON" --version 2>&1 ))"
echo "CPU: AVX available — installing Google MediaPipe."

if [[ ! -x "$VENV/bin/python" ]]; then
  echo "Creating venv at $VENV"
  "$PYTHON" -m venv "$VENV"
fi

# shellcheck disable=SC1091
source "$VENV/bin/activate"
python -m pip install --upgrade pip
python -m pip install \
  "numpy>=1.24,<2.3" \
  "opencv-python>=4.8,<5" \
  "mediapipe>=0.10.14"

mkdir -p "$MODEL_DIR"

if [[ ! -f "$MP_MODEL" ]]; then
  echo "Downloading Face Landmarker model…"
  download "$MP_MODEL_URL" "$MP_MODEL"
  if [[ ! -s "$MP_MODEL" ]]; then
    echo "error: failed to download $MP_MODEL" >&2
    exit 1
  fi
fi

echo
echo "Face tracking setup complete (experimental)."
echo "  python: $VENV/bin/python"
echo "  backend: MediaPipe ($MP_MODEL)"
echo
echo "Select Mediapipe (Experimental) in Camera settings, then press Start Tracking."
