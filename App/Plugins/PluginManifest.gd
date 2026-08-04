class_name PluginManifest
extends Resource

@export_group("Identity")
@export var plugin_id: StringName = &""
@export var display_name: String = ""
@export var version: String = "1.0.0"
@export var api_version: String = "1.0.0"
@export var main_scene: String = ""

@export_group("Contract")
@export var dependencies: Array[StringName] = []
@export var capabilities: Array[StringName] = []
@export var permissions: Array[StringName] = []
@export var enabled_by_default: bool = true

@export_group("Metadata")
@export var metadata: Dictionary = {}

var validation_error: String = ""


func validate() -> bool:
	validation_error = ""

	if plugin_id.is_empty():
		validation_error = "Plugin ID không được để trống"
		return false

	if display_name.is_empty():
		display_name = String(plugin_id)

	if not _validate_version(version):
		validation_error = (
			"Plugin Version không hợp lệ: "
			+ version
		)
		return false

	if not _validate_version(api_version):
		validation_error = (
			"Plugin API Version không hợp lệ: "
			+ api_version
		)
		return false

	if not main_scene.is_empty():
		if not main_scene.begins_with("res://"):
			validation_error = (
				"Plugin Main Scene phải sử dụng res://"
			)
			return false

		if not main_scene.ends_with(".tscn"):
			validation_error = (
				"Plugin Main Scene phải là TSCN"
			)
			return false

	if not _validate_ids(
		dependencies,
		"Dependency"
	):
		return false

	if dependencies.has(plugin_id):
		validation_error = (
			"Plugin không thể phụ thuộc chính nó"
		)
		return false

	if not _validate_ids(
		capabilities,
		"Capability"
	):
		return false

	if not _validate_ids(
		permissions,
		"Permission"
	):
		return false

	return true


func get_id() -> StringName:
	return plugin_id


func get_display_name() -> String:
	return display_name


func get_version() -> String:
	return version


func get_api_version() -> String:
	return api_version


func get_main_scene() -> String:
	return main_scene


func get_dependencies() -> Array[StringName]:
	var result: Array[StringName] = []

	result.assign(dependencies)

	return result


func get_capabilities() -> Array[StringName]:
	var result: Array[StringName] = []

	result.assign(capabilities)

	return result


func get_permissions() -> Array[StringName]:
	var result: Array[StringName] = []

	result.assign(permissions)

	return result


func get_metadata() -> Dictionary:
	return metadata.duplicate(true)


func get_error() -> String:
	return validation_error


func has_dependency(
	dependency_id: StringName
) -> bool:
	return dependencies.has(
		dependency_id
	)


func has_capability(
	capability_id: StringName
) -> bool:
	return capabilities.has(
		capability_id
	)


func requires_permission(
	permission_id: StringName
) -> bool:
	return permissions.has(
		permission_id
	)


func duplicate_manifest() -> PluginManifest:
	var result: PluginManifest = duplicate(
		true
	) as PluginManifest

	return result


func to_dictionary() -> Dictionary:
	return {
		"plugin_id": String(plugin_id),
		"display_name": display_name,
		"version": version,
		"api_version": api_version,
		"main_scene": main_scene,
		"dependencies": _ids_to_strings(
			dependencies
		),
		"capabilities": _ids_to_strings(
			capabilities
		),
		"permissions": _ids_to_strings(
			permissions
		),
		"enabled_by_default": enabled_by_default,
		"metadata": metadata.duplicate(true)
	}


func _validate_ids(
	ids: Array[StringName],
	label: String
) -> bool:
	var found: Dictionary = {}

	for id in ids:
		if id.is_empty():
			validation_error = (
				label
				+ " ID không được để trống"
			)
			return false

		if found.has(id):
			validation_error = (
				label
				+ " ID bị trùng: "
				+ String(id)
			)
			return false

		found[id] = true

	return true


func _validate_version(
	value: String
) -> bool:
	if value.is_empty():
		return false

	var parts: PackedStringArray = value.split(
		".",
		false
	)

	if parts.is_empty():
		return false

	for part in parts:
		if not part.is_valid_int():
			return false

		if part.to_int() < 0:
			return false

	return true


func _ids_to_strings(
	ids: Array[StringName]
) -> PackedStringArray:
	var result: PackedStringArray = []

	for id in ids:
		result.append(
			String(id)
		)

	return result 
