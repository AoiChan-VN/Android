class_name Infrastructure
extends Node

signal infrastructure_started
signal infrastructure_ready
signal infrastructure_paused
signal infrastructure_resumed
signal infrastructure_stopping
signal infrastructure_stopped
signal infrastructure_failed(reason: String)

signal adapter_registered(
	adapter_id: StringName,
	adapter_type: int
)

signal adapter_unregistered(
	adapter_id: StringName,
	adapter_type: int
)

signal adapter_started(
	adapter_id: StringName
)

signal adapter_ready(
	adapter_id: StringName
)

signal adapter_paused(
	adapter_id: StringName
)

signal adapter_resumed(
	adapter_id: StringName
)

signal adapter_stopping(
	adapter_id: StringName
)

signal adapter_stopped(
	adapter_id: StringName
)

signal adapter_failed(
	adapter_id: StringName,
	reason: String
)

signal adapter_health_changed(
	adapter_id: StringName,
	healthy: bool
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

const EXPECTED_NODE_NAME: StringName = &"Infrastructure"

@export_group("Infrastructure")
@export var auto_start: bool = true
@export var scan_children: bool = true
@export var start_registered_adapters: bool = true
@export var stop_on_exit: bool = true
@export var strict_start: bool = false
@export var console_output: bool = true
@export var free_on_remove: bool = false

@export_group("Validation")
@export var validate_root: bool = true

var state: State = State.IDLE
var infrastructure_error: String = ""

var _adapters: Dictionary = {}
var _adapter_order: Array[StringName] = []


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
		infrastructure_error = ""

	if validate_root and not _validate_root():
		return _fail(infrastructure_error)

	state = State.STARTING

	infrastructure_started.emit()

	var success: bool = true

	if start_registered_adapters:
		success = start_all()

	if strict_start and not success:
		return _fail(
			"Một hoặc nhiều Infrastructure Adapter không thể khởi động"
		)

	state = State.READY

	infrastructure_ready.emit()

	_log("Infrastructure Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	var success: bool = pause_all()

	if strict_start and not success:
		return false

	state = State.PAUSED

	infrastructure_paused.emit()

	_log("Infrastructure Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	var success: bool = resume_all()

	if strict_start and not success:
		return false

	state = State.READY

	infrastructure_resumed.emit()

	_log("Infrastructure Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func add_adapter(
	adapter: InfrastructureAdapter
) -> bool:
	if not is_instance_valid(adapter):
		_log_error(
			"Không thể thêm Infrastructure Adapter không hợp lệ"
		)
		return false

	if (
		adapter.get_parent() != null
		and adapter.get_parent() != self
	):
		_log_error(
			"Adapter đang thuộc Node khác: "
			+ String(adapter.get_adapter_id())
		)
		return false

	if adapter.get_parent() == null:
		add_child(adapter)

	return register_adapter(adapter)


func register_adapter(
	adapter: InfrastructureAdapter
) -> bool:
	if not is_instance_valid(adapter):
		_log_error(
			"Không thể đăng ký Infrastructure Adapter không hợp lệ"
		)
		return false

	if adapter.get_parent() != self:
		_log_error(
			"Adapter phải là Child trực tiếp của Infrastructure"
		)
		return false

	var adapter_id: StringName = (
		adapter.get_adapter_id()
	)

	if adapter_id.is_empty():
		_log_error(
			"Adapter ID không được để trống"
		)
		return false

	if _adapters.has(adapter_id):
		_log_error(
			"Adapter ID đã tồn tại: "
			+ String(adapter_id)
		)
		return false

	_adapters[adapter_id] = adapter
	_adapter_order.append(adapter_id)

	_connect_adapter(adapter)

	adapter_registered.emit(
		adapter_id,
		int(adapter.get_adapter_type())
	)

	_log(
		"Adapter Registered: "
		+ String(adapter_id)
	)

	if state == State.READY and start_registered_adapters:
		var success: bool = adapter.start()

		if strict_start and not success:
			return false

	return true


func unregister_adapter(
	adapter_id: StringName
) -> bool:
	if not _adapters.has(adapter_id):
		return false

	var adapter: InfrastructureAdapter = (
		_adapters[adapter_id]
	)

	if is_instance_valid(adapter):
		var adapter_type: int = (
			int(adapter.get_adapter_type())
		)

		if (
			adapter.is_ready()
			or adapter.is_paused()
			or adapter.is_failed()
		):
			adapter.stop()

		_disconnect_adapter(adapter)

		if adapter.get_parent() == self:
			remove_child(adapter)

		_adapters.erase(adapter_id)
		_adapter_order.erase(adapter_id)

		adapter_unregistered.emit(
			adapter_id,
			adapter_type
		)

		_log(
			"Adapter Unregistered: "
			+ String(adapter_id)
		)

		if free_on_remove:
			adapter.queue_free()

		return true

	_adapters.erase(adapter_id)
	_adapter_order.erase(adapter_id)

	return false


func get_adapter(
	adapter_id: StringName
) -> InfrastructureAdapter:
	if not _adapters.has(adapter_id):
		return null

	var adapter: InfrastructureAdapter = (
		_adapters[adapter_id]
	)

	if not is_instance_valid(adapter):
		_adapters.erase(adapter_id)
		_adapter_order.erase(adapter_id)
		return null

	return adapter


func has_adapter(
	adapter_id: StringName
) -> bool:
	return get_adapter(adapter_id) != null


func get_adapter_count() -> int:
	return _adapters.size()


func get_adapter_ids() -> Array[StringName]:
	return _get_adapter_ids_copy()


func get_adapter_ids_by_type(
	adapter_type: int
) -> Array[StringName]:
	var result: Array[StringName] = []

	for adapter_id in _get_adapter_ids_copy():
		var adapter: InfrastructureAdapter = (
			get_adapter(adapter_id)
		)

		if adapter == null:
			continue

		if int(adapter.get_adapter_type()) == adapter_type:
			result.append(adapter_id)

	return result


func get_adapters_by_type(
	adapter_type: int
) -> Array[InfrastructureAdapter]:
	var result: Array[InfrastructureAdapter] = []

	for adapter_id in get_adapter_ids_by_type(
		adapter_type
	):
		var adapter: InfrastructureAdapter = (
			get_adapter(adapter_id)
		)

		if adapter != null:
			result.append(adapter)

	return result


func get_adapter_ids_by_capability(
	capability_id: StringName
) -> Array[StringName]:
	var result: Array[StringName] = []

	for adapter_id in _get_adapter_ids_copy():
		var adapter: InfrastructureAdapter = (
			get_adapter(adapter_id)
		)

		if adapter == null:
			continue

		if adapter.has_capability(capability_id):
			result.append(adapter_id)

	return result


func start_adapter(
	adapter_id: StringName
) -> bool:
	var adapter: InfrastructureAdapter = (
		get_adapter(adapter_id)
	)

	if adapter == null:
		return false

	return adapter.start()


func pause_adapter(
	adapter_id: StringName
) -> bool:
	var adapter: InfrastructureAdapter = (
		get_adapter(adapter_id)
	)

	if adapter == null:
		return false

	return adapter.pause()


func resume_adapter(
	adapter_id: StringName
) -> bool:
	var adapter: InfrastructureAdapter = (
		get_adapter(adapter_id)
	)

	if adapter == null:
		return false

	return adapter.resume()


func stop_adapter(
	adapter_id: StringName
) -> bool:
	var adapter: InfrastructureAdapter = (
		get_adapter(adapter_id)
	)

	if adapter == null:
		return false

	return adapter.stop()


func check_adapter_health(
	adapter_id: StringName
) -> bool:
	var adapter: InfrastructureAdapter = (
		get_adapter(adapter_id)
	)

	if adapter == null:
		return false

	return adapter.check_health()


func check_all_health() -> bool:
	var success: bool = true

	for adapter_id in _get_adapter_ids_copy():
		var adapter: InfrastructureAdapter = (
			get_adapter(adapter_id)
		)

		if adapter == null:
			continue

		if not adapter.check_health():
			success = false

	return success


func start_all() -> bool:
	var success: bool = true

	for adapter_id in _get_adapter_ids_copy():
		var adapter: InfrastructureAdapter = (
			get_adapter(adapter_id)
		)

		if adapter == null:
			continue

		if not adapter.start():
			success = false

	return success


func pause_all() -> bool:
	var success: bool = true

	for adapter_id in _get_adapter_ids_copy():
		var adapter: InfrastructureAdapter = (
			get_adapter(adapter_id)
		)

		if adapter == null:
			continue

		if adapter.is_ready() and not adapter.pause():
			success = false

	return success


func resume_all() -> bool:
	var success: bool = true

	for adapter_id in _get_adapter_ids_copy():
		var adapter: InfrastructureAdapter = (
			get_adapter(adapter_id)
		)

		if adapter == null:
			continue

		if adapter.is_paused() and not adapter.resume():
			success = false

	return success


func stop_all() -> bool:
	var success: bool = true

	var adapter_ids: Array[StringName] = (
		_get_adapter_ids_copy()
	)

	adapter_ids.reverse()

	for adapter_id in adapter_ids:
		var adapter: InfrastructureAdapter = (
			get_adapter(adapter_id)
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
	return infrastructure_error


func _register_existing_children() -> void:
	for child in get_children():
		if child is InfrastructureAdapter:
			register_adapter(child)


func _connect_adapter(
	adapter: InfrastructureAdapter
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

	if not adapter.health_changed.is_connected(
		_on_adapter_health_changed
	):
		adapter.health_changed.connect(
			_on_adapter_health_changed
		)


func _disconnect_adapter(
	adapter: InfrastructureAdapter
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

	if adapter.health_changed.is_connected(
		_on_adapter_health_changed
	):
		adapter.health_changed.disconnect(
			_on_adapter_health_changed
		)


func _on_adapter_started(
	adapter_id: StringName
) -> void:
	adapter_started.emit(adapter_id)


func _on_adapter_ready(
	adapter_id: StringName
) -> void:
	adapter_ready.emit(adapter_id)


func _on_adapter_paused(
	adapter_id: StringName
) -> void:
	adapter_paused.emit(adapter_id)


func _on_adapter_resumed(
	adapter_id: StringName
) -> void:
	adapter_resumed.emit(adapter_id)


func _on_adapter_stopping(
	adapter_id: StringName
) -> void:
	adapter_stopping.emit(adapter_id)


func _on_adapter_stopped(
	adapter_id: StringName
) -> void:
	adapter_stopped.emit(adapter_id)


func _on_adapter_failed(
	adapter_id: StringName,
	reason: String
) -> void:
	adapter_failed.emit(
		adapter_id,
		reason
	)

	_log_error(
		"Adapter Failed ["
		+ String(adapter_id)
		+ "]: "
		+ reason
	)


func _on_adapter_health_changed(
	adapter_id: StringName,
	healthy: bool
) -> void:
	adapter_health_changed.emit(
		adapter_id,
		healthy
	)


func _get_adapter_ids_copy() -> Array[StringName]:
	var result: Array[StringName] = []

	for adapter_id in _adapter_order:
		if _adapters.has(adapter_id):
			result.append(adapter_id)

	return result


func _validate_root() -> bool:
	infrastructure_error = ""

	if not is_inside_tree():
		infrastructure_error = (
			"Infrastructure không nằm trong SceneTree"
		)
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Infrastructure: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
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
	infrastructure_error = reason

	infrastructure_failed.emit(reason)

	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING

	infrastructure_stopping.emit()

	if stop_on_exit:
		stop_all()

	state = State.STOPPED

	infrastructure_stopped.emit()

	_log("Infrastructure Stopped")


func _log(
	message: String
) -> void:
	if console_output:
		print(
			"[Infrastructure] ",
			message
		)


func _log_error(
	message: String
) -> void:
	push_error(
		"[Infrastructure] "
		+ message
) 
