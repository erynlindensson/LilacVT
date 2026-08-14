extends SceneTree
## Headless test for VTS dictionary + HTML color deserialize.

class Dummy extends RefCounted:
	@export var tint: Color = Color.WHITE
	@export var offset: Vector2 = Vector2.ZERO

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var Serializers = load("res://lib/utils/serializers.gd")
	var ser = Serializers.ObjSerializer

	var html_target := Dummy.new()
	ser.from_json({"tint": "ff3366ff", "offset": {"x": 2.0, "y": 3.0}}, html_target)
	assert(absf(html_target.tint.r - 1.0) < 0.02)
	assert(absf(html_target.tint.g - 0.2) < 0.05)
	assert(is_equal_approx(html_target.offset.x, 2.0))
	assert(is_equal_approx(html_target.offset.y, 3.0))

	var dict_target := Dummy.new()
	ser.from_json({"tint": {"r": 0.25, "g": 0.5, "b": 0.75, "a": 0.5}}, dict_target)
	assert(is_equal_approx(dict_target.tint.r, 0.25))
	assert(is_equal_approx(dict_target.tint.g, 0.5))
	assert(is_equal_approx(dict_target.tint.b, 0.75))
	assert(is_equal_approx(dict_target.tint.a, 0.5))

	var missing := Dummy.new()
	missing.tint = Color.BLACK
	ser.from_json({}, missing)
	assert(missing.tint == Color.BLACK)

	print("serializers_color_ok")
	quit(0)
