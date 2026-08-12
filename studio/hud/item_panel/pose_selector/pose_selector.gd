extends ConfirmationDialog

const VtModel = preload("res://lib/model/vt_model.gd")

var item: VtModel

func _ready() -> void:
	if item == null or not item.has_method("list_poses"):
		%Poses.add_item("No poses")
		%Poses.disabled = true
		get_ok_button().disabled = true
		return
	var poses: PackedStringArray = item.list_poses()
	if poses.is_empty():
		%Poses.add_item("No poses")
		%Poses.disabled = true
		get_ok_button().disabled = true
		return
	for pose_name in poses:
		var idx: int = %Poses.item_count
		%Poses.add_item(pose_name)
		%Poses.set_item_metadata(idx, pose_name)

func _on_confirmed() -> void:
	var selected = %Poses.get_selected_metadata()
	if selected == null:
		close_requested.emit()
		return
	var pose_name := String(selected)
	if pose_name == "Neutral" and item.has_method("reset_pose"):
		item.reset_pose(%Duration.value)
	elif item.has_method("apply_pose"):
		item.apply_pose(pose_name, %Duration.value)
	close_requested.emit()

func _on_canceled() -> void:
	close_requested.emit()

func _on_close_requested() -> void:
	queue_free()
