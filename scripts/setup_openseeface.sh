#!/usr/bin/env bash
# Create/update the local OpenSeeFace venv used by open-vt.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OSF_DIR="$ROOT/thirdparty/openseeface"
VENV="$OSF_DIR/.venv"

if [[ ! -f "$OSF_DIR/facetracker.py" ]]; then
  echo "error: OpenSeeFace sources missing at $OSF_DIR" >&2
  exit 1
fi

if [[ ! -d "$OSF_DIR/models" ]]; then
  echo "error: OpenSeeFace models missing at $OSF_DIR/models" >&2
  exit 1
fi

PYTHON="${PYTHON:-python3}"
if ! command -v "$PYTHON" >/dev/null 2>&1; then
  echo "error: $PYTHON not found" >&2
  exit 1
fi

echo "Using $PYTHON ($( "$PYTHON" --version 2>&1 ))"
if [[ ! -x "$VENV/bin/python" ]]; then
  echo "Creating venv at $VENV"
  "$PYTHON" -m venv "$VENV"
fi

# shellcheck disable=SC1091
source "$VENV/bin/activate"
python -m pip install --upgrade pip
python -m pip install \
  "numpy>=1.21,<2.1" \
  "opencv-python>=4.5" \
  "Pillow>=8.4" \
  "onnxruntime>=1.9"

echo
echo "OpenSeeFace setup complete."
echo "  python: $VENV/bin/python"
echo "  models: $OSF_DIR/models"
echo
echo "Select OpenSeeFace (Webcam) in Camera settings to start tracking."
