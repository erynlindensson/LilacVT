extends SceneTree

const ParameterGrouping = preload("res://lib/blueprints/ui/parameter_grouping.gd")

func _init() -> void:
	var cases := {
		"ParamBrowRX": "Brows",
		"ParamEyeBallX": "Eyes",
		"ParamMouthOpenY": "Mouth",
		"ParamBodyAngleZ": "Body",
		"ParamCheekPuff": "Cheeks",
		"ParamTongueOut": "Tongue",
		"FacePositionZ": "Face",
		"BrowRightY": "Brows",
	}
	for param in cases:
		var got := ParameterGrouping.infer_group(param)
		var want: String = cases[param]
		if got != want:
			printerr("FAIL %s -> %s (want %s)" % [param, got, want])
			quit(1)
			return
	print("parameter_grouping_ok")
	quit(0)
