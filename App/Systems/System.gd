class_name System
extends Node

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

@export_group("System")
@export var system_id: StringName = &""
@export var auto_start: bool = true
@export var console_output: bool = true

@export_group("Process")
@export var process_enabled: bool = true
@export var process_priority: int = 0

var state: State = State.IDLE
var system_error: String = ""
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

	_on_system_process(delta)


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

	system_started.emit(system_id)

	if not _validate_system():
		return _fail(system_error)

	if not _on_system_start():
		if system_error.is_empty():
			system_error = "System không thể khởi động"

		return _fail(system_error)

	state = State.READY

	system_ready.emit(system_id)

	_log("System Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	if not _on_system_pause():
		return false

	state = State.PAUSED

	system_paused.emit(system_id)

	_log("System Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	if not _on_system_resume():
		return false

	state = State.READY

	system_resumed.emit(system_id)

	_log("System Resumed")

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


func get_system_id() -> StringName:
	return system_id


func get_state() -> State:
	return state


func get_system_error() -> String:
	return system_error


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


func _validate_system() -> bool:
	system_error = ""

	if not is_inside_tree():
		system_error = "System không nằm trong SceneTree"
		return false

	if system_id.is_empty():
		system_error = "System ID không được để trống"
		return false

	return true


func _on_system_start() -> bool:
	return true


func _on_system_pause() -> bool:
	return true


func _on_system_resume() -> bool:
	return true


func _on_system_process(_delta: float) -> void:
	pass


func _on_system_stop() -> bool:
	return true


func _fail(reason: String) -> bool:
	state = State.FAILED
	system_error = reason

	system_failed.emit(system_id, reason)

	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING

	system_stopping.emit(system_id)

	_log("System Stopping")

	_on_system_stop()

	state = State.STOPPED

	system_stopped.emit(system_id)

	_log("System Stopped")


func _log(message: String) -> void:
	if console_output:
		print("[System:", system_id, "] ", message)


func _log_error(message: String) -> void:
	push_error("[System:%s] %s" % [system_id, message]) 
