class_name Systems
extends Node

signal systems_started
signal systems_ready
signal systems_paused
signal systems_resumed
signal systems_stopping
signal systems_stopped
signal systems_failed(reason: String)

signal system_registered(system_id: StringName)
signal system_unregistered(system_id: StringName)
signal system_started(system_id: StringName)
signal system_ready(system_id: StringName)
signal system_paused(system_id: StringName)
signal system_resumed(system_id: StringName)
signal system_stopping(system_id: StringName)
signal system_stopped(system_id: StringName)
signal system_failed(system_id: StringName, reason: String)

enum State {
	IDLE,
	STARTING,
	READY,
	PAUSED,
	STOPPING,
	STOPPED,
	FAILED
}

const EXPECTED_NODE_NAME: StringName = &"Systems"

@export_group("Systems")
@export var auto_start: bool = true
@export var auto_register_children: bool = true
@export var start_registered_systems: bool = true
@export var stop_systems_on_shutdown: bool = true
@export var console_output: bool = true
@export var free_on_remove: bool = false

@export_group("Validation")
@export var validate_root: bool = true

var state: State = State.IDLE
var systems_error: String = ""

var _systems: Dictionary = {}
var _system_order: Array[StringName] = []


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
		return _fail(systems_error)

	state = State.STARTING

	systems_started.emit()

	var success: bool = true

	if start_registered_systems:
		success = start_all()

	if not success:
		return _fail("Một hoặc nhiều System không thể khởi động")

	state = State.READY

	systems_ready.emit()

	_log("Systems Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	state = State.PAUSED

	systems_paused.emit()

	for system_id in _get_system_ids_copy():
		var system: System = get_system(system_id)

		if system == null:
			continue

		if system.is_ready():
			system.pause()

	_log("Systems Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	state = State.READY

	systems_resumed.emit()

	for system_id in _get_system_ids_copy():
		var system: System = get_system(system_id)

		if system == null:
			continue

		if system.is_paused():
			system.resume()

	_log("Systems Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func add_system(system: System) -> bool:
	if not is_instance_valid(system):
		_log_error("Không thể thêm System không hợp lệ")
		return false

	if system.get_parent() != null and system.get_parent() != self:
		_log_error(
			"System đang thuộc Node khác: "
			+ String(system.get_system_id())
		)
		return false

	if system.get_parent() == null:
		add_child(system)

	return register_system(system)


func register_system(system: System) -> bool:
	if not is_instance_valid(system):
		_log_error("Không thể đăng ký System không hợp lệ")
		return false

	if system.get_parent() != self:
		_log_error("System phải là Child trực tiếp của Systems")
		return false

	var system_id: StringName = system.get_system_id()

	if system_id.is_empty():
		_log_error("System ID không được để trống")
		return false

	if _systems.has(system_id):
		_log_error("System ID đã tồn tại: " + String(system_id))
		return false

	_systems[system_id] = system
	_system_order.append(system_id)

	system_registered.emit(system_id)

	_log("System Registered: " + String(system_id))

	return true


func unregister_system(system_id: StringName) -> bool:
	if not _systems.has(system_id):
		return false

	var system: System = _systems[system_id]

	if is_instance_valid(system):
		if system.is_ready() or system.is_paused():
			system.stop()

		if system.get_parent() == self:
			remove_child(system)

	_systems.erase(system_id)
	_system_order.erase(system_id)

	system_unregistered.emit(system_id)

	_log("System Unregistered: " + String(system_id))

	if free_on_remove and is_instance_valid(system):
		system.queue_free()

	return true


func get_system(system_id: StringName) -> System:
	if not _systems.has(system_id):
		return null

	var system: System = _systems[system_id]

	if not is_instance_valid(system):
		_systems.erase(system_id)
		_system_order.erase(system_id)
		return null

	return system


func has_system(system_id: StringName) -> bool:
	return _systems.has(system_id)


func get_system_count() -> int:
	return _systems.size()


func get_system_ids() -> Array[StringName]:
	return _get_system_ids_copy()


func start_system(system_id: StringName) -> bool:
	var system: System = get_system(system_id)

	if system == null:
		return false

	return system.start()


func pause_system(system_id: StringName) -> bool:
	var system: System = get_system(system_id)

	if system == null:
		return false

	return system.pause()


func resume_system(system_id: StringName) -> bool:
	var system: System = get_system(system_id)

	if system == null:
		return false

	return system.resume()


func stop_system(system_id: StringName) -> bool:
	var system: System = get_system(system_id)

	if system == null:
		return false

	return system.stop()


func start_all() -> bool:
	var success: bool = true

	for system_id in _get_system_ids_copy():
		var system: System = get_system(system_id)

		if system == null:
			continue

		if not system.start():
			success = false

	return success


func pause_all() -> bool:
	var success: bool = true

	for system_id in _get_system_ids_copy():
		var system: System = get_system(system_id)

		if system == null:
			continue

		if system.is_ready() and not system.pause():
			success = false

	return success


func resume_all() -> bool:
	var success: bool = true

	for system_id in _get_system_ids_copy():
		var system: System = get_system(system_id)

		if system == null:
			continue

		if system.is_paused() and not system.resume():
			success = false

	return success


func stop_all() -> bool:
	var success: bool = true

	var system_ids: Array[StringName] = _get_system_ids_copy()
	system_ids.reverse()

	for system_id in system_ids:
		var system: System = get_system(system_id)

		if system == null:
			continue

		if not system.is_stopped() and not system.stop():
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


func get_systems_error() -> String:
	return systems_error


func _register_existing_children() -> void:
	for child in get_children():
		if child is System:
			register_system(child)


func _get_system_ids_copy() -> Array[StringName]:
	var result: Array[StringName] = []

	for system_id in _system_order:
		if _systems.has(system_id):
			result.append(system_id)

	return result


func _validate_root() -> bool:
	systems_error = ""

	if not is_inside_tree():
		systems_error = "Systems không nằm trong SceneTree"
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Systems: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
			% [EXPECTED_NODE_NAME, name]
		)

	return true


func _fail(reason: String) -> bool:
	state = State.FAILED
	systems_error = reason

	systems_failed.emit(reason)

	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING

	systems_stopping.emit()

	if stop_systems_on_shutdown:
		stop_all()

	state = State.STOPPED

	systems_stopped.emit()

	_log("Systems Stopped")


func _log(message: String) -> void:
	if console_output:
		print("[Systems] ", message)


func _log_error(message: String) -> void:
	push_error("[Systems] " + message) 
