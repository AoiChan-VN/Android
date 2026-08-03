class_name Resources
extends Node

signal resources_started
signal resources_ready
signal resources_paused
signal resources_resumed
signal resources_stopping
signal resources_stopped
signal resources_failed(reason: String)

signal resource_registered(
	resource_id: StringName,
	resource_path: String
)

signal resource_unregistered(
	resource_id: StringName,
	resource_path: String
)

signal resource_loaded(
	resource_id: StringName,
	resource_path: String
)

signal resource_unloaded(
	resource_id: StringName,
	resource_path: String
)

signal resource_saved(
	resource_id: StringName,
	resource_path: String
)

signal resource_changed(
	resource_id: StringName,
	resource_path: String
)

signal resource_load_failed(
	resource_id: StringName,
	resource_path: String,
	reason: String
)

enum State {
	IDLE,
	STARTING,
	READY,
	PAUSED,
	STOPPING,
	STOPPED,
	FAILED
}

const EXPECTED_NODE_NAME: StringName = &"Resources"

@export_group("Resources")
@export var auto_start: bool = true
@export var validate_paths: bool = true
@export var keep_loaded: bool = true
@export var scan_on_start: bool = false
@export var console_output: bool = true
@export var clear_on_stop: bool = false

@export_group("Validation")
@export var validate_root: bool = true

var state: State = State.IDLE
var resources_error: String = ""

var _entries: Dictionary = {}
var _resource_order: Array[StringName] = []


func _enter_tree() -> void:
	state = State.STARTING


func _ready() -> void:
	if auto_start:
		start()


func _exit_tree() -> void:
	_shutdown()


