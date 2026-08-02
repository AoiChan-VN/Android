class_name Features
extends Node

signal features_started
signal features_ready
signal features_paused
signal features_resumed
signal features_stopping
signal features_stopped
signal features_failed(reason: String)

signal feature_registered(feature_id: StringName)
signal feature_unregistered(feature_id: StringName)
signal feature_started(feature_id: StringName)
signal feature_ready(feature_id: StringName)
signal feature_enabled(feature_id: StringName)
signal feature_disabled(feature_id: StringName)
signal feature_paused(feature_id: StringName)
signal feature_resumed(feature_id: StringName)
signal feature_stopping(feature_id: StringName)
signal feature_stopped(feature_id: StringName)
signal feature_failed(feature_id: StringName, reason: String)

signal dependency_changed(dependency_id: StringName, ready: bool)
signal dependency_removed(dependency_id: StringName)

enum State {
	IDLE,
	STARTING,
	READY,
	PAUSED,
	STOPPING,
	STOPPED,
	FAILED
}

const EXPECTED_NODE_NAME: StringName = &"Features"

@export_group("Features")
@export var auto_start: bool = true
@export var scan_children: bool = true
@export var start_features: bool = true
@export var stop_on_exit: bool = true
@export var retry_on_dependency: bool = true
@export var strict_start: bool = false
@export var console_output: bool = true
@export var free_on_remove: bool = false

@export_group("Validation")
@export var validate_root: bool = true

var state: State = State.IDLE
var features_error: String = ""

var _features: Dictionary = {}
var _feature_order: Array[StringName] = []
var _dependencies: Dictionary = {}


func _enter_tree() -> void:
	state = State.STARTING


