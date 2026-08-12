extends ConfirmationDialog

const VtModel = preload("res://lib/model/vt_model.gd")

var item: VtModel

func _ready():
	var controller = item.get_expression_controller() if item.has_method("get_expression_controller") else null
	if controller == null or controller.expressions.is_empty():
		%Expressions.add_item("No Expressions Present")
		%Expressions.disabled = true
		get_ok_button().disabled = true
		return
	for e in controller.expressions:
		var idx = %Expressions.item_count
		%Expressions.add_item(e.get_name())
		%Expressions.set_item_metadata(idx, e)
	
func _on_confirmed() -> void:
	var selected = %Expressions.get_selected_metadata()
	if selected == null:
		close_requested.emit()
		return
	item.toggle_expression(selected.get_name(), true, %Duration.value, true)
	close_requested.emit()

func _on_canceled() -> void:
	close_requested.emit()

func _on_close_requested() -> void:
	queue_free()
