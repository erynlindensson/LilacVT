extends RefCounted
## Built-in humanoid body poses for VRM.
## Values are euler deltas (degrees) composed as rest * delta on the skeleton.
## Calibrated for Godot humanoid-retargeted VRM (bone +Y along limb; arm raise/lower = local X).
## Face bones (Head / eyes) are never overridden so tracking keeps working.

const NEUTRAL := "Neutral"

const _FACE_BONES: PackedStringArray = [
	"Head", "Neck", "LeftEye", "RightEye", "Jaw",
]

## pose_name → { bone_name: Vector3(euler_degrees) }  — deltas from rest
const _POSE_EULERS: Dictionary = {
	"Neutral": {},
	# Raise right arm; slight elbow bend for a wave silhouette.
	"Wave": {
		"RightUpperArm": Vector3(-100.0, 0.0, 0.0),
		"RightLowerArm": Vector3(-35.0, 0.0, 0.0),
		"RightHand": Vector3(0.0, 0.0, -15.0),
	},
	# Both arms down from T-pose; elbow bend is local Z (mirrored), not X —
	# X flexion swings the forearm behind the torso on Godot-retargeted VRMs.
	"HandsOnHips": {
		"LeftUpperArm": Vector3(50.0, 0.0, 0.0),
		"LeftLowerArm": Vector3(0.0, 0.0, -70.0),
		"LeftHand": Vector3(0.0, 0.0, 10.0),
		"RightUpperArm": Vector3(50.0, 0.0, 0.0),
		"RightLowerArm": Vector3(0.0, 0.0, 70.0),
		"RightHand": Vector3(0.0, 0.0, -10.0),
	},
	"ArmsCrossed": {
		"LeftUpperArm": Vector3(45.0, -15.0, 20.0),
		"LeftLowerArm": Vector3(0.0, 0.0, -95.0),
		"LeftHand": Vector3(0.0, 0.0, 15.0),
		"RightUpperArm": Vector3(45.0, 15.0, -20.0),
		"RightLowerArm": Vector3(0.0, 0.0, 95.0),
		"RightHand": Vector3(0.0, 0.0, -15.0),
	},
	"Thinking": {
		"RightUpperArm": Vector3(-45.0, 15.0, -20.0),
		"RightLowerArm": Vector3(0.0, 0.0, 90.0),
		"RightHand": Vector3(10.0, 0.0, -25.0),
		"LeftUpperArm": Vector3(40.0, 0.0, 0.0),
		"LeftLowerArm": Vector3(0.0, 0.0, 25.0),
	},
	"Point": {
		"RightUpperArm": Vector3(10.0, -25.0, -40.0),
		"RightLowerArm": Vector3(0.0, 0.0, 15.0),
		"RightHand": Vector3(0.0, 0.0, -5.0),
		"LeftUpperArm": Vector3(45.0, 0.0, 0.0),
		"LeftLowerArm": Vector3(0.0, 0.0, 25.0),
	},
}

static func list_poses() -> PackedStringArray:
	var names := PackedStringArray()
	names.append(NEUTRAL)
	for key in _POSE_EULERS.keys():
		if String(key) == NEUTRAL:
			continue
		names.append(String(key))
	return names

static func get_pose(pose_name: String) -> Dictionary:
	var eulers: Dictionary = _POSE_EULERS.get(pose_name, {})
	var out: Dictionary = {}
	for bone_name in eulers.keys():
		if is_face_bone(String(bone_name)):
			continue
		var deg: Vector3 = eulers[bone_name]
		out[String(bone_name)] = Quaternion.from_euler(Vector3(
			deg_to_rad(deg.x),
			deg_to_rad(deg.y),
			deg_to_rad(deg.z)
		))
	return out

static func is_face_bone(bone_name: String) -> bool:
	return bone_name in _FACE_BONES