func _ready() -> void:
	if scan_children:
		_register_existing_children()

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
		features_error = ""

	if validate_root and not _validate_root():
		return _fail(features_error)

	state = State.STARTING
	features_started.emit()

	var success: bool = true

	if start_features:
		success = start_all()

	if strict_start and not success:
		return _fail("Một hoặc nhiều Feature không thể khởi động")

	state = State.READY
	features_ready.emit()

	_log("Features Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	var success: bool = pause_all()

	if strict_start and not success:
		return false

	state = State.PAUSED
	features_paused.emit()

	_log("Features Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	var success: bool = resume_all()

	if strict_start and not success:
		return false

	state = State.READY
	features_resumed.emit()

	_log("Features Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func add_feature(feature: Feature) -> bool:
	if not is_instance_valid(feature):
		_log_error("Không thể thêm Feature không hợp lệ")
		return false

	if feature.get_parent() != null and feature.get_parent() != self:
		_log_error(
			"Feature đang thuộc Node khác: "
			+ String(feature.get_feature_id())
		)
		return false

	if feature.get_parent() == null:
		add_child(feature)

	return register_feature(feature)


func register_feature(feature: Feature) -> bool:
	if not is_instance_valid(feature):
		_log_error("Không thể đăng ký Feature không hợp lệ")
		return false

	if feature.get_parent() != self:
		_log_error("Feature phải là Child trực tiếp của Features")
		return false

	var feature_id: StringName = feature.get_feature_id()

	if feature_id.is_empty():
		_log_error("Feature ID không được để trống")
		return false

	if _features.has(feature_id):
		_log_error("Feature ID đã tồn tại: " + String(feature_id))
		return false

	_features[feature_id] = feature
	_feature_order.append(feature_id)

	feature.set_dependency_check(_is_dependency_ready)

	_connect_feature(feature)

	feature_registered.emit(feature_id)

	_log("Feature Registered: " + String(feature_id))

	if state == State.READY and start_features:
		feature.start()

	return true


func unregister_feature(feature_id: StringName) -> bool:
	if not _features.has(feature_id):
		return false

	var feature: Feature = _features[feature_id]

	if is_instance_valid(feature):
		if not feature.is_stopped():
			feature.stop()

		_disconnect_feature(feature)
		feature.clear_dependency_check()

		if feature.get_parent() == self:
			remove_child(feature)

	_features.erase(feature_id)
	_feature_order.erase(feature_id)

	feature_unregistered.emit(feature_id)

	_log("Feature Unregistered: " + String(feature_id))

	if free_on_remove and is_instance_valid(feature):
		feature.queue_free()

	return true


func get_feature(feature_id: StringName) -> Feature:
	if not _features.has(feature_id):
		return null

	var feature: Feature = _features[feature_id]

	if not is_instance_valid(feature):
		_features.erase(feature_id)
		_feature_order.erase(feature_id)
		return null

	return feature


func has_feature(feature_id: StringName) -> bool:
	return _features.has(feature_id)


func get_feature_count() -> int:
	return _features.size()


func get_feature_ids() -> Array[StringName]:
	return _get_feature_ids_copy()


func start_feature(feature_id: StringName) -> bool:
	var feature: Feature = get_feature(feature_id)

	if feature == null:
		return false

	return feature.start()


func enable_feature(feature_id: StringName) -> bool:
	var feature: Feature = get_feature(feature_id)

	if feature == null:
		return false

	return feature.enable()


func disable_feature(feature_id: StringName) -> bool:
	var feature: Feature = get_feature(feature_id)

	if feature == null:
		return false

	return feature.disable()


func pause_feature(feature_id: StringName) -> bool:
	var feature: Feature = get_feature(feature_id)

	if feature == null:
		return false

	return feature.pause()


func resume_feature(feature_id: StringName) -> bool:
	var feature: Feature = get_feature(feature_id)

	if feature == null:
		return false

	return feature.resume()


func stop_feature(feature_id: StringName) -> bool:
	var feature: Feature = get_feature(feature_id)

	if feature == null:
		return false

	return feature.stop()


func retry_feature(feature_id: StringName) -> bool:
	var feature: Feature = get_feature(feature_id)

	if feature == null:
		return false

	return feature.retry()


func start_all() -> bool:
	var success: bool = true

	for feature_id in _get_feature_ids_copy():
		var feature: Feature = get_feature(feature_id)

		if feature == null:
			continue

		if not feature.start():
			success = false

	return success


func pause_all() -> bool:
	var success: bool = true

	for feature_id in _get_feature_ids_copy():
		var feature: Feature = get_feature(feature_id)

		if feature == null:
			continue

		if feature.is_ready() and not feature.pause():
			success = false

	return success


func resume_all() -> bool:
	var success: bool = true

	for feature_id in _get_feature_ids_copy():
		var feature: Feature = get_feature(feature_id)

		if feature == null:
			continue

		if feature.is_paused() and not feature.resume():
			success = false

	return success


func stop_all() -> bool:
	var success: bool = true

	var feature_ids: Array[StringName] = _get_feature_ids_copy()
	feature_ids.reverse()

	for feature_id in feature_ids:
		var feature: Feature = get_feature(feature_id)

		if feature == null:
			continue

		if not feature.is_stopped() and not feature.stop():
			success = false

	return success


func retry_failed() -> bool:
	var success: bool = true

	for feature_id in _get_feature_ids_copy():
		var feature: Feature = get_feature(feature_id)

		if feature == null:
			continue

		if feature.is_failed() and not feature.retry():
			success = false

	return success


func set_dependency(
	dependency_id: StringName,
	ready: bool = true
) -> bool:
	if dependency_id.is_empty():
		_log_error("Dependency ID không được để trống")
		return false

	var changed: bool = (
		not _dependencies.has(dependency_id)
		or bool(_dependencies[dependency_id]) != ready
	)

	_dependencies[dependency_id] = ready

	if changed:
		dependency_changed.emit(dependency_id, ready)

	if ready and retry_on_dependency:
		retry_failed()

	return true


func remove_dependency(dependency_id: StringName) -> bool:
	if not _dependencies.has(dependency_id):
		return false

	_dependencies.erase(dependency_id)

	dependency_changed.emit(dependency_id, false)
	dependency_removed.emit(dependency_id)

	return true


func has_dependency(dependency_id: StringName) -> bool:
	return _dependencies.has(dependency_id)


func is_dependency_ready(dependency_id: StringName) -> bool:
	return _is_dependency_ready(dependency_id)


func get_dependency_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for dependency_id in _dependencies.keys():
		result.append(dependency_id)

	return result


func get_missing_dependencies(
	feature_id: StringName
) -> Array[StringName]:
	var feature: Feature = get_feature(feature_id)

	if feature == null:
		return []

	return feature.get_missing_dependencies()


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


func get_features_error() -> String:
	return features_error


func _register_existing_children() -> void:
	for child in get_children():
		if child is Feature:
			register_feature(child)


func _connect_feature(feature: Feature) -> void:
	if not feature.feature_started.is_connected(_on_feature_started):
		feature.feature_started.connect(_on_feature_started)

	if not feature.feature_ready.is_connected(_on_feature_ready):
		feature.feature_ready.connect(_on_feature_ready)

	if not feature.feature_enabled.is_connected(_on_feature_enabled):
		feature.feature_enabled.connect(_on_feature_enabled)

	if not feature.feature_disabled.is_connected(_on_feature_disabled):
		feature.feature_disabled.connect(_on_feature_disabled)

	if not feature.feature_paused.is_connected(_on_feature_paused):
		feature.feature_paused.connect(_on_feature_paused)

	if not feature.feature_resumed.is_connected(_on_feature_resumed):
		feature.feature_resumed.connect(_on_feature_resumed)

	if not feature.feature_stopping.is_connected(_on_feature_stopping):
		feature.feature_stopping.connect(_on_feature_stopping)

	if not feature.feature_stopped.is_connected(_on_feature_stopped):
		feature.feature_stopped.connect(_on_feature_stopped)

	if not feature.feature_failed.is_connected(_on_feature_failed):
		feature.feature_failed.connect(_on_feature_failed)


func _disconnect_feature(feature: Feature) -> void:
	if not is_instance_valid(feature):
		return

	if feature.feature_started.is_connected(_on_feature_started):
		feature.feature_started.disconnect(_on_feature_started)

	if feature.feature_ready.is_connected(_on_feature_ready):
		feature.feature_ready.disconnect(_on_feature_ready)

	if feature.feature_enabled.is_connected(_on_feature_enabled):
		feature.feature_enabled.disconnect(_on_feature_enabled)

	if feature.feature_disabled.is_connected(_on_feature_disabled):
		feature.feature_disabled.disconnect(_on_feature_disabled)

	if feature.feature_paused.is_connected(_on_feature_paused):
		feature.feature_paused.disconnect(_on_feature_paused)

	if feature.feature_resumed.is_connected(_on_feature_resumed):
		feature.feature_resumed.disconnect(_on_feature_resumed)

	if feature.feature_stopping.is_connected(_on_feature_stopping):
		feature.feature_stopping.disconnect(_on_feature_stopping)

	if feature.feature_stopped.is_connected(_on_feature_stopped):
		feature.feature_stopped.disconnect(_on_feature_stopped)

	if feature.feature_failed.is_connected(_on_feature_failed):
		feature.feature_failed.disconnect(_on_feature_failed)


func _on_feature_started(feature_id: StringName) -> void:
	feature_started.emit(feature_id)


func _on_feature_ready(feature_id: StringName) -> void:
	feature_ready.emit(feature_id)


func _on_feature_enabled(feature_id: StringName) -> void:
	feature_enabled.emit(feature_id)


func _on_feature_disabled(feature_id: StringName) -> void:
	feature_disabled.emit(feature_id)


func _on_feature_paused(feature_id: StringName) -> void:
	feature_paused.emit(feature_id)


func _on_feature_resumed(feature_id: StringName) -> void:
	feature_resumed.emit(feature_id)


func _on_feature_stopping(feature_id: StringName) -> void:
	feature_stopping.emit(feature_id)


func _on_feature_stopped(feature_id: StringName) -> void:
	feature_stopped.emit(feature_id)


func _on_feature_failed(
	feature_id: StringName,
	reason: String
) -> void:
	feature_failed.emit(feature_id, reason)

	_log_error(
		"Feature Failed ["
		+ String(feature_id)
		+ "]: "
		+ reason
	)


func _is_dependency_ready(dependency_id: StringName) -> bool:
	if not _dependencies.has(dependency_id):
		return false

	return bool(_dependencies[dependency_id])


func _get_feature_ids_copy() -> Array[StringName]:
	var result: Array[StringName] = []

	for feature_id in _feature_order:
		if _features.has(feature_id):
			result.append(feature_id)

	return result


func _validate_root() -> bool:
	features_error = ""

	if not is_inside_tree():
		features_error = "Features không nằm trong SceneTree"
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Features: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
			% [EXPECTED_NODE_NAME, name]
		)

	return true


func _fail(reason: String) -> bool:
	state = State.FAILED
	features_error = reason

	features_failed.emit(reason)

	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING
	features_stopping.emit()

	if stop_on_exit:
		stop_all()

	state = State.STOPPED
	features_stopped.emit()

	_log("Features Stopped")


func _log(message: String) -> void:
	if console_output:
		print("[Features] ", message)


func _log_error(message: String) -> void:
	push_error("[Features] " + message) 
