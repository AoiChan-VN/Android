class_name Feature
extends Node

signal feature_started(feature_id: StringName)
signal feature_ready(feature_id: StringName)
signal feature_enabled(feature_id: StringName)
signal feature_disabled(feature_id: StringName)
signal feature_paused(feature_id: StringName)
signal feature_resumed(feature_id: StringName)
signal feature_stopping(feature_id: StringName)
signal feature_stopped(feature_id: StringName)
signal feature_failed(feature_id: StringName, reason: String)

enum State {
	IDLE,
	STARTING,
	READY,
	DISABLED,
	PAUSED,
	STOPPING,
	STOPPED,
	FAILED
}

@export_group("Feature")
@export var feature_id: StringName = &""
@export var auto_start: bool = false
@export var enabled_on_start: bool = true
@export var required_ids: Array[StringName] = []
@export var console_output: bool = true

@export_group("Process")
@export var process_enabled: bool = true
@export var process_priority: int = 0

var state: State = State.IDLE
var feature_error: String = ""
var elapsed_time: float = 0.0
var frame_count: int = 0

var _dependency_check: Callable = Callable()


func _enter_tree() -> void:
	state = State.STARTING


func _ready() -> void:
	process_priority = process_priority
	set_process(process_enabled)

	if auto_start:
		start()


func _process(delta: float) -> void:
	if state != State.READY:
		return

	elapsed_time += delta
	frame_count += 1

	_on_feature_process(delta)


func _exit_tree() -> void:
	_shutdown()


func start() -> bool:
	if state == State.READY or state == State.DISABLED:
		return true

	if state == State.PAUSED:
		return resume()

	if state == State.STOPPING:
		return false

	if state == State.FAILED or state == State.STOPPED:
		state = State.IDLE
		feature_error = ""

	state = State.STARTING
	feature_started.emit(feature_id)

	if not _validate_feature():
		return _fail(feature_error)

	var missing_ids: Array[StringName] = get_missing_dependencies()

	if not missing_ids.is_empty():
		feature_error = "Thiếu Dependency: " + ", ".join(missing_ids)
		return _fail(feature_error)

	if not _on_feature_start():
		if feature_error.is_empty():
			feature_error = "Feature không thể khởi động"

		return _fail(feature_error)

	feature_ready.emit(feature_id)

	if enabled_on_start:
		state = State.READY
		feature_enabled.emit(feature_id)
		_log("Feature Ready")
	else:
		state = State.DISABLED
		feature_disabled.emit(feature_id)
		_log("Feature Disabled")

	return true


func enable() -> bool:
	if state == State.READY:
		return true

	if state != State.DISABLED:
		return false

	var missing_ids: Array[StringName] = get_missing_dependencies()

	if not missing_ids.is_empty():
		feature_error = "Thiếu Dependency: " + ", ".join(missing_ids)
		_log_error(feature_error)
		return false

	if not _on_feature_enable():
		return false

	state = State.READY
	feature_enabled.emit(feature_id)

	_log("Feature Enabled")

	return true


func disable() -> bool:
	if state == State.DISABLED:
		return true

	if state != State.READY and state != State.PAUSED:
		return false

	if not _on_feature_disable():
		return false

	state = State.DISABLED
	feature_disabled.emit(feature_id)

	_log("Feature Disabled")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	if not _on_feature_pause():
		return false

	state = State.PAUSED
	feature_paused.emit(feature_id)

	_log("Feature Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	var missing_ids: Array[StringName] = get_missing_dependencies()

	if not missing_ids.is_empty():
		feature_error = "Thiếu Dependency: " + ", ".join(missing_ids)
		_log_error(feature_error)
		return false

	if not _on_feature_resume():
		return false

	state = State.READY
	feature_resumed.emit(feature_id)

	_log("Feature Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func retry() -> bool:
	if state != State.FAILED and state != State.STOPPED:
		return false

	state = State.IDLE
	feature_error = ""

	return start()


func set_dependency_check(check: Callable) -> bool:
	if not check.is_valid():
		return false

	_dependency_check = check

	return true


func clear_dependency_check() -> void:
	_dependency_check = Callable()


func get_missing_dependencies() -> Array[StringName]:
	var missing_ids: Array[StringName] = []

	if required_ids.is_empty():
		return missing_ids

	if not _dependency_check.is_valid():
		missing_ids.assign(required_ids)
		return missing_ids

	for required_id in required_ids:
		var dependency_ready: bool = bool(
			_dependency_check.call(required_id)
		)

		if not dependency_ready:
			missing_ids.append(required_id)

	return missing_ids


func set_processing_enabled(enabled: bool) -> void:
	process_enabled = enabled
	set_process(enabled)


func get_feature_id() -> StringName:
	return feature_id


func get_state() -> State:
	return state


func get_feature_error() -> String:
	return feature_error


func get_elapsed_time() -> float:
	return elapsed_time


func get_frame_count() -> int:
	return frame_count


func is_ready() -> bool:
	return state == State.READY


func is_disabled() -> bool:
	return state == State.DISABLED


func is_paused() -> bool:
	return state == State.PAUSED


func is_stopped() -> bool:
	return state == State.STOPPED


func is_failed() -> bool:
	return state == State.FAILED


func _validate_feature() -> bool:
	feature_error = ""

	if not is_inside_tree():
		feature_error = "Feature không nằm trong SceneTree"
		return false

	if feature_id.is_empty():
		feature_error = "Feature ID không được để trống"
		return false

	var found_ids: Dictionary = {}

	for required_id in required_ids:
		if required_id.is_empty():
			feature_error = "Dependency ID không được để trống"
			return false

		if required_id == feature_id:
			feature_error = "Feature không thể phụ thuộc chính nó"
			return false

		if found_ids.has(required_id):
			feature_error = "Dependency ID bị trùng: " + String(required_id)
			return false

		found_ids[required_id] = true

	return true


func _on_feature_start() -> bool:
	return true


func _on_feature_enable() -> bool:
	return true


func _on_feature_disable() -> bool:
	return true


func _on_feature_pause() -> bool:
	return true


func _on_feature_resume() -> bool:
	return true


func _on_feature_process(_delta: float) -> void:
	pass


func _on_feature_stop() -> bool:
	return true


func _fail(reason: String) -> bool:
	state = State.FAILED
	feature_error = reason

	feature_failed.emit(feature_id, reason)

	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING
	feature_stopping.emit(feature_id)

	_log("Feature Stopping")

	_on_feature_stop()

	state = State.STOPPED
	feature_stopped.emit(feature_id)

	_log("Feature Stopped")


func _log(message: String) -> void:
	if console_output:
		print("[Feature:", feature_id, "] ", message)


func _log_error(message: String) -> void:
	push_error("[Feature:%s] %s" % [feature_id, message]) 
