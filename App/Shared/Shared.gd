class_name Shared
extends Node

signal shared_started
signal shared_ready
signal shared_paused
signal shared_resumed
signal shared_stopping
signal shared_stopped
signal shared_failed(
	reason: String
)

signal value_registered(
	shared_id: StringName,
	namespace_id: StringName
)

signal value_unregistered(
	shared_id: StringName,
	namespace_id: StringName
)

signal value_changed(
	shared_id: StringName,
	version: int
)

signal value_active_changed(
	shared_id: StringName,
	active: bool
)

signal namespace_registered(
	namespace_id: StringName
)

signal namespace_removed(
	namespace_id: StringName
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

const EXPECTED_NODE_NAME: StringName = &"Shared"

@export_group("Shared")
@export var auto_start: bool = true
@export var allow_replace: bool = false
@export var clear_on_stop: bool = false
@export var console_output: bool = true

@export_group("Validation")
@export var validate_root: bool = true

var state: State = State.IDLE
var shared_error: String = ""

var _values: Dictionary = {}
var _value_order: Array[StringName] = []
var _namespaces: Dictionary = {}


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
		shared_error = ""

	if validate_root and not _validate_root():
		return _fail(shared_error)

	state = State.STARTING

	shared_started.emit()

	_activate_all()

	state = State.READY

	shared_ready.emit()

	_log("Shared Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	state = State.PAUSED

	shared_paused.emit()

	_log("Shared Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	state = State.READY

	shared_resumed.emit()

	_log("Shared Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func register_value(
	shared_id: StringName,
	namespace_id: StringName,
	initial_value: Variant = null,
	replace_existing: bool = false
) -> bool:
	if not _is_operational():
		return false

	if shared_id.is_empty():
		_set_error(
			"Shared ID không được để trống"
		)
		return false

	if namespace_id.is_empty():
		_set_error(
			"Namespace ID không được để trống"
		)
		return false

	if _values.has(shared_id):
		if not replace_existing and not allow_replace:
			_set_error(
				"Shared ID đã tồn tại: "
				+ String(shared_id)
			)
			return false

		unregister_value(shared_id)

	var shared_value := SharedValue.new()

	if not shared_value.configure(
		shared_id,
		namespace_id,
		initial_value
	):
		_set_error(
			"Không thể tạo SharedValue"
		)
		return false

	_values[shared_id] = shared_value
	_value_order.append(shared_id)

	_add_namespace(
		namespace_id,
		shared_id
	)

	_connect_value(
		shared_value
	)

	shared_value.activate()

	value_registered.emit(
		shared_id,
		namespace_id
	)

	_log(
		"Shared Value Registered: "
		+ String(shared_id)
	)

	return true


func unregister_value(
	shared_id: StringName
) -> bool:
	var shared_value: SharedValue = get_value_entry(
		shared_id
	)

	if shared_value == null:
		return false

	var namespace_id: StringName = (
		shared_value.get_namespace()
	)

	shared_value.deactivate()

	_disconnect_value(
		shared_value
	)

	_values.erase(
		shared_id
	)

	_value_order.erase(
		shared_id
	)

	_remove_namespace(
		namespace_id,
		shared_id
	)

	value_unregistered.emit(
		shared_id,
		namespace_id
	)

	_log(
		"Shared Value Unregistered: "
		+ String(shared_id)
	)

	return true


func replace_value(
	shared_id: StringName,
	namespace_id: StringName,
	new_value: Variant
) -> bool:
	if _values.has(shared_id):
		if not unregister_value(shared_id):
			return false

	return register_value(
		shared_id,
		namespace_id,
		new_value,
		true
	)


func get_value_entry(
	shared_id: StringName
) -> SharedValue:
	if not _values.has(shared_id):
		return null

	var shared_value: SharedValue = (
		_values[shared_id]
	)

	if shared_value == null:
		_values.erase(shared_id)
		_value_order.erase(shared_id)
		return null

	return shared_value


func get_shared_value(
	shared_id: StringName
) -> Variant:
	var shared_value: SharedValue = (
		get_value_entry(shared_id)
	)

	if shared_value == null:
		return null

	return shared_value.get_value()


func set_shared_value(
	shared_id: StringName,
	new_value: Variant
) -> bool:
	if state != State.READY:
		return false

	var shared_value: SharedValue = (
		get_value_entry(shared_id)
	)

	if shared_value == null:
		return false

	return shared_value.set_value(
		new_value
	)


func force_set_shared_value(
	shared_id: StringName,
	new_value: Variant
) -> bool:
	if not _is_operational():
		return false

	var shared_value: SharedValue = (
		get_value_entry(shared_id)
	)

	if shared_value == null:
		return false

	return shared_value.force_set_value(
		new_value
	)


func has_value(
	shared_id: StringName
) -> bool:
	return get_value_entry(
		shared_id
	) != null


func is_value_active(
	shared_id: StringName
) -> bool:
	var shared_value: SharedValue = (
		get_value_entry(shared_id)
	)

	if shared_value == null:
		return false

	return shared_value.is_active()


func get_value_version(
	shared_id: StringName
) -> int:
	var shared_value: SharedValue = (
		get_value_entry(shared_id)
	)

	if shared_value == null:
		return -1

	return shared_value.get_version()


func get_value_namespace(
	shared_id: StringName
) -> StringName:
	var shared_value: SharedValue = (
		get_value_entry(shared_id)
	)

	if shared_value == null:
		return &""

	return shared_value.get_namespace()


func get_value_count() -> int:
	return _values.size()


func get_value_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for shared_id in _value_order:
		if _values.has(shared_id):
			result.append(
				shared_id
			)

	return result


func register_namespace(
	namespace_id: StringName
) -> bool:
	if namespace_id.is_empty():
		return false

	if _namespaces.has(namespace_id):
		return false

	_namespaces[namespace_id] = []

	namespace_registered.emit(
		namespace_id
	)

	_log(
		"Namespace Registered: "
		+ String(namespace_id)
	)

	return true


func remove_namespace(
	namespace_id: StringName,
	remove_values: bool = false
) -> bool:
	if not _namespaces.has(namespace_id):
		return false

	if remove_values:
		var value_ids: Array[StringName] = (
			get_value_ids_by_namespace(
				namespace_id
			)
		)

		for shared_id in value_ids:
			unregister_value(
				shared_id
			)

	_namespaces.erase(
		namespace_id
	)

	namespace_removed.emit(
		namespace_id
	)

	_log(
		"Namespace Removed: "
		+ String(namespace_id)
	)

	return true


func has_namespace(
	namespace_id: StringName
) -> bool:
	return _namespaces.has(
		namespace_id
	)


func get_namespace_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for namespace_id in _namespaces.keys():
		result.append(
			StringName(
				str(namespace_id)
			)
		)

	return result


func get_namespace_count() -> int:
	return _namespaces.size()


func get_value_ids_by_namespace(
	namespace_id: StringName
) -> Array[StringName]:
	var result: Array[StringName] = []

	if not _namespaces.has(
		namespace_id
	):
		return result

	var value_ids: Array = (
		_namespaces[namespace_id]
	)

	for shared_id in value_ids:
		if has_value(
			shared_id
		):
			result.append(
				shared_id
			)

	return result


func get_values_by_namespace(
	namespace_id: StringName
) -> Dictionary:
	var result: Dictionary = {}

	for shared_id in get_value_ids_by_namespace(
		namespace_id
	):
		result[shared_id] = get_shared_value(
			shared_id
		)

	return result


func activate_value(
	shared_id: StringName
) -> bool:
	var shared_value: SharedValue = (
		get_value_entry(shared_id)
	)

	if shared_value == null:
		return false

	return shared_value.activate()


func deactivate_value(
	shared_id: StringName
) -> bool:
	var shared_value: SharedValue = (
		get_value_entry(shared_id)
	)

	if shared_value == null:
		return false

	return shared_value.deactivate()


func activate_all() -> bool:
	var success: bool = true

	for shared_id in get_value_ids():
		var shared_value: SharedValue = (
			get_value_entry(shared_id)
		)

		if shared_value == null:
			continue

		if not shared_value.activate():
			success = false

	return success


func deactivate_all() -> bool:
	var success: bool = true

	var shared_ids: Array[StringName] = (
		get_value_ids()
	)

	shared_ids.reverse()

	for shared_id in shared_ids:
		var shared_value: SharedValue = (
			get_value_entry(shared_id)
		)

		if shared_value == null:
			continue

		if not shared_value.deactivate():
			success = false

	return success


func clear_values() -> void:
	var shared_ids: Array[StringName] = (
		get_value_ids()
	)

	shared_ids.reverse()

	for shared_id in shared_ids:
		unregister_value(
			shared_id
		)


func clear_namespaces() -> void:
	_namespaces.clear()


func clear_shared() -> void:
	clear_values()
	clear_namespaces()


func create_snapshot() -> Dictionary:
	var snapshot: Dictionary = {
		"values": []
	}

	var records: Array = []

	for shared_id in _value_order:
		var shared_value: SharedValue = (
			get_value_entry(shared_id)
		)

		if shared_value == null:
			continue

		records.append(
			{
				"shared_id": String(
					shared_value.get_id()
				),
				"namespace_id": String(
					shared_value.get_namespace()
				),
				"value": shared_value.get_value(),
				"version": shared_value.get_version(),
				"active": shared_value.is_active()
			}
		)

	snapshot["values"] = records

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
	return shared_error


func _activate_all() -> void:
	activate_all()


func _connect_value(
	shared_value: SharedValue
) -> void:
	if not shared_value.changed.is_connected(
		_on_value_changed
	):
		shared_value.changed.connect(
			_on_value_changed
		)

	if not shared_value.active_changed.is_connected(
		_on_value_active_changed
	):
		shared_value.active_changed.connect(
			_on_value_active_changed
		)


func _disconnect_value(
	shared_value: SharedValue
) -> void:
	if not is_instance_valid(
		shared_value
	):
		return

	if shared_value.changed.is_connected(
		_on_value_changed
	):
		shared_value.changed.disconnect(
			_on_value_changed
		)

	if shared_value.active_changed.is_connected(
		_on_value_active_changed
	):
		shared_value.active_changed.disconnect(
			_on_value_active_changed
	)


func _on_value_changed(
	shared_id: StringName,
	version: int
) -> void:
	value_changed.emit(
		shared_id,
		version
	)


func _on_value_active_changed(
	shared_id: StringName,
	active: bool
) -> void:
	value_active_changed.emit(
		shared_id,
		active
	)


func _add_namespace(
	namespace_id: StringName,
	shared_id: StringName
) -> void:
	if not _namespaces.has(
		namespace_id
	):
		_namespaces[namespace_id] = []

		var namespace_created: StringName = (
			namespace_id
		)

		namespace_registered.emit(
			namespace_created
		)

	var value_ids: Array = (
		_namespaces[namespace_id]
	)

	if not value_ids.has(
		shared_id
	):
		value_ids.append(
			shared_id
	)


func _remove_namespace(
	namespace_id: StringName,
	shared_id: StringName
) -> void:
	if not _namespaces.has(
		namespace_id
	):
		return

	var value_ids: Array = (
		_namespaces[namespace_id]
	)

	value_ids.erase(
		shared_id
	)

	if value_ids.is_empty():
		_namespaces.erase(
			namespace_id
		)

		namespace_removed.emit(
			namespace_id
		)


func _validate_root() -> bool:
	shared_error = ""

	if not is_inside_tree():
		shared_error = (
			"Shared không nằm trong SceneTree"
		)
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Shared: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
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
	shared_error = message

	_log_error(
		message
	)


func _fail(
	reason: String
) -> bool:
	state = State.FAILED
	shared_error = reason

	shared_failed.emit(
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

	shared_stopping.emit()

	if clear_on_stop:
		clear_shared()
	else:
		deactivate_all()

	state = State.STOPPED

	shared_stopped.emit()

	_log(
		"Shared Stopped"
	)


func _log(
	message: String
) -> void:
	if console_output:
		print(
			"[Shared] ",
			message
		)


func _log_error(
	message: String
) -> void:
	push_error(
		"[Shared] "
		+ message
) 
