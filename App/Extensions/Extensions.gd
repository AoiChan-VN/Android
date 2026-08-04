class_name Extensions
extends Node

signal extensions_started
signal extensions_ready
signal extensions_paused
signal extensions_resumed
signal extensions_stopping
signal extensions_stopped
signal extensions_failed(reason: String)

signal ext_registered(ext_id: StringName)
signal ext_unregistered(ext_id: StringName)
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
	PAUSED,
	STOPPING,
	STOPPED,
	FAILED
}

const EXPECTED_NODE_NAME: StringName = &"Extensions"

@export_group("Extensions")
@export var auto_start: bool = true
@export var scan_children: bool = true
@export var start_registered: bool = true
@export var stop_on_exit: bool = true
@export var retry_on_change: bool = true
@export var strict_start: bool = false
@export var free_on_remove: bool = false
@export var console_output: bool = true

@export_group("Validation")
@export var validate_root: bool = true

var state: State = State.IDLE
var extensions_error: String = ""

var _exts: Dictionary = {}
var _order: Array[StringName] = []
var _started_order: Array[StringName] = []


func _enter_tree() -> void:
	state = State.STARTING


func _ready() -> void:
	if scan_children:
		_register_children()

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

	if state == State.FAILED or state == State.STOPPED:
		state = State.IDLE
		extensions_error = ""

	if validate_root and not _validate_root():
		return _fail(extensions_error)

	state = State.STARTING

	extensions_started.emit()

	var success: bool = true

	if start_registered:
		success = start_all()

	if strict_start and not success:
		return _fail(
			"Một hoặc nhiều Extension không thể khởi động"
		)

	state = State.READY

	extensions_ready.emit()

	_log("Extensions Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	var success: bool = pause_all()

	if strict_start and not success:
		return false

	state = State.PAUSED

	extensions_paused.emit()

	_log("Extensions Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	var success: bool = resume_all()

	if strict_start and not success:
		return false

	state = State.READY

	extensions_resumed.emit()

	_log("Extensions Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func add_ext(ext: AppExtension) -> bool:
	if not is_instance_valid(ext):
		_log_error("Extension không hợp lệ")
		return false

	if ext.get_parent() != null and ext.get_parent() != self:
		_log_error(
			"Extension đang thuộc Node khác: "
			+ String(ext.get_ext_id())
		)
		return false

	if ext.get_parent() == null:
		add_child(ext)

	return register_ext(ext)


func register_ext(ext: AppExtension) -> bool:
	if not is_instance_valid(ext):
		_log_error("Extension không hợp lệ")
		return false

	if ext.get_parent() != self:
		_log_error(
			"Extension phải là Child trực tiếp của Extensions"
		)
		return false

	var ext_id: StringName = ext.get_ext_id()

	if ext_id.is_empty():
		_log_error("Ext ID không được để trống")
		return false

	if _exts.has(ext_id):
		_log_error(
			"Ext ID đã tồn tại: "
			+ String(ext_id)
		)
		return false

	_exts[ext_id] = ext
	_order.append(ext_id)

	ext.bind_dep_check(_is_dep_ready)

	_connect_ext(ext)

	ext_registered.emit(ext_id)

	_log(
		"Extension Registered: "
		+ String(ext_id)
	)

	if state == State.READY and start_registered:
		var success: bool = ext.start()

		if success:
			_add_started(ext_id)

		if retry_on_change:
			retry_failed()

		if strict_start and not success:
			return false

	return true


func replace_ext(ext: AppExtension) -> bool:
	if not is_instance_valid(ext):
		return false

	var ext_id: StringName = ext.get_ext_id()

	if ext_id.is_empty():
		return false

	if _exts.has(ext_id):
		if not unregister_ext(ext_id):
			return false

	return add_ext(ext)


func unregister_ext(ext_id: StringName) -> bool:
	var ext: AppExtension = get_ext(ext_id)

	if ext == null:
		return false

	if not ext.is_stopped():
		ext.stop()

	_disconnect_ext(ext)
	ext.clear_dep_check()

	if ext.get_parent() == self:
		remove_child(ext)

	_exts.erase(ext_id)
	_order.erase(ext_id)
	_started_order.erase(ext_id)

	ext_unregistered.emit(ext_id)

	_block_dependents(ext_id)

	_log(
		"Extension Unregistered: "
		+ String(ext_id)
	)

	if free_on_remove and is_instance_valid(ext):
		ext.queue_free()

	return true


func get_ext(ext_id: StringName) -> AppExtension:
	if not _exts.has(ext_id):
		return null

	var ext: AppExtension = _exts[ext_id]

	if not is_instance_valid(ext):
		_exts.erase(ext_id)
		_order.erase(ext_id)
		_started_order.erase(ext_id)
		return null

	return ext


func has_ext(ext_id: StringName) -> bool:
	return get_ext(ext_id) != null


func get_ext_count() -> int:
	return _exts.size()


func get_ext_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for ext_id in _order:
		if _exts.has(ext_id):
			result.append(ext_id)

	return result


func get_ready_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for ext_id in get_ext_ids():
		var ext: AppExtension = get_ext(ext_id)

		if ext != null and ext.is_ready():
			result.append(ext_id)

	return result


func get_failed_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for ext_id in get_ext_ids():
		var ext: AppExtension = get_ext(ext_id)

		if ext != null and ext.is_failed():
			result.append(ext_id)

	return result


func get_ids_by_cap(cap_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []

	if cap_id.is_empty():
		return result

	for ext_id in get_ext_ids():
		var ext: AppExtension = get_ext(ext_id)

		if ext != null and ext.has_cap(cap_id):
			result.append(ext_id)

	return result


func get_dependents(ext_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []

	for target_id in get_ext_ids():
		var ext: AppExtension = get_ext(target_id)

		if ext != null and ext.has_dep(ext_id):
			result.append(target_id)

	return result


func start_ext(ext_id: StringName) -> bool:
	var ext: AppExtension = get_ext(ext_id)

	if ext == null:
		return false

	var success: bool = ext.start()

	if success:
		_add_started(ext_id)

		if retry_on_change:
			retry_failed()

	return success


func enable_ext(ext_id: StringName) -> bool:
	var ext: AppExtension = get_ext(ext_id)

	if ext == null:
		return false

	var success: bool = ext.enable()

	if success and retry_on_change:
		retry_failed()

	return success


func disable_ext(ext_id: StringName) -> bool:
	var ext: AppExtension = get_ext(ext_id)

	if ext == null:
		return false

	var success: bool = ext.disable()

	if success:
		_block_dependents(ext_id)

	return success


func pause_ext(ext_id: StringName) -> bool:
	var ext: AppExtension = get_ext(ext_id)

	if ext == null:
		return false

	return ext.pause()


func resume_ext(ext_id: StringName) -> bool:
	var ext: AppExtension = get_ext(ext_id)

	if ext == null:
		return false

	var success: bool = ext.resume()

	if success and retry_on_change:
		retry_failed()

	return success


func stop_ext(ext_id: StringName) -> bool:
	var ext: AppExtension = get_ext(ext_id)

	if ext == null:
		return false

	var success: bool = ext.stop()

	if success:
		_started_order.erase(ext_id)
		_block_dependents(ext_id)

	return success


func retry_ext(ext_id: StringName) -> bool:
	var ext: AppExtension = get_ext(ext_id)

	if ext == null:
		return false

	var success: bool = ext.retry()

	if success:
		_add_started(ext_id)

	return success


func start_all() -> bool:
	var pending: Array[StringName] = get_ext_ids()
	var success: bool = true
	var progress: bool = true

	while progress and not pending.is_empty():
		progress = false

		var next: Array[StringName] = []

		for ext_id in pending:
			var ext: AppExtension = get_ext(ext_id)

			if ext == null:
				success = false
				continue

			if ext.is_ready() or ext.is_disabled():
				_add_started(ext_id)
				progress = true
				continue

			if not ext.get_missing_deps().is_empty():
				next.append(ext_id)
				continue

			if ext.start():
				_add_started(ext_id)
				progress = true
			else:
				success = false

		pending = next

	if not pending.is_empty():
		success = false

		for ext_id in pending:
			var ext: AppExtension = get_ext(ext_id)

			if ext == null:
				continue

			var missing: Array[StringName] = (
				ext.get_missing_deps()
			)

			ext.block(
				"Dependency thiếu hoặc bị vòng lặp: "
				+ _join_ids(missing)
			)

	return success


func pause_all() -> bool:
	var success: bool = true
	var ids: Array[StringName] = []

	ids.assign(_started_order)
	ids.reverse()

	for ext_id in ids:
		var ext: AppExtension = get_ext(ext_id)

		if ext == null:
			continue

		if ext.is_ready() and not ext.pause():
			success = false

	return success


func resume_all() -> bool:
	var success: bool = true

	for ext_id in _started_order:
		var ext: AppExtension = get_ext(ext_id)

		if ext == null:
			continue

		if ext.is_paused() and not ext.resume():
			success = false

	return success


func retry_failed() -> bool:
	var success: bool = true
	var progress: bool = true

	while progress:
		progress = false

		for ext_id in get_failed_ids():
			var ext: AppExtension = get_ext(ext_id)

			if ext == null:
				continue

			if not ext.get_missing_deps().is_empty():
				continue

			if ext.retry():
				_add_started(ext_id)
				progress = true
			else:
				success = false

	return success


func stop_all() -> bool:
	var success: bool = true
	var stopped: Dictionary = {}
	var ids: Array[StringName] = []

	ids.assign(_started_order)
	ids.reverse()

	for ext_id in ids:
		var ext: AppExtension = get_ext(ext_id)

		if ext == null:
			continue

		stopped[ext_id] = true

		if not ext.is_stopped() and not ext.stop():
			success = false

	var all_ids: Array[StringName] = get_ext_ids()

	all_ids.reverse()

	for ext_id in all_ids:
		if stopped.has(ext_id):
			continue

		var ext: AppExtension = get_ext(ext_id)

		if ext == null:
			continue

		if not ext.is_stopped() and not ext.stop():
			success = false

	_started_order.clear()

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


func get_error() -> String:
	return extensions_error


func _register_children() -> void:
	for child in get_children():
		if child is AppExtension:
			register_ext(child)


func _connect_ext(ext: AppExtension) -> void:
	if not ext.ext_started.is_connected(_on_ext_started):
		ext.ext_started.connect(_on_ext_started)

	if not ext.ext_ready.is_connected(_on_ext_ready):
		ext.ext_ready.connect(_on_ext_ready)

	if not ext.ext_enabled.is_connected(_on_ext_enabled):
		ext.ext_enabled.connect(_on_ext_enabled)

	if not ext.ext_disabled.is_connected(_on_ext_disabled):
		ext.ext_disabled.connect(_on_ext_disabled)

	if not ext.ext_paused.is_connected(_on_ext_paused):
		ext.ext_paused.connect(_on_ext_paused)

	if not ext.ext_resumed.is_connected(_on_ext_resumed):
		ext.ext_resumed.connect(_on_ext_resumed)

	if not ext.ext_stopping.is_connected(_on_ext_stopping):
		ext.ext_stopping.connect(_on_ext_stopping)

	if not ext.ext_stopped.is_connected(_on_ext_stopped):
		ext.ext_stopped.connect(_on_ext_stopped)

	if not ext.ext_failed.is_connected(_on_ext_failed):
		ext.ext_failed.connect(_on_ext_failed)


func _disconnect_ext(ext: AppExtension) -> void:
	if not is_instance_valid(ext):
		return

	if ext.ext_started.is_connected(_on_ext_started):
		ext.ext_started.disconnect(_on_ext_started)

	if ext.ext_ready.is_connected(_on_ext_ready):
		ext.ext_ready.disconnect(_on_ext_ready)

	if ext.ext_enabled.is_connected(_on_ext_enabled):
		ext.ext_enabled.disconnect(_on_ext_enabled)

	if ext.ext_disabled.is_connected(_on_ext_disabled):
		ext.ext_disabled.disconnect(_on_ext_disabled)

	if ext.ext_paused.is_connected(_on_ext_paused):
		ext.ext_paused.disconnect(_on_ext_paused)

	if ext.ext_resumed.is_connected(_on_ext_resumed):
		ext.ext_resumed.disconnect(_on_ext_resumed)

	if ext.ext_stopping.is_connected(_on_ext_stopping):
		ext.ext_stopping.disconnect(_on_ext_stopping)

	if ext.ext_stopped.is_connected(_on_ext_stopped):
		ext.ext_stopped.disconnect(_on_ext_stopped)

	if ext.ext_failed.is_connected(_on_ext_failed):
		ext.ext_failed.disconnect(_on_ext_failed)


func _on_ext_started(ext_id: StringName) -> void:
	ext_started.emit(ext_id)


func _on_ext_ready(ext_id: StringName) -> void:
	_add_started(ext_id)

	ext_ready.emit(ext_id)

	if retry_on_change:
		retry_failed()


func _on_ext_enabled(ext_id: StringName) -> void:
	ext_enabled.emit(ext_id)

	if retry_on_change:
		retry_failed()


func _on_ext_disabled(ext_id: StringName) -> void:
	ext_disabled.emit(ext_id)

	_block_dependents(ext_id)


func _on_ext_paused(ext_id: StringName) -> void:
	ext_paused.emit(ext_id)


func _on_ext_resumed(ext_id: StringName) -> void:
	ext_resumed.emit(ext_id)

	if retry_on_change:
		retry_failed()


func _on_ext_stopping(ext_id: StringName) -> void:
	ext_stopping.emit(ext_id)


func _on_ext_stopped(ext_id: StringName) -> void:
	_started_order.erase(ext_id)

	ext_stopped.emit(ext_id)


func _on_ext_failed(
	ext_id: StringName,
	reason: String
) -> void:
	_started_order.erase(ext_id)

	ext_failed.emit(
		ext_id,
		reason
	)

	_log_error(
		"Extension Failed ["
		+ String(ext_id)
		+ "]: "
		+ reason
	)


func _is_dep_ready(dep_id: StringName) -> bool:
	var ext: AppExtension = get_ext(dep_id)

	return ext != null and ext.is_ready()


func _block_dependents(ext_id: StringName) -> void:
	for dependent_id in get_dependents(ext_id):
		var ext: AppExtension = get_ext(dependent_id)

		if ext == null:
			continue

		if (
			ext.is_ready()
			or ext.is_paused()
			or ext.is_disabled()
		):
			ext.block(
				"Dependency đã bị vô hiệu hóa: "
				+ String(ext_id)
			)


func _add_started(ext_id: StringName) -> void:
	if not _started_order.has(ext_id):
		_started_order.append(ext_id)


func _join_ids(ids: Array[StringName]) -> String:
	var values: PackedStringArray = []

	for id in ids:
		values.append(String(id))

	return ", ".join(values)


func _validate_root() -> bool:
	extensions_error = ""

	if not is_inside_tree():
		extensions_error = (
			"Extensions không nằm trong SceneTree"
		)
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Extensions: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
			% [
				EXPECTED_NODE_NAME,
				name
			]
		)

	return true


func _fail(reason: String) -> bool:
	state = State.FAILED
	extensions_error = reason

	extensions_failed.emit(reason)

	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING

	extensions_stopping.emit()

	if stop_on_exit:
		stop_all()

	state = State.STOPPED

	extensions_stopped.emit()

	_log("Extensions Stopped")


func _log(message: String) -> void:
	if console_output:
		print(
			"[Extensions] ",
			message
		)


func _log_error(message: String) -> void:
	push_error(
		"[Extensions] "
		+ message
	) 
