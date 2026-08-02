class_name Kernel
extends Node

signal kernel_started
signal kernel_ready
signal kernel_paused
signal kernel_resumed
signal kernel_stopping
signal kernel_stopped
signal kernel_failed(reason: String)
signal unit_registered(unit_id: StringName)
signal unit_unregistered(unit_id: StringName)

enum State {
	IDLE,
	STARTING,
	READY,
	PAUSED,
	STOPPING,
	STOPPED,
	FAILED
}

const EXPECTED_NODE_NAME: StringName = &"Kernel"

@export_group("Kernel")
@export var auto_start: bool = true
@export var console_output: bool = true

@export_group("Process")
@export var process_enabled: bool = true
@export var process_priority: int = 0

@export_group("Validation")
@export var validate_root: bool = true

var state: State = State.IDLE
var kernel_error: String = ""
var frame_count: int = 0
var process_time: float = 0.0

var _units: Dictionary = {}
var _pending_commands: Array[Callable] = []


func _enter_tree() -> void:
	state = State.STARTING
	process_priority = process_priority


func _ready() -> void:
	set_process_priority(process_priority)
	set_process(process_enabled)

	if auto_start:
		start()


func _process(delta: float) -> void:
	if state != State.READY:
		return

	frame_count += 1
	process_time += delta
	_execute_pending_commands()


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

	kernel_started.emit()

	if validate_root and not _validate_root():
		return _fail(kernel_error)

	state = State.READY
	kernel_ready.emit()
	_log("Kernel Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	state = State.PAUSED
	kernel_paused.emit()
	_log("Kernel Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	state = State.READY
	kernel_resumed.emit()
	_log("Kernel Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func register_unit(
	unit_id: StringName,
	start_callable: Callable = Callable(),
	stop_callable: Callable = Callable()
) -> bool:
	if unit_id.is_empty():
		_log_error("Không thể đăng ký Unit với ID rỗng")
		return false

	if _units.has(unit_id):
		_log_error("Unit đã tồn tại: " + String(unit_id))
		return false

	_units[unit_id] = {
		"start": start_callable,
		"stop": stop_callable
	}

	unit_registered.emit(unit_id)
	_log("Unit Registered: " + String(unit_id))

	return true


func unregister_unit(unit_id: StringName) -> bool:
	if not _units.has(unit_id):
		return false

	_units.erase(unit_id)
	unit_unregistered.emit(unit_id)
	_log("Unit Unregistered: " + String(unit_id))

	return true


func has_unit(unit_id: StringName) -> bool:
	return _units.has(unit_id)


func get_unit_count() -> int:
	return _units.size()


func get_unit_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for unit_id in _units.keys():
		result.append(unit_id)

	return result


func queue_command(command: Callable) -> bool:
	if not command.is_valid():
		_log_error("Không thể đưa Callable không hợp lệ vào Kernel Queue")
		return false

	_pending_commands.append(command)
	return true


func clear_pending_commands() -> void:
	_pending_commands.clear()


func get_pending_command_count() -> int:
	return _pending_commands.size()


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


func get_kernel_error() -> String:
	return kernel_error


func get_frame_count() -> int:
	return frame_count


func get_process_time() -> float:
	return process_time


func _execute_pending_commands() -> void:
	if _pending_commands.is_empty():
		return

	var commands: Array[Callable] = _pending_commands.duplicate()
	_pending_commands.clear()

	for command in commands:
		if command.is_valid():
			command.call()


func _validate_root() -> bool:
	kernel_error = ""

	if not is_inside_tree():
		kernel_error = "Kernel không nằm trong SceneTree"
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Kernel: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
			% [EXPECTED_NODE_NAME, name]
		)

	return true


func _fail(reason: String) -> bool:
	state = State.FAILED
	kernel_error = reason
	kernel_failed.emit(reason)
	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING
	kernel_stopping.emit()
	_log("Kernel Stopping")

	_pending_commands.clear()

	state = State.STOPPED
	kernel_stopped.emit()
	_log("Kernel Stopped")


func _log(message: String) -> void:
	if console_output:
		print("[Kernel] ", message)


func _log_error(message: String) -> void:
	push_error("[Kernel] " + message) 
