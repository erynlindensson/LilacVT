@abstract extends GraphNode

const VtModel = preload("res://lib/model/vt_model.gd")

enum SlotType {
	TRIGGER,
	NUMERIC,
	STRING,
	BOOL,
	VECTOR
}

const SLOT_COLORS := {
	SlotType.TRIGGER: Color(0.95, 0.55, 0.15, 1.0),
	SlotType.NUMERIC: Color(0.35, 0.78, 0.42, 1.0),
	SlotType.STRING: Color(0.62, 0.45, 0.92, 1.0),
	SlotType.BOOL: Color(0.92, 0.82, 0.25, 1.0),
	SlotType.VECTOR: Color(0.35, 0.62, 0.95, 1.0),
}

signal action_updated(slot: int)

## reference to the bound model is directly available to all VtActions
var model: VtModel:
	set = set_model

func set_model(m: VtModel):
	model = m

## quick name access to the graph this action belongs to
@onready var graph: GraphEdit = get_parent()

# port mappings
# Slot index != Port Index, slots are the children while ports are enabled children
var _slot_to_input: Dictionary[StringName, int] = {}
var _slot_to_output: Dictionary[StringName, int] = {}

static func color_for_type(slot_type: int) -> Color:
	return SLOT_COLORS.get(slot_type, Color.WHITE)

func apply_slot_color(slot_index: int, side: StringName = &"both") -> void:
	if side == &"both" or side == &"left":
		if is_slot_enabled_left(slot_index):
			set_slot_color_left(slot_index, color_for_type(get_slot_type_left(slot_index)))
	if side == &"both" or side == &"right":
		if is_slot_enabled_right(slot_index):
			set_slot_color_right(slot_index, color_for_type(get_slot_type_right(slot_index)))

func apply_all_slot_colors() -> void:
	for slot_index in get_child_count():
		apply_slot_color(slot_index)

func ensure_slot_colors() -> void:
	apply_all_slot_colors()

func _ready() -> void:
	ensure_slot_colors()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		ensure_slot_colors()

@abstract func get_type() -> StringName

func update_value(slot: int, value: Variant) -> void:
	pass

func get_value(slot: int) -> Variant:
	return null
	
func invoke_trigger(slot: int):
	pass

@abstract func deserialize(data: Dictionary) -> void

@abstract func serialize() -> Dictionary

func bind(slot: int, node: GraphNode) -> void:
	pass

func unbind(slot: int, node: GraphNode) -> void:
	pass
	
func reset_value(slot: int) -> void:
	pass

func get_slot_by_name(slot: StringName) -> int:
	return get_children().find_custom(
		func (f):
			return f.name.to_lower() == slot.to_lower()
	)

@abstract func get_input_port_by_name(slot: StringName) -> int

@abstract func get_output_port_by_name(slot: StringName) -> int

# replaces godot's built in functions because since 4.5 the internal
# port cache has been broken, only populating when the graph is first visible
# because our graphs exist off-screen, we need to provide a method
# of connecting ports even without the internal cache lookup
@abstract func get_input_slot_by_port(port: int) -> int

@abstract func get_output_slot_by_port(port: int) -> int
	
func get_slot_name(slot: int) -> StringName:
	return get_child(slot).name

func get_output_type(slot: int) -> int:
	return self.get_slot_type_right(slot)
	
func get_input_type(slot: int) -> int:
	return self.get_slot_type_left(slot)
