extends "res://lib/model/modifier.gd"

var mesh: MeshInstance3D

@export var visible: bool = true:
	set(v):
		visible = v
		if mesh != null:
			mesh.visible = v

func _init(m: MeshInstance3D) -> void:
	mesh = m
	if mesh != null:
		visible = mesh.visible
