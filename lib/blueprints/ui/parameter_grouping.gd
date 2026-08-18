extends RefCounted
class_name ParameterGrouping

## Longer prefixes are matched first (e.g. Brows before Brow).
const PREFIX_GROUPS := [
	{"prefix": "EyeBall", "group": "Eyes"},
	{"prefix": "Eye", "group": "Eyes"},
	{"prefix": "Brows", "group": "Brows"},
	{"prefix": "Brow", "group": "Brows"},
	{"prefix": "Mouth", "group": "Mouth"},
	{"prefix": "Lip", "group": "Mouth"},
	{"prefix": "Cheek", "group": "Cheeks"},
	{"prefix": "Tongue", "group": "Tongue"},
	{"prefix": "Head", "group": "Head"},
	{"prefix": "Body", "group": "Body"},
	{"prefix": "Arm", "group": "Arms"},
	{"prefix": "Hand", "group": "Hands"},
	{"prefix": "Leg", "group": "Legs"},
	{"prefix": "Foot", "group": "Feet"},
	{"prefix": "Hair", "group": "Hair"},
	{"prefix": "Angle", "group": "Angles"},
	{"prefix": "Face", "group": "Face"},
]

static func infer_group(param_name: String) -> String:
	var name := _strip_name_prefixes(param_name)
	for entry in PREFIX_GROUPS:
		var prefix: String = entry.prefix
		if name.begins_with(prefix):
			return entry.group
	var chunk := _leading_alpha_chunk(name)
	if not chunk.is_empty():
		return chunk
	return "Other"

static func group_parameters(param_names: Array) -> Dictionary:
	var groups: Dictionary = {}
	for param in param_names:
		var group := infer_group(String(param))
		var list: Array = groups.get(group, [])
		list.append(param)
		groups[group] = list
	for group in groups:
		groups[group].sort()
	return groups

static func sorted_group_names(groups: Dictionary) -> Array:
	var names: Array = groups.keys()
	names.sort_custom(
		func (a, b):
			if a == "Other":
				return false
			if b == "Other":
				return true
			return a < b
	)
	return names

## Live2D Cubism parameters use a Param prefix; strip it before grouping.
static func _strip_name_prefixes(param_name: String) -> String:
	var name := param_name
	if name.begins_with("Param"):
		name = name.substr(5)
	return name

static func _leading_alpha_chunk(param_name: String) -> String:
	var chunk := ""
	for i in param_name.length():
		var c: String = param_name[i]
		if c >= "A" and c <= "Z":
			if not chunk.is_empty():
				break
			chunk += c
		elif c >= "a" and c <= "z":
			chunk += c
		else:
			if not chunk.is_empty():
				break
	return chunk.capitalize()
