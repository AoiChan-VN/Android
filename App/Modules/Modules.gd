class_name Modules
extends Node

signal modules_started
signal modules_ready
signal modules_paused
signal modules_resumed
signal modules_stopping
signal modules_stopped
signal modules_failed(reason: String)

signal module_registered(module_id: StringName)
signal module_unregistered(module_id: StringName)
signal module_started(module_id: StringName)
signal module_ready(module_id: StringName)
signal module_paused(module_id: StringName)
signal module_resumed(module_id: StringName)
signal module_stopping(module_id: StringName)
signal module_stopped(module_id: StringName)
signal module_failed(module_id: StringName, reason: String)

enum State {
	IDLE,
	STARTING,
	READY,
	PAUSED,
	STOPPING,
	STOPPED,
	FAILED
}

const EXPECTED_NODE_NAME: StringName = &"Modules"

@export_group("Modules")
@export var auto_start: bool = true
@export var auto_register_children: bool = true
@export var start_registered_modules: bool = true
@export var stop_modules_on_shutdown: bool = true
@export var console_output: bool = true
@export var free_on_remove: bool = false

@export_group("Validation")
@export var validate_root: bool = true

var state: State = State.IDLE
var modules_error: String = ""

var _modules: Dictionary = {}
var _connections: Dictionary = {}


func _enter_tree() -> void:
	state = State.STARTING


