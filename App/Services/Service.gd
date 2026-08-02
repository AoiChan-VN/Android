class_name Service
extends Node

signal service_started(service_id: StringName)
signal service_ready(service_id: StringName)
signal service_paused(service_id: StringName)
signal service_resumed(service_id: StringName)
signal service_stopping(service_id: StringName)
signal service_stopped(service_id: StringName)
signal service_failed(service_id: StringName, reason: String)

enum State {
	IDLE,
	STARTING,
	READY,
	PAUSED,
	STOPPING,
	STOPPED,
	FAILED
}

@export_group("Service")
@export var service_id: StringName = &""
@export var auto_start: bool = true
@export var console_output: bool = true

@export_group("Process")
@export var process_enabled: bool = true
@export var process_priority: int = 0

var state: State = State.IDLE
var service_error: String = ""
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

	_on_service_process(delta)


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
	service_started.emit(service_id)

	if not _validate_service():
		return _fail(service_error)

	if not _on_service_start():
		if service_error.is_empty():
			service_error = "Service không thể khởi động"

		return _fail(service_error)

	state = State.READY
	service_ready.emit(service_id)

	_log("Service Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	if not _on_service_pause():
		return false

	state = State.PAUSED
	service_paused.emit(service_id)

	_log("Service Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	if not _on_service_resume():
		return false

	state = State.READY
	service_resumed.emit(service_id)

	_log("Service Resumed")

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


func get_service_id() -> StringName:
	return service_id


func get_state() -> State:
	return state


func get_service_error() -> String:
	return service_error


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


func _validate_service() -> bool:
	service_error = ""

	if not is_inside_tree():
		service_error = "Service không nằm trong SceneTree"
		return false

	if service_id.is_empty():
		service_error = "Service ID không được để trống"
		return false

	return true


func _on_service_start() -> bool:
	return true


func _on_service_pause() -> bool:
	return true


func _on_service_resume() -> bool:
	return true


func _on_service_process(_delta: float) -> void:
	pass


func _on_service_stop() -> bool:
	return true


func _fail(reason: String) -> bool:
	state = State.FAILED
	service_error = reason

	service_failed.emit(service_id, reason)
	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING
	service_stopping.emit(service_id)

	_log("Service Stopping")

	_on_service_stop()

	state = State.STOPPED
	service_stopped.emit(service_id)

	_log("Service Stopped")


func _log(message: String) -> void:
	if console_output:
		print("[Service:", service_id, "] ", message)


func _log_error(message: String) -> void:
	push_error("[Service:%s] %s" % [service_id, message]) 
