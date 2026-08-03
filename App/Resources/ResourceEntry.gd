class_name ResourceEntry
extends RefCounted

var resource_id: StringName = &""
var resource_path: String = ""
var type_hint: String = ""
var resource_type: String = ""
var resource: Resource = null


func configure(
	id: StringName,
	path: String,
	hint: String = ""
) -> bool:
	if id.is_empty():
		return false

	if path.is_empty():
		return false

	resource_id = id
	resource_path = path
	type_hint = hint
	resource_type = ""
	resource = null

	return true


func set_resource(
	value: Resource
) -> bool:
	if value == null:
		return false

	resource = value
	resource_type = value.get_class()

	return true


func clear_resource() -> void:
	resource = null


func get_id() -> StringName:
	return resource_id


func get_path() -> String:
	return resource_path


func get_type_hint() -> String:
	return type_hint


func get_resource_type() -> String:
	return resource_type


func get_resource() -> Resource:
	return resource


func is_loaded() -> bool:
	return resource != null


func is_valid() -> bool:
	return (
		not resource_id.is_empty()
		and not resource_path.is_empty()
	)


func to_dictionary() -> Dictionary:
	return {
		"resource_id": String(resource_id),
		"resource_path": resource_path,
		"type_hint": type_hint,
		"resource_type": resource_type,
		"loaded": is_loaded()
  } 