func _ready() -> void:
	if auto_register_children:
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

	if state == State.STOPPED:
		return false

	if state == State.FAILED:
		return false

	if validate_root and not _validate_root():
		return _fail(modules_error)

	state = State.STARTING
	modules_started.emit()

	var success: bool = true

	if start_registered_modules:
		success = start_all()

	if not success:
		return _fail("Một hoặc nhiều Module không thể khởi động")

	state = State.READY
	modules_ready.emit()

	_log("Modules Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	state = State.PAUSED
	modules_paused.emit()

	for module_id in _get_module_ids_copy():
		var module: Module = _modules[module_id]

		if module.is_ready():
			module.pause()

	_log("Modules Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	state = State.READY
	modules_resumed.emit()

	for module_id in _get_module_ids_copy():
		var module: Module = _modules[module_id]

		if module.is_paused():
			module.resume()

	_log("Modules Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func add_module(module: Module) -> bool:
	if not is_instance_valid(module):
		_log_error("Không thể thêm Module không hợp lệ")
		return false

	if module.get_parent() != null and module.get_parent() != self:
		_log_error("Module đang thuộc Node khác: " + String(module.get_module_id()))
		return false

	if module.get_parent() == null:
		add_child(module)

	return register_module(module)


func register_module(module: Module) -> bool:
	if not is_instance_valid(module):
		_log_error("Không thể đăng ký Module không hợp lệ")
		return false

	if module.get_parent() != self:
		_log_error("Module phải là Child trực tiếp của Modules")
		return false

	var module_id: StringName = module.get_module_id()

	if module_id.is_empty():
		_log_error("Module ID không được để trống")
		return false

	if _modules.has(module_id):
		_log_error("Module ID đã tồn tại: " + String(module_id))
		return false

	_modules[module_id] = module
	_connect_module(module)

	module_registered.emit(module_id)

	_log("Module Registered: " + String(module_id))

	return true


func unregister_module(module_id: StringName) -> bool:
	if not _modules.has(module_id):
		return false

	var module: Module = _modules[module_id]

	if is_instance_valid(module):
		if module.is_ready() or module.is_paused():
			module.stop()

		_disconnect_module(module)

		if module.get_parent() == self:
			remove_child(module)

	_modules.erase(module_id)

	module_unregistered.emit(module_id)

	_log("Module Unregistered: " + String(module_id))

	if free_on_remove and is_instance_valid(module):
		module.queue_free()

	return true


func get_module(module_id: StringName) -> Module:
	if not _modules.has(module_id):
		return null

	var module: Module = _modules[module_id]

	if not is_instance_valid(module):
		_modules.erase(module_id)
		return null

	return module


func has_module(module_id: StringName) -> bool:
	return _modules.has(module_id)


func get_module_count() -> int:
	return _modules.size()


func get_module_ids() -> Array[StringName]:
	return _get_module_ids_copy()


func start_module(module_id: StringName) -> bool:
	var module: Module = get_module(module_id)

	if module == null:
		return false

	return module.start()


func pause_module(module_id: StringName) -> bool:
	var module: Module = get_module(module_id)

	if module == null:
		return false

	return module.pause()


func resume_module(module_id: StringName) -> bool:
	var module: Module = get_module(module_id)

	if module == null:
		return false

	return module.resume()


func stop_module(module_id: StringName) -> bool:
	var module: Module = get_module(module_id)

	if module == null:
		return false

	return module.stop()


func start_all() -> bool:
	var success: bool = true

	for module_id in _get_module_ids_copy():
		var module: Module = get_module(module_id)

		if module == null:
			continue

		if not module.start():
			success = false

	return success


func pause_all() -> bool:
	var success: bool = true

	for module_id in _get_module_ids_copy():
		var module: Module = get_module(module_id)

		if module == null:
			continue

		if module.is_ready() and not module.pause():
			success = false

	return success


func resume_all() -> bool:
	var success: bool = true

	for module_id in _get_module_ids_copy():
		var module: Module = get_module(module_id)

		if module == null:
			continue

		if module.is_paused() and not module.resume():
			success = false

	return success


func stop_all() -> bool:
	var success: bool = true

	for module_id in _get_module_ids_copy():
		var module: Module = get_module(module_id)

		if module == null:
			continue

		if not module.is_stopped() and not module.stop():
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


func get_modules_error() -> String:
	return modules_error


func _register_existing_children() -> void:
	for child in get_children():
		if child is Module:
			register_module(child)


func _connect_module(module: Module) -> void:
	if _connections.has(module):
		return

	var connections: Dictionary = {
		"started": module.module_started.connect(_on_module_started),
		"ready": module.module_ready.connect(_on_module_ready),
		"paused": module.module_paused.connect(_on_module_paused),
		"resumed": module.module_resumed.connect(_on_module_resumed),
		"stopping": module.module_stopping.connect(_on_module_stopping),
		"stopped": module.module_stopped.connect(_on_module_stopped),
		"failed": module.module_failed.connect(_on_module_failed)
	}

	_connections[module] = connections


func _disconnect_module(module: Module) -> void:
	if not _connections.has(module):
		return

	if is_instance_valid(module):
		if module.module_started.is_connected(_on_module_started):
			module.module_started.disconnect(_on_module_started)

		if module.module_ready.is_connected(_on_module_ready):
			module.module_ready.disconnect(_on_module_ready)

		if module.module_paused.is_connected(_on_module_paused):
			module.module_paused.disconnect(_on_module_paused)

		if module.module_resumed.is_connected(_on_module_resumed):
			module.module_resumed.disconnect(_on_module_resumed)

		if module.module_stopping.is_connected(_on_module_stopping):
			module.module_stopping.disconnect(_on_module_stopping)

		if module.module_stopped.is_connected(_on_module_stopped):
			module.module_stopped.disconnect(_on_module_stopped)

		if module.module_failed.is_connected(_on_module_failed):
			module.module_failed.disconnect(_on_module_failed)

	_connections.erase(module)


func _on_module_started(module_id: StringName) -> void:
	module_started.emit(module_id)


func _on_module_ready(module_id: StringName) -> void:
	module_ready.emit(module_id)


func _on_module_paused(module_id: StringName) -> void:
	module_paused.emit(module_id)


func _on_module_resumed(module_id: StringName) -> void:
	module_resumed.emit(module_id)


func _on_module_stopping(module_id: StringName) -> void:
	module_stopping.emit(module_id)


func _on_module_stopped(module_id: StringName) -> void:
	module_stopped.emit(module_id)


func _on_module_failed(module_id: StringName, reason: String) -> void:
	module_failed.emit(module_id, reason)
	_log_error("Module Failed [" + String(module_id) + "]: " + reason)


func _get_module_ids_copy() -> Array[StringName]:
	var result: Array[StringName] = []

	for module_id in _modules.keys():
		result.append(module_id)

	return result


func _validate_root() -> bool:
	modules_error = ""

	if not is_inside_tree():
		modules_error = "Modules không nằm trong SceneTree"
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Modules: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
			% [EXPECTED_NODE_NAME, name]
		)

	return true


func _fail(reason: String) -> bool:
	state = State.FAILED
	modules_error = reason

	modules_failed.emit(reason)
	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING
	modules_stopping.emit()

	if stop_modules_on_shutdown:
		stop_all()

	state = State.STOPPED
	modules_stopped.emit()

	_log("Modules Stopped")


func _log(message: String) -> void:
	if console_output:
		print("[Modules] ", message)


func _log_error(message: String) -> void:
	push_error("[Modules] " + message) 
