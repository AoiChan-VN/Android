class_name SharedValue
extends RefCounted

signal changed(
	shared_id: StringName,
	version: int
)

signal active_changed(
	shared_id: StringName,
	active: bool
)

var shared_id: StringName = &""
var namespace_id: StringName = &""
var value: Variant = null
var version: int = 0

var _active: bool = false


func configure(
	id: StringName,
	namespace_name: StringName,
	initial_value: Variant = null
) -> bool:
	if id.is_empty():
		return false

	if namespace_name.is_empty():
		return false

	shared_id = id
	namespace_id = namespace_name
	value = initial_value
	version = 0
	_active = false

	return true


func activate() -> bool:
	if shared_id.is_empty():
		return false

	if _active:
		return true

	_active = true

	active_changed.emit(
		shared_id,
		true
	)

	return true


func deactivate() -> bool:
	if not _active:
		return true

	_active = false

	active_changed.emit(
		shared_id,
		false
	)

	return true


func set_value(
	new_value: Variant
) -> bool:
	if not _active:
		return false

	value = new_value
	version += 1

	changed.emit(
		shared_id,
		version
	)

	return true


func force_set_value(
	new_value: Variant
) -> bool:
	value = new_value
	version += 1

	changed.emit(
		shared_id,
		version
	)

	return true


func get_value() -> Variant:
	return value


func get_id() -> StringName:
	return shared_id


func get_namespace() -> StringName:
	return namespace_id


func get_version() -> int:
	return version


func is_active() -> bool:
	return _active


func is_valid() -> bool:
	return (
		not shared_id.is_empty()
		and not namespace_id.is_empty()
) 
