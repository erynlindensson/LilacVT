#!/usr/bin/env python3
"""Webcam face tracking for OpenVT via Google MediaPipe Face Landmarker.

The official MediaPipe pip wheel is compiled with AVX. Importing it on
CPUs without AVX (Celeron/Pentium Jasper Lake, etc.) SIGILLs with:
  FATAL ERROR: This binary was compiled with avx enabled...

OpenVT only offers this tracker when the CPU has AVX. OpenSeeFace is the
webcam tracker on machines without it.
"""
from __future__ import annotations

import argparse
import json
import math
import socket
import sys
import time
from pathlib import Path

import cv2
import numpy as np

HERE = Path(__file__).resolve().parent
DEFAULT_MP_MODEL = HERE / "models" / "face_landmarker.task"


def clamp(value: float, lo: float, hi: float) -> float:
	return max(lo, min(hi, value))


def cpu_has_avx() -> bool:
	try:
		with open("/proc/cpuinfo", encoding="utf-8") as cpuinfo:
			for line in cpuinfo:
				if line.startswith("flags") or line.startswith("Features"):
					return " avx " in f" {line.strip()} "
	except OSError:
		pass
	return False


def rotation_matrix_to_ypr(r: np.ndarray) -> tuple[float, float, float]:
	sy = math.sqrt(float(r[0, 0]) ** 2 + float(r[1, 0]) ** 2)
	if sy > 1e-6:
		pitch = math.atan2(float(r[2, 1]), float(r[2, 2]))
		yaw = math.atan2(-float(r[2, 0]), sy)
		roll = math.atan2(float(r[1, 0]), float(r[0, 0]))
	else:
		pitch = math.atan2(-float(r[1, 2]), float(r[1, 1]))
		yaw = math.atan2(-float(r[2, 0]), sy)
		roll = 0.0
	return math.degrees(yaw), math.degrees(pitch), math.degrees(roll)


def blendshape_map(categories) -> dict[str, float]:
	out: dict[str, float] = {}
	for cat in categories:
		out[str(cat.category_name)] = float(cat.score)
	return out


def bs(values: dict[str, float], name: str, default: float = 0.0) -> float:
	return float(values.get(name, default))


def to_openvt_mediapipe(blendshapes: dict[str, float], matrix: np.ndarray) -> dict[str, float]:
	r = matrix[:3, :3]
	t = matrix[:3, 3]
	yaw, pitch, roll = rotation_matrix_to_ypr(r)
	eye_open_l = 1.0 - bs(blendshapes, "eyeBlinkLeft")
	eye_open_r = 1.0 - bs(blendshapes, "eyeBlinkRight")
	mouth_open = bs(blendshapes, "jawOpen")
	mouth_smile = 0.5 * (bs(blendshapes, "mouthSmileLeft") + bs(blendshapes, "mouthSmileRight"))
	brows = clamp(
		bs(blendshapes, "browInnerUp")
		- 0.5 * (bs(blendshapes, "browDownLeft") + bs(blendshapes, "browDownRight")),
		0.0,
		1.0,
	)
	return {
		"FacePositionX": clamp(float(t[0]) * 10.0, -15.0, 15.0),
		"FacePositionY": clamp(float(t[1]) * 10.0, -15.0, 15.0),
		"FacePositionZ": clamp(-float(t[2]) * 8.0, -10.0, 10.0),
		"FaceAngleX": clamp(yaw, -30.0, 30.0),
		"FaceAngleY": clamp(-pitch, -30.0, 30.0),
		"FaceAngleZ": clamp(roll, -30.0, 30.0),
		"MouthOpen": clamp(mouth_open, 0.0, 1.0),
		"MouthSmile": clamp(mouth_smile, 0.0, 1.0),
		"MouthX": clamp(bs(blendshapes, "mouthLeft") - bs(blendshapes, "mouthRight"), -1.0, 1.0),
		"Brows": brows,
		"BrowLeftY": clamp(bs(blendshapes, "browInnerUp") - bs(blendshapes, "browDownLeft"), -1.0, 1.0),
		"BrowRightY": clamp(bs(blendshapes, "browInnerUp") - bs(blendshapes, "browDownRight"), -1.0, 1.0),
		"EyeOpenLeft": clamp(eye_open_l, 0.0, 1.0),
		"EyeOpenRight": clamp(eye_open_r, 0.0, 1.0),
		"EyeLeftX": clamp(bs(blendshapes, "eyeLookOutLeft") - bs(blendshapes, "eyeLookInLeft"), -1.0, 1.0),
		"EyeLeftY": clamp(bs(blendshapes, "eyeLookUpLeft") - bs(blendshapes, "eyeLookDownLeft"), -1.0, 1.0),
		"EyeRightX": clamp(bs(blendshapes, "eyeLookOutRight") - bs(blendshapes, "eyeLookInRight"), -1.0, 1.0),
		"EyeRightY": clamp(bs(blendshapes, "eyeLookUpRight") - bs(blendshapes, "eyeLookDownRight"), -1.0, 1.0),
		"CheekPuff": clamp(bs(blendshapes, "cheekPuff"), 0.0, 1.0),
		"TongueOut": clamp(bs(blendshapes, "tongueOut"), 0.0, 1.0),
	}


