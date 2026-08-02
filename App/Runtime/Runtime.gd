class_name Runtime
extends Node

signal runtime_started
signal runtime_paused
signal runtime_resumed
signal runtime_stopped
signal runtime_failed(reason: String)

enum State {
	IDLE,
	STARTING,
	RUNNING,
	PAUSED,
	STOPPING,
	STOPPED,
	FAILED
}

const EXPECTED_NODE_NAME: StringName = &"Runtime"

@export_group("Runtime")
@export var auto_start: bool = true
@export var process_enabled: bool = true
@export var console_output: bool = true

var state: State = State.IDLE
var elapsed_time: float = 0.0
var frame_count: int = 0
var runtime_error: String = ""


func _enter_tree() -> void:
	state = State.STARTING


func _ready() -> void:
	set_process(process_enabled)

	if auto_start:
		start()


func _process(delta: float) -> void:
	if state != State.RUNNING:
		return

	if not process_enabled:
		return

	elapsed_time += delta
	frame_count += 1


func _exit_tree() -> void:
	_shutdown()


func start() -> bool:
	if state == State.RUNNING:
		return true

	if state == State.PAUSED:
		return resume()

	if state == State.STOPPING:
		return false

	if state == State.STOPPED:
		return false

	if state == State.FAILED:
		return false

	if not _validate_root():
		state = State.FAILED
		runtime_failed.emit(runtime_error)
		_log_error(runtime_error)
		return false

	state = State.RUNNING
	runtime_started.emit()
	_log("Runtime Started")

	return true


func pause() -> bool:
	if state != State.RUNNING:
		return false

	state = State.PAUSED
	runtime_paused.emit()
	_log("Runtime Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	state = State.RUNNING
	runtime_resumed.emit()
	_log("Runtime Resumed")

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


func is_running() -> bool:
	return state == State.RUNNING


func is_paused() -> bool:
	return state == State.PAUSED


func is_stopped() -> bool:
	return state == State.STOPPED


func get_state() -> State:
	return state


func get_elapsed_time() -> float:
	return elapsed_time


func get_frame_count() -> int:
	return frame_count


func _validate_root() -> bool:
	runtime_error = ""

	if not is_inside_tree():
		runtime_error = "Runtime không nằm trong SceneTree"
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Runtime: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
			% [EXPECTED_NODE_NAME, name]
		)

	return true


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING
	_log("Runtime Stopping")

	state = State.STOPPED
	runtime_stopped.emit()
	_log("Runtime Stopped")


func _log(message: String) -> void:
	if console_output:
		print("[Runtime] ", message)


func _log_error(message: String) -> void:
	push_error("[Runtime] " + message) 
