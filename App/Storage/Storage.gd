class_name Storage
extends Node

signal storage_started
signal storage_ready
signal storage_paused
signal storage_resumed
signal storage_stopping
signal storage_stopped
signal storage_failed(reason: String)

signal adapter_registered(
	storage_id: StringName
)

signal adapter_unregistered(
	storage_id: StringName
)

signal adapter_started(
	storage_id: StringName
)

signal adapter_ready(
	storage_id: StringName
)

signal adapter_paused(
	storage_id: StringName
)

signal adapter_resumed(
	storage_id: StringName
)

signal adapter_stopping(
	storage_id: StringName
)

signal adapter_stopped(
	storage_id: StringName
)

signal adapter_failed(
	storage_id: StringName,
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

const EXPECTED_NODE_NAME: StringName = &"Storage"

@export_group("Storage")
@export var auto_start: bool = true
@export var scan_children: bool = true
@export var start_registered: bool = true
@export var stop_on_exit: bool = true
@export var strict_start: bool = false
@export var console_output: bool = true
@export var free_on_remove: bool = false

@export_group("Validation")
@export var validate_root: bool = true

var state: State = State.IDLE
var storage_error: String = ""

var _adapters: Dictionary = {}
var _adapter_order: Array[StringName] = []
var _default_storage_id: StringName = &""


func _enter_tree() -> void:
	state = State.STARTING


func _ready() -> void:
	if scan_children:
		_register_existing_children()

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
		storage_error = ""

	if validate_root and not _validate_root():
		return _fail(storage_error)

	state = State.STARTING

	storage_started.emit()

	var success: bool = true

	if start_registered:
		success = start_all()

	if strict_start and not success:
		return _fail(
			"Một hoặc nhiều Storage Adapter không thể khởi động"
		)

	if _default_storage_id.is_empty():
		_select_default()

	state = State.READY

	storage_ready.emit()

	_log("Storage Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	var success: bool = pause_all()

	if strict_start and not success:
		return false

	state = State.PAUSED

	storage_paused.emit()

	_log("Storage Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	var success: bool = resume_all()

	if strict_start and not success:
		return false

	state = State.READY

	storage_resumed.emit()

	_log("Storage Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func add_adapter(
	adapter: StorageAdapter
) -> bool:
	if not is_instance_valid(adapter):
		_log_error(
			"Không thể thêm Storage Adapter không hợp lệ"
		)
		return false

	if (
		adapter.get_parent() != null
		and adapter.get_parent() != self
	):
		_log_error(
			"Storage Adapter đang thuộc Node khác: "
			+ String(
				adapter.get_storage_id()
			)
		)
		return false

	if adapter.get_parent() == null:
		add_child(adapter)

	return register_adapter(adapter)


func register_adapter(
	adapter: StorageAdapter
) -> bool:
	if not is_instance_valid(adapter):
		_log_error(
			"Không thể đăng ký Storage Adapter không hợp lệ"
		)
		return false

	if adapter.get_parent() != self:
		_log_error(
			"Storage Adapter phải là Child trực tiếp của Storage"
		)
		return false

	var storage_id: StringName = (
		adapter.get_storage_id()
	)

	if storage_id.is_empty():
		_log_error(
			"Storage ID không được để trống"
		)
		return false

	if _adapters.has(storage_id):
		_log_error(
			"Storage ID đã tồn tại: "
			+ String(storage_id)
		)
		return false

	_adapters[storage_id] = adapter
	_adapter_order.append(storage_id)

	_connect_adapter(adapter)

	adapter_registered.emit(
		storage_id
	)

	_log(
		"Storage Adapter Registered: "
		+ String(storage_id)
	)

	if _default_storage_id.is_empty():
		_default_storage_id = storage_id

	if state == State.READY and start_registered:
		var success: bool = adapter.start()

		if strict_start and not success:
			return false

	return true


func unregister_adapter(
	storage_id: StringName
) -> bool:
	if not _adapters.has(storage_id):
		return false

	var adapter: StorageAdapter = (
		_adapters[storage_id]
	)

	if is_instance_valid(adapter):
		if (
			adapter.is_ready()
			or adapter.is_paused()
			or adapter.is_failed()
		):
			adapter.stop()

		_disconnect_adapter(adapter)

		if adapter.get_parent() == self:
			remove_child(adapter)

		_adapters.erase(storage_id)
		_adapter_order.erase(storage_id)

		if _default_storage_id == storage_id:
			_default_storage_id = &""
			_select_default()

		adapter_unregistered.emit(
			storage_id
		)

		_log(
			"Storage Adapter Unregistered: "
			+ String(storage_id)
		)

		if free_on_remove:
			adapter.queue_free()

		return true

	_adapters.erase(storage_id)
	_adapter_order.erase(storage_id)

	return false


func set_default_storage(
	storage_id: StringName
) -> bool:
	if not _adapters.has(storage_id):
		return false

	var adapter: StorageAdapter = (
		get_adapter(storage_id)
	)

	if adapter == null:
		return false

	_default_storage_id = storage_id

	return true


func get_default_storage_id() -> StringName:
	return _default_storage_id


func get_default_storage() -> StorageAdapter:
	if _default_storage_id.is_empty():
		return null

	return get_adapter(
		_default_storage_id
	)


func get_adapter(
	storage_id: StringName
) -> StorageAdapter:
	if not _adapters.has(storage_id):
		return null

	var adapter: StorageAdapter = (
		_adapters[storage_id]
	)

	if not is_instance_valid(adapter):
		_adapters.erase(storage_id)
		_adapter_order.erase(storage_id)

		if _default_storage_id == storage_id:
			_default_storage_id = &""
			_select_default()

		return null

	return adapter


func has_adapter(
	storage_id: StringName
) -> bool:
	return get_adapter(storage_id) != null


func get_adapter_count() -> int:
	return _adapters.size()


func get_adapter_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for storage_id in _adapter_order:
		if _adapters.has(storage_id):
			result.append(storage_id)

	return result


func start_adapter(
	storage_id: StringName
) -> bool:
	var adapter: StorageAdapter = (
		get_adapter(storage_id)
	)

	if adapter == null:
		return false

	return adapter.start()


func pause_adapter(
	storage_id: StringName
) -> bool:
	var adapter: StorageAdapter = (
		get_adapter(storage_id)
	)

	if adapter == null:
		return false

	return adapter.pause()


func resume_adapter(
	storage_id: StringName
) -> bool:
	var adapter: StorageAdapter = (
		get_adapter(storage_id)
	)

	if adapter == null:
		return false

	return adapter.resume()


func stop_adapter(
	storage_id: StringName
) -> bool:
	var adapter: StorageAdapter = (
		get_adapter(storage_id)
	)

	if adapter == null:
		return false

	return adapter.stop()


func ensure_directory(
	relative_path: String = "",
	storage_id: StringName = &""
) -> bool:
	var adapter: StorageAdapter = (
		_resolve_adapter(storage_id)
	)

	if adapter == null:
		return false

	return adapter.ensure_directory(
		relative_path
	)


func file_exists(
	relative_path: String,
	storage_id: StringName = &""
) -> bool:
	var adapter: StorageAdapter = (
		_resolve_adapter(storage_id)
	)

	if adapter == null:
		return false

	return adapter.file_exists(
		relative_path
	)


func write_text(
	relative_path: String,
	content: String,
	storage_id: StringName = &""
) -> bool:
	var adapter: StorageAdapter = (
		_resolve_adapter(storage_id)
	)

	if adapter == null:
		return false

	return adapter.write_text(
		relative_path,
		content
	)


func read_text(
	relative_path: String,
	storage_id: StringName = &""
) -> String:
	var adapter: StorageAdapter = (
		_resolve_adapter(storage_id)
	)

	if adapter == null:
		return ""

	return adapter.read_text(
		relative_path
	)


func write_bytes(
	relative_path: String,
	data: PackedByteArray,
	storage_id: StringName = &""
) -> bool:
	var adapter: StorageAdapter = (
		_resolve_adapter(storage_id)
	)

	if adapter == null:
		return false

	return adapter.write_bytes(
		relative_path,
		data
	)


func read_bytes(
	relative_path: String,
	storage_id: StringName = &""
) -> PackedByteArray:
	var adapter: StorageAdapter = (
		_resolve_adapter(storage_id)
	)

	if adapter == null:
		return PackedByteArray()

	return adapter.read_bytes(
		relative_path
	)


func write_json(
	relative_path: String,
	data: Variant,
	indent: String = "\t",
	storage_id: StringName = &""
) -> bool:
	var adapter: StorageAdapter = (
		_resolve_adapter(storage_id)
	)

	if adapter == null:
		return false

	return adapter.write_json(
		relative_path,
		data,
		indent
	)


func read_json(
	relative_path: String,
	storage_id: StringName = &""
) -> Variant:
	var adapter: StorageAdapter = (
		_resolve_adapter(storage_id)
	)

	if adapter == null:
		return null

	return adapter.read_json(
		relative_path
	)


func delete_file(
	relative_path: String,
	storage_id: StringName = &""
) -> bool:
	var adapter: StorageAdapter = (
		_resolve_adapter(storage_id)
	)

	if adapter == null:
		return false

	return adapter.delete_file(
		relative_path
	)


func directory_exists(
	relative_path: String = "",
	storage_id: StringName = &""
) -> bool:
	var adapter: StorageAdapter = (
		_resolve_adapter(storage_id)
	)

	if adapter == null:
		return false

	return adapter.directory_exists(
		relative_path
	)


func delete_directory(
	relative_path: String,
	storage_id: StringName = &""
) -> bool:
	var adapter: StorageAdapter = (
		_resolve_adapter(storage_id)
	)

	if adapter == null:
		return false

	return adapter.delete_directory(
		relative_path
	)


func list_files(
	relative_path: String = "",
	storage_id: StringName = &""
) -> Array[String]:
	var adapter: StorageAdapter = (
		_resolve_adapter(storage_id)
	)

	if adapter == null:
		return []

	return adapter.list_files(
		relative_path
	)


func list_directories(
	relative_path: String = "",
	storage_id: StringName = &""
) -> Array[String]:
	var adapter: StorageAdapter = (
		_resolve_adapter(storage_id)
	)

	if adapter == null:
		return []

	return adapter.list_directories(
		relative_path
	)


func get_storage_path(
	storage_id: StringName = &""
) -> String:
	var adapter: StorageAdapter = (
		_resolve_adapter(storage_id)
	)

	if adapter == null:
		return ""

	return adapter.get_root_path()


func get_absolute_storage_path(
	storage_id: StringName = &""
) -> String:
	var adapter: StorageAdapter = (
		_resolve_adapter(storage_id)
	)

	if adapter == null:
		return ""

	return adapter.get_absolute_root_path()


func start_all() -> bool:
	var success: bool = true

	for storage_id in get_adapter_ids():
		var adapter: StorageAdapter = (
			get_adapter(storage_id)
		)

		if adapter == null:
			continue

		if not adapter.start():
			success = false

	return success


func pause_all() -> bool:
	var success: bool = true

	for storage_id in get_adapter_ids():
		var adapter: StorageAdapter = (
			get_adapter(storage_id)
		)

		if adapter == null:
			continue

		if adapter.is_ready() and not adapter.pause():
			success = false

	return success


func resume_all() -> bool:
	var success: bool = true

	for storage_id in get_adapter_ids():
		var adapter: StorageAdapter = (
			get_adapter(storage_id)
		)

		if adapter == null:
			continue

		if adapter.is_paused() and not adapter.resume():
			success = false

	return success


func stop_all() -> bool:
	var success: bool = true

	var storage_ids: Array[StringName] = (
		get_adapter_ids()
	)

	storage_ids.reverse()

	for storage_id in storage_ids:
		var adapter: StorageAdapter = (
			get_adapter(storage_id)
		)

		if adapter == null:
			continue

		if (
			not adapter.is_stopped()
			and not adapter.stop()
		):
			success = false

	return success


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
	return storage_error


func _register_existing_children() -> void:
	for child in get_children():
		if child is StorageAdapter:
			register_adapter(child)


func _connect_adapter(
	adapter: StorageAdapter
) -> void:
	if not adapter.adapter_started.is_connected(
		_on_adapter_started
	):
		adapter.adapter_started.connect(
			_on_adapter_started
		)

	if not adapter.adapter_ready.is_connected(
		_on_adapter_ready
	):
		adapter.adapter_ready.connect(
			_on_adapter_ready
		)

	if not adapter.adapter_paused.is_connected(
		_on_adapter_paused
	):
		adapter.adapter_paused.connect(
			_on_adapter_paused
		)

	if not adapter.adapter_resumed.is_connected(
		_on_adapter_resumed
	):
		adapter.adapter_resumed.connect(
			_on_adapter_resumed
		)

	if not adapter.adapter_stopping.is_connected(
		_on_adapter_stopping
	):
		adapter.adapter_stopping.connect(
			_on_adapter_stopping
		)

	if not adapter.adapter_stopped.is_connected(
		_on_adapter_stopped
	):
		adapter.adapter_stopped.connect(
			_on_adapter_stopped
		)

	if not adapter.adapter_failed.is_connected(
		_on_adapter_failed
	):
		adapter.adapter_failed.connect(
			_on_adapter_failed
		)


func _disconnect_adapter(
	adapter: StorageAdapter
) -> void:
	if not is_instance_valid(adapter):
		return

	if adapter.adapter_started.is_connected(
		_on_adapter_started
	):
		adapter.adapter_started.disconnect(
			_on_adapter_started
		)

	if adapter.adapter_ready.is_connected(
		_on_adapter_ready
	):
		adapter.adapter_ready.disconnect(
			_on_adapter_ready
		)

	if adapter.adapter_paused.is_connected(
		_on_adapter_paused
	):
		adapter.adapter_paused.disconnect(
			_on_adapter_paused
		)

	if adapter.adapter_resumed.is_connected(
		_on_adapter_resumed
	):
		adapter.adapter_resumed.disconnect(
			_on_adapter_resumed
		)

	if adapter.adapter_stopping.is_connected(
		_on_adapter_stopping
	):
		adapter.adapter_stopping.disconnect(
			_on_adapter_stopping
		)

	if adapter.adapter_stopped.is_connected(
		_on_adapter_stopped
	):
		adapter.adapter_stopped.disconnect(
			_on_adapter_stopped
		)

	if adapter.adapter_failed.is_connected(
		_on_adapter_failed
	):
		adapter.adapter_failed.disconnect(
			_on_adapter_failed
		)


func _on_adapter_started(
	storage_id: StringName
) -> void:
	adapter_started.emit(
		storage_id
	)


func _on_adapter_ready(
	storage_id: StringName
) -> void:
	adapter_ready.emit(
		storage_id
	)


func _on_adapter_paused(
	storage_id: StringName
) -> void:
	adapter_paused.emit(
		storage_id
	)


func _on_adapter_resumed(
	storage_id: StringName
) -> void:
	adapter_resumed.emit(
		storage_id
	)


func _on_adapter_stopping(
	storage_id: StringName
) -> void:
	adapter_stopping.emit(
		storage_id
	)


func _on_adapter_stopped(
	storage_id: StringName
) -> void:
	adapter_stopped.emit(
		storage_id
	)


func _on_adapter_failed(
	storage_id: StringName,
	reason: String
) -> void:
	adapter_failed.emit(
		storage_id,
		reason
	)

	_log_error(
		"Storage Adapter Failed ["
		+ String(storage_id)
		+ "]: "
		+ reason
	)


func _resolve_adapter(
	storage_id: StringName
) -> StorageAdapter:
	if storage_id.is_empty():
		return get_default_storage()

	return get_adapter(
		storage_id
	)


func _select_default() -> void:
	for storage_id in _adapter_order:
		var adapter: StorageAdapter = (
			get_adapter(storage_id)
		)

		if adapter != null:
			_default_storage_id = storage_id
			return

	_default_storage_id = &""


func _validate_root() -> bool:
	storage_error = ""

	if not is_inside_tree():
		storage_error = (
			"Storage không nằm trong SceneTree"
		)
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Storage: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
			% [
				EXPECTED_NODE_NAME,
				name
			]
		)

	return true


func _fail(
	reason: String
) -> bool:
	state = State.FAILED
	storage_error = reason

	storage_failed.emit(reason)

	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING

	storage_stopping.emit()

	if stop_on_exit:
		stop_all()

	state = State.STOPPED

	storage_stopped.emit()

	_log("Storage Stopped")


func _log(
	message: String
) -> void:
	if console_output:
		print(
			"[Storage] ",
			message
		)


func _log_error(
	message: String
) -> void:
	push_error(
		"[Storage] "
		+ message
) 