def parse_args() -> argparse.Namespace:
	parser = argparse.ArgumentParser(description="OpenVT MediaPipe face tracker")
	parser.add_argument("-c", "--capture", type=int, default=0, help="camera index")
	parser.add_argument("-i", "--ip", default="127.0.0.1", help="UDP destination host")
	parser.add_argument("-p", "--port", type=int, default=11574, help="UDP destination port")
	parser.add_argument("-W", "--width", type=int, default=1280)
	parser.add_argument("-H", "--height", type=int, default=720)
	parser.add_argument("--model", default=str(DEFAULT_MP_MODEL), help="face_landmarker.task path")
	parser.add_argument("--silent", type=int, default=0)
	return parser.parse_args()


def run_mediapipe(args: argparse.Namespace, sock: socket.socket, dest: tuple, cap: cv2.VideoCapture) -> int:
	import mediapipe as mp
	from mediapipe.tasks import python
	from mediapipe.tasks.python import vision

	model_path = Path(args.model)
	if not model_path.is_file():
		print(f"error: Face Landmarker model missing at {model_path}", file=sys.stderr)
		print("run scripts/setup_mediapipe.sh", file=sys.stderr)
		return 1
	options = vision.FaceLandmarkerOptions(
		base_options=python.BaseOptions(model_asset_path=str(model_path)),
		running_mode=vision.RunningMode.VIDEO,
		output_face_blendshapes=True,
		output_facial_transformation_matrixes=True,
		num_faces=1,
	)
	landmarker = vision.FaceLandmarker.create_from_options(options)
	start = time.time()
	try:
		while True:
			ok, frame = cap.read()
			if not ok:
				time.sleep(0.01)
				continue
			rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
			mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
			timestamp_ms = int((time.time() - start) * 1000.0)
			result = landmarker.detect_for_video(mp_image, timestamp_ms)
			if not result.face_blendshapes or not result.facial_transformation_matrixes:
				continue
			packet = to_openvt_mediapipe(
				blendshape_map(result.face_blendshapes[0]),
				np.array(result.facial_transformation_matrixes[0], dtype=np.float64),
			)
			sock.sendto(json.dumps(packet, separators=(",", ":")).encode("utf-8"), dest)
	except KeyboardInterrupt:
		return 0
	finally:
		landmarker.close()
	return 0


def main() -> int:
	if not cpu_has_avx():
		print(
			"error: this CPU has no AVX. MediaPipe wheels SIGILL here. Use OpenSeeFace instead.",
			file=sys.stderr,
		)
		return 1
	args = parse_args()
	cap = cv2.VideoCapture(args.capture)
	if not cap.isOpened():
		print(f"error: could not open camera {args.capture}", file=sys.stderr)
		return 1
	cap.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
	cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
	sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
	dest = (args.ip, args.port)
	if not args.silent:
		print(
			f"Face tracking backend=mediapipe camera={args.capture} -> {args.ip}:{args.port}",
			file=sys.stderr,
		)
	try:
		return run_mediapipe(args, sock, dest, cap)
	finally:
		cap.release()
		sock.close()


if __name__ == "__main__":
	sys.exit(main())
