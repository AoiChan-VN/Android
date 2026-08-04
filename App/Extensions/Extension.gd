class_name AppExtension
extends Node

signal ext_started(ext_id: StringName)
signal ext_ready(ext_id: StringName)
signal ext_enabled(ext_id: StringName)
signal ext_disabled(ext_id: StringName)
signal ext_paused(ext_id: StringName)
signal ext_resumed(ext_id: StringName)
signal ext_stopping(ext_id: StringName)
signal ext_stopped(ext_id: StringName)
signal ext_failed(ext_id: StringName, reason: String)

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

@export_group("Extension")
@export var ext_id: StringName = &""
@export var version: String = "1.0.0"
@export var deps: Array[StringName] = []
@export var caps: Array[StringName] = []
@export var auto_start: bool = false
@export var enabled_on_start: bool = true
@export var console_output: bool = true

@export_group("Process")
@export var process_enabled: bool = false
@export var priority: int = 0

var state: State = State.IDLE
var ext_error: String = ""
var elapsed_time: float = 0.0
var frame_count: int = 0

var _dep_check: Callable = Callable()


func _enter_tree() -> void:
	state = State.STARTING


func _ready() -> void:
	process_priority = priority
	set_process(process_enabled)

	if auto_start:
		start()


func _process(delta: float) -> void:
	if state != State.READY:
		return

	elapsed_time += delta
	frame_count += 1

	_on_ext_process(delta)


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
		ext_error = ""

	state = State.STARTING

	ext_started.emit(ext_id)

	if not _validate_ext():
		return _fail(ext_error)

	var missing: Array[StringName] = get_missing_deps()

	if not missing.is_empty():
		return _fail(
			"Dependency chưa sẵn sàng: "
			+ _join_ids(missing)
		)

	if not _on_ext_start():
		if ext_error.is_empty():
			ext_error = "Extension không thể khởi động"

		return _fail(ext_error)

	if enabled_on_start:
		state = State.READY
		ext_ready.emit(ext_id)
		ext_enabled.emit(ext_id)
		_log("Extension Ready")
	else:
		state = State.DISABLED
		ext_ready.emit(ext_id)
		ext_disabled.emit(ext_id)
		_log("Extension Disabled")

	return true


func enable() -> bool:
	if state == State.READY:
		return true

	if state != State.DISABLED:
		return false

	var missing: Array[StringName] = get_missing_deps()

	if not missing.is_empty():
		_set_error(
			"Dependency chưa sẵn sàng: "
			+ _join_ids(missing)
		)
		return false

	if not _on_ext_enable():
		return false

	state = State.READY

	ext_enabled.emit(ext_id)

	_log("Extension Enabled")

	return true


func disable() -> bool:
	if state == State.DISABLED:
		return true

	if state != State.READY and state != State.PAUSED:
		return false

	if not _on_ext_disable():
		return false

	state = State.DISABLED

	ext_disabled.emit(ext_id)

	_log("Extension Disabled")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	if not _on_ext_pause():
		return false

	state = State.PAUSED

	ext_paused.emit(ext_id)

	_log("Extension Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	var missing: Array[StringName] = get_missing_deps()

	if not missing.is_empty():
		_set_error(
			"Dependency chưa sẵn sàng: "
			+ _join_ids(missing)
		)
		return false

	if not _on_ext_resume():
		return false

	state = State.READY

	ext_resumed.emit(ext_id)

	_log("Extension Resumed")

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
	ext_error = ""

	return start()


func block(reason: String) -> bool:
	if reason.is_empty():
		return false

	if (
		state == State.READY
		or state == State.PAUSED
		or state == State.DISABLED
	):
		_on_ext_stop()

	return _fail(reason)


func bind_dep_check(check: Callable) -> bool:
	if not check.is_valid():
		return false

	_dep_check = check

	return true


func clear_dep_check() -> void:
	_dep_check = Callable()


func get_missing_deps() -> Array[StringName]:
	var result: Array[StringName] = []

	if deps.is_empty():
		return result

	if not _dep_check.is_valid():
		result.assign(deps)
		return result

	for dep_id in deps:
		var ready: bool = bool(
			_dep_check.call(dep_id)
		)

		if not ready:
			result.append(dep_id)

	return result


func has_dep(dep_id: StringName) -> bool:
	return deps.has(dep_id)


func has_cap(cap_id: StringName) -> bool:
	return caps.has(cap_id)


func add_cap(cap_id: StringName) -> bool:
	if cap_id.is_empty():
		return false

	if caps.has(cap_id):
		return false

	caps.append(cap_id)

	return true


func remove_cap(cap_id: StringName) -> bool:
	return caps.erase(cap_id)


func set_processing(enabled: bool) -> void:
	process_enabled = enabled
	set_process(enabled)


func get_ext_id() -> StringName:
	return ext_id


func get_version() -> String:
	return version


func get_deps() -> Array[StringName]:
	var result: Array[StringName] = []

	result.assign(deps)

	return result


func get_caps() -> Array[StringName]:
	var result: Array[StringName] = []

	result.assign(caps)

	return result


func get_state() -> State:
	return state


func get_error() -> String:
	return ext_error


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


func is_active() -> bool:
	return (
		state == State.READY
		or state == State.PAUSED
	)


func _validate_ext() -> bool:
	ext_error = ""

	if not is_inside_tree():
		ext_error = "Extension không nằm trong SceneTree"
		return false

	if ext_id.is_empty():
		ext_error = "Ext ID không được để trống"
		return false

	if version.is_empty():
		ext_error = "Version không được để trống"
		return false

	var dep_map: Dictionary = {}

	for dep_id in deps:
		if dep_id.is_empty():
			ext_error = "Dependency ID không được để trống"
			return false

		if dep_id == ext_id:
			ext_error = "Extension không thể phụ thuộc chính nó"
			return false

		if dep_map.has(dep_id):
			ext_error = (
				"Dependency ID bị trùng: "
				+ String(dep_id)
			)
			return false

		dep_map[dep_id] = true

	var cap_map: Dictionary = {}

	for cap_id in caps:
		if cap_id.is_empty():
			ext_error = "Capability ID không được để trống"
			return false

		if cap_map.has(cap_id):
			ext_error = (
				"Capability ID bị trùng: "
				+ String(cap_id)
			)
			return false

		cap_map[cap_id] = true

	return true


func _on_ext_start() -> bool:
	return true


func _on_ext_enable() -> bool:
	return true


func _on_ext_disable() -> bool:
	return true


func _on_ext_pause() -> bool:
	return true


func _on_ext_resume() -> bool:
	return true


func _on_ext_process(_delta: float) -> void:
	pass


func _on_ext_stop() -> void:
	pass


func _set_error(message: String) -> void:
	ext_error = message

	_log_error(message)


func _fail(reason: String) -> bool:
	state = State.FAILED
	ext_error = reason

	ext_failed.emit(
		ext_id,
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

	ext_stopping.emit(ext_id)

	_on_ext_stop()

	state = State.STOPPED

	ext_stopped.emit(ext_id)

	_log("Extension Stopped")


func _join_ids(ids: Array[StringName]) -> String:
	var values: PackedStringArray = []

	for id in ids:
		values.append(String(id))

	return ", ".join(values)


func _log(message: String) -> void:
	if console_output:
		print(
			"[Extension:",
			ext_id,
			"] ",
			message
		)


func _log_error(message: String) -> void:
	push_error(
		"[Extension:%s] %s"
		% [
			ext_id,
			message
		]
	) 