func start() -> bool:
	if state == State.READY:
		return true

	if state == State.PAUSED:
		return resume()

	if state == State.STOPPING:
		return false

	if state == State.FAILED or state == State.STOPPED:
		state = State.IDLE
		resources_error = ""

	if validate_root and not _validate_root():
		return _fail(resources_error)

	state = State.STARTING

	resources_started.emit()

	if scan_on_start:
		if not scan_registered_paths():
			return _fail(resources_error)

	state = State.READY

	resources_ready.emit()

	_log("Resources Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	state = State.PAUSED

	resources_paused.emit()

	_log("Resources Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	state = State.READY

	resources_resumed.emit()

	_log("Resources Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func register_resource(
	resource_id: StringName,
	resource_path: String,
	type_hint: String = "",
	replace_existing: bool = false
) -> bool:
	if not _is_operational():
		return false

	if resource_id.is_empty():
		_set_error(
			"Resource ID không được để trống"
		)
		return false

	if resource_path.is_empty():
		_set_error(
			"Resource Path không được để trống"
		)
		return false

	if validate_paths and not ResourceLoader.exists(
		resource_path,
		type_hint
	):
		_set_error(
			"Resource Path không tồn tại: "
			+ resource_path
		)
		return false

	if _entries.has(resource_id):
		if not replace_existing:
			_set_error(
				"Resource ID đã tồn tại: "
				+ String(resource_id)
			)
			return false

		unregister_resource(resource_id)

	var entry := ResourceEntry.new()

	if not entry.configure(
		resource_id,
		resource_path,
		type_hint
	):
		_set_error(
			"Không thể tạo Resource Entry"
		)
		return false

	_entries[resource_id] = entry
	_resource_order.append(resource_id)

	resource_registered.emit(
		resource_id,
		resource_path
	)

	_log(
		"Resource Registered: "
		+ String(resource_id)
	)

	return true


func unregister_resource(
	resource_id: StringName
) -> bool:
	if not _entries.has(resource_id):
		return false

	var entry: ResourceEntry = _entries[resource_id]

	if entry != null:
		var resource_path: String = entry.get_path()

		entry.clear_resource()

		_entries.erase(resource_id)
		_resource_order.erase(resource_id)

		resource_unregistered.emit(
			resource_id,
			resource_path
		)

		_log(
			"Resource Unregistered: "
			+ String(resource_id)
		)

		return true

	_entries.erase(resource_id)
	_resource_order.erase(resource_id)

	return false


func register_loaded_resource(
	resource_id: StringName,
	resource: Resource,
	resource_path: String = "",
	replace_existing: bool = false
) -> bool:
	if not _is_operational():
		return false

	if resource_id.is_empty():
		_set_error(
			"Resource ID không được để trống"
		)
		return false

	if resource == null:
		_set_error(
			"Resource không hợp lệ"
		)
		return false

	var path: String = resource_path

	if path.is_empty():
		path = resource.resource_path

	if path.is_empty():
		_set_error(
			"Resource Path không được để trống"
		)
		return false

	if _entries.has(resource_id):
		if not replace_existing:
			_set_error(
				"Resource ID đã tồn tại: "
				+ String(resource_id)
			)
			return false

		unregister_resource(resource_id)

	var entry := ResourceEntry.new()

	if not entry.configure(
		resource_id,
		path
	):
		_set_error(
			"Không thể tạo Resource Entry"
		)
		return false

	if not entry.set_resource(resource):
		_set_error(
			"Không thể gán Resource vào Entry"
		)
		return false

	_entries[resource_id] = entry
	_resource_order.append(resource_id)

	resource_registered.emit(
		resource_id,
		path
	)

	resource_loaded.emit(
		resource_id,
		path
	)

	_log(
		"Loaded Resource Registered: "
		+ String(resource_id)
	)

	return true


func get_entry(
	resource_id: StringName
) -> ResourceEntry:
	if not _entries.has(resource_id):
		return null

	var entry: ResourceEntry = _entries[resource_id]

	if entry == null:
		_entries.erase(resource_id)
		_resource_order.erase(resource_id)
		return null

	return entry


func get_resource(
	resource_id: StringName
) -> Resource:
	var entry: ResourceEntry = get_entry(
		resource_id
	)

	if entry == null:
		return null

	if entry.is_loaded():
		return entry.get_resource()

	return load_resource(
		resource_id
	)


func load_resource(
	resource_id: StringName,
	cache_mode: ResourceLoader.CacheMode = ResourceLoader.CACHE_MODE_REUSE
) -> Resource:
	if not _is_operational():
		return null

	var entry: ResourceEntry = get_entry(
		resource_id
	)

	if entry == null:
		_set_error(
			"Không tìm thấy Resource ID: "
			+ String(resource_id)
		)

		resource_load_failed.emit(
			resource_id,
			"",
			resources_error
		)

		return null

	if entry.is_loaded() and keep_loaded:
		return entry.get_resource()

	var resource_path: String = entry.get_path()
	var type_hint: String = entry.get_type_hint()

	var resource: Resource = ResourceLoader.load(
		resource_path,
		type_hint,
		cache_mode
	)

	if resource == null:
		_set_error(
			"Không thể Load Resource: "
			+ resource_path
		)

		resource_load_failed.emit(
			resource_id,
			resource_path,
			resources_error
		)

		return null

	entry.set_resource(resource)

	resource_loaded.emit(
		resource_id,
		resource_path
	)

	_log(
		"Resource Loaded: "
		+ String(resource_id)
	)

	return resource


func unload_resource(
	resource_id: StringName
) -> bool:
	var entry: ResourceEntry = get_entry(
		resource_id
	)

	if entry == null:
		return false

	if not entry.is_loaded():
		return true

	var resource_path: String = entry.get_path()

	entry.clear_resource()

	resource_unloaded.emit(
		resource_id,
		resource_path
	)

	_log(
		"Resource Unloaded: "
		+ String(resource_id)
	)

	return true


func reload_resource(
	resource_id: StringName
) -> Resource:
	if not _is_operational():
		return null

	var entry: ResourceEntry = get_entry(
		resource_id
	)

	if entry == null:
		return null

	entry.clear_resource()

	return load_resource(
		resource_id,
		ResourceLoader.CACHE_MODE_REPLACE
	)


func save_resource(
	resource_id: StringName,
	resource: Resource = null,
	flags: ResourceSaver.SaverFlags = 0
) -> bool:
	if not _is_operational():
		return false

	var entry: ResourceEntry = get_entry(
		resource_id
	)

	if entry == null:
		_set_error(
			"Không tìm thấy Resource ID: "
			+ String(resource_id)
		)
		return false

	var target_resource: Resource = resource

	if target_resource == null:
		target_resource = entry.get_resource()

	if target_resource == null:
		target_resource = load_resource(
			resource_id
		)

	if target_resource == null:
		return false

	var resource_path: String = entry.get_path()

	var result: Error = ResourceSaver.save(
		target_resource,
		resource_path,
		flags
	)

	if result != OK:
		_set_error(
			"Không thể Save Resource: "
			+ resource_path
			+ " - "
			+ error_string(result)
		)
		return false

	if not entry.is_loaded():
		entry.set_resource(
			target_resource
		)

	resource_saved.emit(
		resource_id,
		resource_path
	)

	_log(
		"Resource Saved: "
		+ String(resource_id)
	)

	return true


func set_resource(
	resource_id: StringName,
	resource: Resource,
	save_immediately: bool = false
) -> bool:
	if not _is_operational():
		return false

	var entry: ResourceEntry = get_entry(
		resource_id
	)

	if entry == null:
		return false

	if resource == null:
		_set_error(
			"Resource không hợp lệ"
		)
		return false

	if not entry.set_resource(resource):
		return false

	resource_changed.emit(
		resource_id,
		entry.get_path()
	)

	if save_immediately:
		return save_resource(
			resource_id,
			resource
		)

	return true


func has_resource(
	resource_id: StringName
) -> bool:
	return get_entry(
		resource_id
	) != null


func is_resource_loaded(
	resource_id: StringName
) -> bool:
	var entry: ResourceEntry = get_entry(
		resource_id
	)

	if entry == null:
		return false

	return entry.is_loaded()


func get_resource_path(
	resource_id: StringName
) -> String:
	var entry: ResourceEntry = get_entry(
		resource_id
	)

	if entry == null:
		return ""

	return entry.get_path()


func get_resource_type(
	resource_id: StringName
) -> String:
	var entry: ResourceEntry = get_entry(
		resource_id
	)

	if entry == null:
		return ""

	if entry.is_loaded():
		return entry.get_resource_type()

	return entry.get_type_hint()


func get_resource_count() -> int:
	return _entries.size()


func get_resource_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for resource_id in _resource_order:
		if _entries.has(resource_id):
			result.append(
				resource_id
			)

	return result


func get_loaded_resource_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for resource_id in _resource_order:
		var entry: ResourceEntry = get_entry(
			resource_id
		)

		if entry != null and entry.is_loaded():
			result.append(
				resource_id
			)

	return result


func get_unloaded_resource_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for resource_id in _resource_order:
		var entry: ResourceEntry = get_entry(
			resource_id
		)

		if entry != null and not entry.is_loaded():
			result.append(
				resource_id
			)

	return result


func get_resources_by_type(
	type_name: String
) -> Array[Resource]:
	var result: Array[Resource] = []

	if type_name.is_empty():
		return result

	for resource_id in _resource_order:
		var resource: Resource = get_resource(
			resource_id
		)

		if resource == null:
			continue

		if resource.get_class() == type_name:
			result.append(
				resource
			)

	return result


func scan_registered_paths() -> bool:
	resources_error = ""

	for resource_id in _resource_order:
		var entry: ResourceEntry = get_entry(
			resource_id
		)

		if entry == null:
			continue

		var resource_path: String = entry.get_path()

		if not ResourceLoader.exists(
			resource_path,
			entry.get_type_hint()
		):
			resources_error = (
				"Resource Path không tồn tại: "
				+ resource_path
			)

			return false

	return true


func clear_loaded() -> void:
	for resource_id in _resource_order:
		var entry: ResourceEntry = get_entry(
			resource_id
		)

		if entry != null:
			entry.clear_resource()


func clear_resources() -> void:
	for resource_id in _resource_order:
		var entry: ResourceEntry = get_entry(
			resource_id
		)

		if entry != null:
			entry.clear_resource()

	_entries.clear()
	_resource_order.clear()


func create_snapshot() -> Dictionary:
	var snapshot: Dictionary = {
		"resources": []
	}

	var records: Array = []

	for resource_id in _resource_order:
		var entry: ResourceEntry = get_entry(
			resource_id
		)

		if entry == null:
			continue

		records.append(
			entry.to_dictionary()
		)

	snapshot["resources"] = records

	return snapshot


func is_ready() -> bool:
	return state == State.READY


func is_paused() -> bool:
	return state == State.PAUSED


func is_stopped() -> bool:
	return state == State.STOPPED


func is_failed() -> bool:
	return state == State.FAILED


func get_state() -> State:
	return state


func get_error() -> String:
	return resources_error


func _validate_root() -> bool:
	resources_error = ""

	if not is_inside_tree():
		resources_error = (
			"Resources không nằm trong SceneTree"
		)
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Resources: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
			% [
				EXPECTED_NODE_NAME,
				name
			]
		)

	return true


func _is_operational() -> bool:
	return (
		state == State.READY
		or state == State.PAUSED
	)


func _set_error(
	message: String
) -> void:
	resources_error = message

	_log_error(
		message
	)


func _fail(
	reason: String
) -> bool:
	state = State.FAILED
	resources_error = reason

	resources_failed.emit(
		reason
	)

	_log_error(
		reason
	)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING

	resources_stopping.emit()

	if clear_on_stop:
		clear_resources()
	elif not keep_loaded:
		clear_loaded()

	state = State.STOPPED

	resources_stopped.emit()

	_log(
		"Resources Stopped"
	)


func _log(
	message: String
) -> void:
	if console_output:
		print(
			"[Resources] ",
			message
		)


func _log_error(
	message: String
) -> void:
	push_error(
		"[Resources] "
		+ message
) 
