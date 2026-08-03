class_name InfrastructureAdapter
extends Node

signal adapter_started(adapter_id: StringName)
signal adapter_ready(adapter_id: StringName)
signal adapter_paused(adapter_id: StringName)
signal adapter_resumed(adapter_id: StringName)
signal adapter_stopping(adapter_id: StringName)
signal adapter_stopped(adapter_id: StringName)
signal adapter_failed(adapter_id: StringName, reason: String)
signal health_changed(adapter_id: StringName, healthy: bool)

enum State {
	IDLE,
	STARTING,
	READY,
	PAUSED,
	STOPPING,
	STOPPED,
	FAILED
}

enum AdapterType {
	UNKNOWN,
	PLATFORM,
	FILE_SYSTEM,
	PROCESS,
	TIME,
	INPUT,
	OUTPUT,
	NETWORK,
	CUSTOM
}

@export_group("Adapter")
@export var adapter_id: StringName = &""
@export var adapter_type: AdapterType = AdapterType.UNKNOWN
@export var capabilities: Array[StringName] = []
@export var auto_start: bool = true
@export var console_output: bool = true

@export_group("Process")
@export var process_enabled: bool = false
@export var process_priority: int = 0

var state: State = State.IDLE
var adapter_error: String = ""
var healthy: bool = false
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

	_on_adapter_process(delta)


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
		adapter_error = ""

	state = State.STARTING

	adapter_started.emit(adapter_id)

	if not _validate_adapter():
		return _fail(adapter_error)

	if not _on_adapter_start():
		if adapter_error.is_empty():
			adapter_error = "Infrastructure Adapter không thể khởi động"

		return _fail(adapter_error)

	state = State.READY
	_set_health(true)

	adapter_ready.emit(adapter_id)

	_log("Adapter Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	if not _on_adapter_pause():
		return false

	state = State.PAUSED

	adapter_paused.emit(adapter_id)

	_log("Adapter Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	if not _on_adapter_resume():
		return false

	state = State.READY

	adapter_resumed.emit(adapter_id)

	_log("Adapter Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func check_health() -> bool:
	if state != State.READY:
		_set_health(false)
		return false

	var result: bool = _on_health_check()

	_set_health(result)

	return result


func has_capability(
	capability_id: StringName
) -> bool:
	return capabilities.has(capability_id)


func add_capability(
	capability_id: StringName
) -> bool:
	if capability_id.is_empty():
		return false

	if capabilities.has(capability_id):
		return false

	capabilities.append(capability_id)

	return true


func remove_capability(
	capability_id: StringName
) -> bool:
	return capabilities.erase(capability_id)


func set_processing_enabled(
	enabled: bool
) -> void:
	process_enabled = enabled
	set_process(enabled)


func get_adapter_id() -> StringName:
	return adapter_id


func get_adapter_type() -> AdapterType:
	return adapter_type


func get_state() -> State:
	return state


func get_error() -> String:
	return adapter_error


func get_capabilities() -> Array[StringName]:
	return capabilities.duplicate()


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


func is_healthy() -> bool:
	return healthy


func _validate_adapter() -> bool:
	adapter_error = ""

	if not is_inside_tree():
		adapter_error = "Infrastructure Adapter không nằm trong SceneTree"
		return false

	if adapter_id.is_empty():
		adapter_error = "Adapter ID không được để trống"
		return false

	var found_capabilities: Dictionary = {}

	for capability_id in capabilities:
		if capability_id.is_empty():
			adapter_error = "Capability ID không được để trống"
			return false

		if found_capabilities.has(capability_id):
			adapter_error = (
				"Capability ID bị trùng: "
				+ String(capability_id)
			)
			return false

		found_capabilities[capability_id] = true

	return true


func _on_adapter_start() -> bool:
	return true


func _on_adapter_pause() -> bool:
	return true


func _on_adapter_resume() -> bool:
	return true


func _on_adapter_process(
	_delta: float
) -> void:
	return


func _on_health_check() -> bool:
	return true


func _on_adapter_stop() -> bool:
	return true


func _set_health(
	value: bool
) -> void:
	if healthy == value:
		return

	healthy = value

	health_changed.emit(
		adapter_id,
		healthy
	)


func _fail(
	reason: String
) -> bool:
	state = State.FAILED
	adapter_error = reason

	_set_health(false)

	adapter_failed.emit(
		adapter_id,
		reason
	)

	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING

	adapter_stopping.emit(adapter_id)

	_log("Adapter Stopping")

	_on_adapter_stop()

	_set_health(false)

	state = State.STOPPED

	adapter_stopped.emit(adapter_id)

	_log("Adapter Stopped")


func _log(
	message: String
) -> void:
	if console_output:
		print(
			"[InfrastructureAdapter:",
			adapter_id,
			"] ",
			message
		)


func _log_error(
	message: String
) -> void:
	push_error(
		"[InfrastructureAdapter:%s] %s"
		% [
			adapter_id,
			message
		]
) 
