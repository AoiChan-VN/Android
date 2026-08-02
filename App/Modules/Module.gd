class_name Module
extends Node

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

@export_group("Module")
@export var module_id: StringName = &""
@export var auto_start: bool = true
@export var console_output: bool = true

@export_group("Process")
@export var process_enabled: bool = true
@export var process_priority: int = 0

var state: State = State.IDLE
var module_error: String = ""
var elapsed_time: float = 0.0
var frame_count: int = 0


func _enter_tree() -> void:
	state = State.STARTING


func _ready() -> void:
	set_process_priority(process_priority)
	set_process(process_enabled)

	if auto_start:
		start()


func _process(delta: float) -> void:
	if state != State.READY:
		return

	elapsed_time += delta
	frame_count += 1


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

	state = State.STARTING
	module_started.emit(module_id)

	if not _validate_module():
		return _fail(module_error)

	state = State.READY
	module_ready.emit(module_id)

	_log("Module Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	state = State.PAUSED
	module_paused.emit(module_id)

	_log("Module Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	state = State.READY
	module_resumed.emit(module_id)

	_log("Module Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func set_processing_enabled(enabled: bool) -> void:
	process_enabled = enabled
	set_process(enabled)


func get_module_id() -> StringName:
	return module_id


func get_state() -> State:
	return state


func get_module_error() -> String:
	return module_error


func get_elapsed_time() -> float:
	return elapsed_time


func get_frame_count() -> int:
	return frame_count


func is_ready() -> bool:
	return state == State.READY


func is_paused() -> bool:
	return state == State.PAUSED


func is_stopped() -> bool:
	return state == State.STOPPED


func is_failed() -> bool:
	return state == State.FAILED


func _validate_module() -> bool:
	module_error = ""

	if not is_inside_tree():
		module_error = "Module không nằm trong SceneTree"
		return false

	if module_id.is_empty():
		module_error = "Module ID không được để trống"
		return false

	return true


func _fail(reason: String) -> bool:
	state = State.FAILED
	module_error = reason

	module_failed.emit(module_id, reason)
	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING
	module_stopping.emit(module_id)

	_log("Module Stopping")

	state = State.STOPPED
	module_stopped.emit(module_id)

	_log("Module Stopped")


func _log(message: String) -> void:
	if console_output:
		print("[Module:", module_id, "] ", message)


func _log_error(message: String) -> void:
	push_error("[Module:%s] %s" % [module_id, message]) 
