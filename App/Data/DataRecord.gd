class_name DataRecord
extends Resource

signal changed(
	record_id: StringName,
	version: int
)

signal metadata_changed(
	record_id: StringName,
	version: int
)

@export_group("Record")
@export var record_id: StringName = &""
@export var record_type: StringName = &""
@export var schema_version: int = 1
@export var version: int = 0

@export_group("Data")
@export var data: Dictionary = {}

@export_group("Metadata")
@export var metadata: Dictionary = {}


func configure(
	id: StringName,
	type_id: StringName,
	initial_data: Dictionary = {},
	initial_metadata: Dictionary = {},
	initial_schema_version: int = 1
) -> bool:
	if String(id).is_empty():
		return false

	if String(type_id).is_empty():
		return false

	if initial_schema_version < 1:
		return false

	record_id = id
	record_type = type_id
	schema_version = initial_schema_version
	version = 0

	data = initial_data.duplicate(true)
	metadata = initial_metadata.duplicate(true)

	return true


func set_value(
	key: StringName,
	value: Variant
) -> bool:
	if String(key).is_empty():
		return false

	data[key] = value
	version += 1

	changed.emit(
		record_id,
		version
	)

	return true


func get_value(
	key: StringName,
	default_value: Variant = null
) -> Variant:
	return data.get(
		key,
		default_value
	)


func has_value(
	key: StringName
) -> bool:
	return data.has(key)


func remove_value(
	key: StringName
) -> bool:
	if not data.has(key):
		return false

	data.erase(key)
	version += 1

	changed.emit(
		record_id,
		version
	)

	return true


func apply(
	patch: Dictionary,
	overwrite: bool = true
) -> bool:
	if patch.is_empty():
		return true

	var changed_state: bool = false

	for key in patch.keys():
		if overwrite or not data.has(key):
			data[key] = patch[key]
			changed_state = true

	if not changed_state:
		return true

	version += 1

	changed.emit(
		record_id,
		version
	)

	return true


func replace_data(
	new_data: Dictionary
) -> bool:
	data = new_data.duplicate(true)
	version += 1

	changed.emit(
		record_id,
		version
	)

	return true


func clear_data() -> void:
	if data.is_empty():
		return

	data.clear()
	version += 1

	changed.emit(
		record_id,
		version
	)


func set_metadata(
	key: StringName,
	value: Variant
) -> bool:
	if String(key).is_empty():
		return false

	metadata[key] = value
	version += 1

	metadata_changed.emit(
		record_id,
		version
	)

	return true


func get_metadata(
	key: StringName,
	default_value: Variant = null
) -> Variant:
	return metadata.get(
		key,
		default_value
	)


func has_metadata(
	key: StringName
) -> bool:
	return metadata.has(key)


func remove_metadata(
	key: StringName
) -> bool:
	if not metadata.has(key):
		return false

	metadata.erase(key)
	version += 1

	metadata_changed.emit(
		record_id,
		version
	)

	return true


func replace_metadata(
	new_metadata: Dictionary
) -> bool:
	metadata = new_metadata.duplicate(true)
	version += 1

	metadata_changed.emit(
		record_id,
		version
	)

	return true


func clear_metadata() -> void:
	if metadata.is_empty():
		return

	metadata.clear()
	version += 1

	metadata_changed.emit(
		record_id,
		version
	)


func set_schema_version(
	new_schema_version: int
) -> bool:
	if new_schema_version < 1:
		return false

	if schema_version == new_schema_version:
		return true

	schema_version = new_schema_version
	version += 1

	changed.emit(
		record_id,
		version
	)

	return true


func get_id() -> StringName:
	return record_id


func get_type_id() -> StringName:
	return record_type


func get_schema_version() -> int:
	return schema_version


func get_version() -> int:
	return version


func get_data() -> Dictionary:
	return data.duplicate(true)


func get_metadata_copy() -> Dictionary:
	return metadata.duplicate(true)


func is_valid() -> bool:
	return (
		not String(record_id).is_empty()
		and not String(record_type).is_empty()
		and schema_version > 0
	)


func to_dictionary() -> Dictionary:
	return {
		"record_id": String(record_id),
		"record_type": String(record_type),
		"schema_version": schema_version,
		"version": version,
		"data": data.duplicate(true),
		"metadata": metadata.duplicate(true)
	}


func load_dictionary(source: Dictionary) -> bool:
	var source_id: StringName = StringName(
		str(source.get("record_id", ""))
	)

	var source_type: StringName = StringName(
		str(source.get("record_type", ""))
	)

	var source_schema_version: int = int(
		source.get("schema_version", 1)
	)

	if not configure(
		source_id,
		source_type,
		source.get("data", {}),
		source.get("metadata", {}),
		source_schema_version
	):
		return false

	version = int(
		source.get("version", 0)
	)

	return true 
