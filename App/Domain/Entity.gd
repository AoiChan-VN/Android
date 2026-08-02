class_name DomainEntity
extends RefCounted

signal changed(entity_id: StringName, version: int)
signal event_added(entity_id: StringName, event: Dictionary)
signal active_changed(entity_id: StringName, active: bool)

var entity_id: StringName = &""
var entity_type: StringName = &""
var version: int = 0

var _state: Dictionary = {}
var _events: Array[Dictionary] = []
var _active: bool = false


func configure(
	id: StringName,
	type_id: StringName,
	initial_state: Dictionary = {}
) -> bool:
	if String(id).is_empty():
		return false

	if String(type_id).is_empty():
		return false

	entity_id = id
	entity_type = type_id
	version = 0
	_state = initial_state.duplicate(true)
	_events.clear()
	_active = false

	return true


func activate() -> bool:
	if String(entity_id).is_empty():
		return false

	if _active:
		return true

	_active = true
	active_changed.emit(entity_id, true)

	return true


func deactivate() -> bool:
	if not _active:
		return true

	_active = false
	active_changed.emit(entity_id, false)

	return true


func set_value(
	key: StringName,
	value: Variant
) -> bool:
	if String(key).is_empty():
		return false

	_state[key] = value
	_touch()

	return true


func get_value(
	key: StringName,
	default_value: Variant = null
) -> Variant:
	return _state.get(key, default_value)


func has_value(key: StringName) -> bool:
	return _state.has(key)


func remove_value(key: StringName) -> bool:
	if not _state.has(key):
		return false

	_state.erase(key)
	_touch()

	return true


func apply(
	patch: Dictionary,
	overwrite: bool = true
) -> bool:
	if patch.is_empty():
		return true

	var changed_state: bool = false

	for key in patch.keys():
		if overwrite or not _state.has(key):
			_state[key] = patch[key]
			changed_state = true

	if changed_state:
		_touch()

	return true


func replace_state(new_state: Dictionary) -> bool:
	_state = new_state.duplicate(true)
	_touch()

	return true


func clear_state() -> void:
	if _state.is_empty():
		return

	_state.clear()
	_touch()


func add_event(
	event_type: StringName,
	payload: Dictionary = {}
) -> bool:
	if String(event_type).is_empty():
		return false

	var event: Dictionary = {
		"entity_id": entity_id,
		"entity_type": entity_type,
		"event_type": event_type,
		"version": version,
		"time": Time.get_ticks_msec(),
		"payload": payload.duplicate(true)
	}

	_events.append(event)

	event_added.emit(
		entity_id,
		event.duplicate(true)
	)

	return true


func pop_event() -> Dictionary:
	if _events.is_empty():
		return {}

	var event: Dictionary = _events.pop_front()

	return event.duplicate(true)


func drain_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for event in _events:
		result.append(event.duplicate(true))

	_events.clear()

	return result


func clear_events() -> void:
	_events.clear()


func get_id() -> StringName:
	return entity_id


func get_type_id() -> StringName:
	return entity_type


func get_version() -> int:
	return version


func get_state() -> Dictionary:
	return _state.duplicate(true)


func get_event_count() -> int:
	return _events.size()


func is_active() -> bool:
	return _active


func is_valid() -> bool:
	return (
		not String(entity_id).is_empty()
		and not String(entity_type).is_empty()
	)


func _touch() -> void:
	version += 1
	changed.emit(entity_id, version) 
