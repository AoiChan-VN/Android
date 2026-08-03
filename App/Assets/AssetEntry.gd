class_name AssetEntry
extends RefCounted

var asset_id: StringName = &""
var asset_path: String = ""
var category: StringName = &""
var type_hint: String = ""
var asset_type: String = ""
var resource: Resource = null


func configure(
	id: StringName,
	path: String,
	asset_category: StringName = &"",
	hint: String = ""
) -> bool:
	if id.is_empty():
		return false

	if path.is_empty():
		return false

	asset_id = id
	asset_path = path
	category = asset_category
	type_hint = hint
	asset_type = ""
	resource = null

	return true


func set_resource(
	value: Resource
) -> bool:
	if value == null:
		return false

	resource = value
	asset_type = value.get_class()

	return true


func clear_resource() -> void:
	resource = null


func get_id() -> StringName:
	return asset_id


func get_path() -> String:
	return asset_path


func get_category() -> StringName:
	return category


func get_type_hint() -> String:
	return type_hint


func get_asset_type() -> String:
	return asset_type


func get_resource() -> Resource:
	return resource


func is_loaded() -> bool:
	return resource != null


func is_valid() -> bool:
	return (
		not asset_id.is_empty()
		and not asset_path.is_empty()
	)


func to_dictionary() -> Dictionary:
	return {
		"asset_id": String(asset_id),
		"asset_path": asset_path,
		"category": String(category),
		"type_hint": type_hint,
		"asset_type": asset_type,
		"loaded": is_loaded()
	} 
