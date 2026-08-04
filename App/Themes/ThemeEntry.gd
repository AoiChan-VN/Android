class_name ThemeEntry
extends RefCounted

var theme_id: StringName = &""
var theme_path: String = ""
var category: StringName = &""
var theme_resource: Theme = null


func configure(
	id: StringName,
	path: String = "",
	theme_category: StringName = &""
) -> bool:
	if id.is_empty():
		return false

	theme_id = id
	theme_path = path
	category = theme_category
	theme_resource = null

	return true


func set_theme(
	value: Theme
) -> bool:
	if value == null:
		return false

	theme_resource = value

	if theme_path.is_empty():
		theme_path = value.resource_path

	return true


func clear_theme() -> void:
	theme_resource = null


func set_path(
	path: String
) -> bool:
	if path.is_empty():
		return false

	theme_path = path

	return true


func get_id() -> StringName:
	return theme_id


func get_path() -> String:
	return theme_path


func get_category() -> StringName:
	return category


func get_theme() -> Theme:
	return theme_resource


func is_loaded() -> bool:
	return theme_resource != null


func is_valid() -> bool:
	return (
		not theme_id.is_empty()
		and (
			not theme_path.is_empty()
			or theme_resource != null
		)
	)


func to_dictionary() -> Dictionary:
	return {
		"theme_id": String(theme_id),
		"theme_path": theme_path,
		"category": String(category),
		"loaded": is_loaded()
	} 
