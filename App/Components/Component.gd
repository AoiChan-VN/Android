class_name Component
extends Node

signal component_started(component_id: StringName)
signal component_ready(component_id: StringName)
signal component_paused(component_id: StringName)
signal component_resumed(component_id: StringName)
signal component_stopping(component_id: StringName)
signal component_stopped(component_id: StringName)
signal component_failed(component_id: StringName, reason: String)

enum State {
	IDLE,
	STARTING,
	READY,
	PAUSED,
	STOPPING,
	STOPPED,
	FAILED
}

@export_group("Component")
@export var component_id: StringName = &""
@export var auto_start: bool = true
@export var console_output: bool = true

@export_group("Process")
@export var process_enabled: bool = true
@export var process_priority: int = 0

var state: State = State.IDLE
var component_error: String = ""
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

	_on_component_process(delta)


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

	component_started.emit(component_id)

	if not _validate_component():
		return _fail(component_error)

	if not _on_component_start():
		if component_error.is_empty():
			component_error = "Component không thể khởi động"

		return _fail(component_error)

	state = State.READY

	component_ready.emit(component_id)

	_log("Component Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	if not _on_component_pause():
		return false

	state = State.PAUSED

	component_paused.emit(component_id)

	_log("Component Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	if not _on_component_resume():
		return false

	state = State.READY

	component_resumed.emit(component_id)

	_log("Component Resumed")

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


func get_component_id() -> StringName:
	return component_id


func get_state() -> State:
	return state


func get_component_error() -> String:
	return component_error


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


func _validate_component() -> bool:
	component_error = ""

	if not is_inside_tree():
		component_error = "Component không nằm trong SceneTree"
		return false

	if component_id.is_empty():
		component_error = "Component ID không được để trống"
		return false

	return true


func _on_component_start() -> bool:
	return true


func _on_component_pause() -> bool:
	return true


func _on_component_resume() -> bool:
	return true


func _on_component_process(_delta: float) -> void:
	pass


func _on_component_stop() -> bool:
	return true


func _fail(reason: String) -> bool:
	state = State.FAILED
	component_error = reason

	component_failed.emit(component_id, reason)

	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING

	component_stopping.emit(component_id)

	_log("Component Stopping")

	_on_component_stop()

	state = State.STOPPED

	component_stopped.emit(component_id)

	_log("Component Stopped")


func _log(message: String) -> void:
	if console_output:
		print("[Component:", component_id, "] ", message)


func _log_error(message: String) -> void:
	push_error("[Component:%s] %s" % [component_id, message]) 
