class_name Components
extends Node

signal components_started
signal components_ready
signal components_paused
signal components_resumed
signal components_stopping
signal components_stopped
signal components_failed(reason: String)

signal component_registered(component_id: StringName)
signal component_unregistered(component_id: StringName)
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

const EXPECTED_NODE_NAME: StringName = &"Components"

@export_group("Components")
@export var auto_start: bool = true
@export var auto_register_children: bool = true
@export var start_registered_components: bool = true
@export var stop_components_on_shutdown: bool = true
@export var console_output: bool = true
@export var free_on_remove: bool = false

@export_group("Validation")
@export var validate_root: bool = true

var state: State = State.IDLE
var components_error: String = ""

var _components: Dictionary = {}
var _component_order: Array[StringName] = []


func _enter_tree() -> void:
	state = State.STARTING


func _ready() -> void:
	if auto_register_children:
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

	if state == State.STOPPED:
		return false

	if state == State.FAILED:
		return false

	if validate_root and not _validate_root():
		return _fail(components_error)

	state = State.STARTING

	components_started.emit()

	var success: bool = true

	if start_registered_components:
		success = start_all()

	if not success:
		return _fail("Một hoặc nhiều Component không thể khởi động")

	state = State.READY

	components_ready.emit()

	_log("Components Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	state = State.PAUSED

	components_paused.emit()

	for component_id in _get_component_ids_copy():
		var component: Component = get_component(component_id)

		if component == null:
			continue

		if component.is_ready():
			component.pause()

	_log("Components Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	state = State.READY

	components_resumed.emit()

	for component_id in _get_component_ids_copy():
		var component: Component = get_component(component_id)

		if component == null:
			continue

		if component.is_paused():
			component.resume()

	_log("Components Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func add_component(component: Component) -> bool:
	if not is_instance_valid(component):
		_log_error("Không thể thêm Component không hợp lệ")
		return false

	if component.get_parent() != null and component.get_parent() != self:
		_log_error(
			"Component đang thuộc Node khác: "
			+ String(component.get_component_id())
		)
		return false

	if component.get_parent() == null:
		add_child(component)

	return register_component(component)


func register_component(component: Component) -> bool:
	if not is_instance_valid(component):
		_log_error("Không thể đăng ký Component không hợp lệ")
		return false

	if component.get_parent() != self:
		_log_error("Component phải là Child trực tiếp của Components")
		return false

	var component_id: StringName = component.get_component_id()

	if component_id.is_empty():
		_log_error("Component ID không được để trống")
		return false

	if _components.has(component_id):
		_log_error("Component ID đã tồn tại: " + String(component_id))
		return false

	_components[component_id] = component
	_component_order.append(component_id)

	component_registered.emit(component_id)

	_log("Component Registered: " + String(component_id))

	return true


func unregister_component(component_id: StringName) -> bool:
	if not _components.has(component_id):
		return false

	var component: Component = _components[component_id]

	if is_instance_valid(component):
		if component.is_ready() or component.is_paused():
			component.stop()

		if component.get_parent() == self:
			remove_child(component)

	_components.erase(component_id)
	_component_order.erase(component_id)

	component_unregistered.emit(component_id)

	_log("Component Unregistered: " + String(component_id))

	if free_on_remove and is_instance_valid(component):
		component.queue_free()

	return true


func get_component(component_id: StringName) -> Component:
	if not _components.has(component_id):
		return null

	var component: Component = _components[component_id]

	if not is_instance_valid(component):
		_components.erase(component_id)
		_component_order.erase(component_id)
		return null

	return component


func has_component(component_id: StringName) -> bool:
	return _components.has(component_id)


func get_component_count() -> int:
	return _components.size()


func get_component_ids() -> Array[StringName]:
	return _get_component_ids_copy()


func start_component(component_id: StringName) -> bool:
	var component: Component = get_component(component_id)

	if component == null:
		return false

	return component.start()


func pause_component(component_id: StringName) -> bool:
	var component: Component = get_component(component_id)

	if component == null:
		return false

	return component.pause()


func resume_component(component_id: StringName) -> bool:
	var component: Component = get_component(component_id)

	if component == null:
		return false

	return component.resume()


func stop_component(component_id: StringName) -> bool:
	var component: Component = get_component(component_id)

	if component == null:
		return false

	return component.stop()


func start_all() -> bool:
	var success: bool = true

	for component_id in _get_component_ids_copy():
		var component: Component = get_component(component_id)

		if component == null:
			continue

		if not component.start():
			success = false

	return success


func pause_all() -> bool:
	var success: bool = true

	for component_id in _get_component_ids_copy():
		var component: Component = get_component(component_id)

		if component == null:
			continue

		if component.is_ready() and not component.pause():
			success = false

	return success


func resume_all() -> bool:
	var success: bool = true

	for component_id in _get_component_ids_copy():
		var component: Component = get_component(component_id)

		if component == null:
			continue

		if component.is_paused() and not component.resume():
			success = false

	return success


func stop_all() -> bool:
	var success: bool = true

	var component_ids: Array[StringName] = _get_component_ids_copy()
	component_ids.reverse()

	for component_id in component_ids:
		var component: Component = get_component(component_id)

		if component == null:
			continue

		if not component.is_stopped() and not component.stop():
			success = false

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


func get_components_error() -> String:
	return components_error


func _register_existing_children() -> void:
	for child in get_children():
		if child is Component:
			register_component(child)


func _get_component_ids_copy() -> Array[StringName]:
	var result: Array[StringName] = []

	for component_id in _component_order:
		if _components.has(component_id):
			result.append(component_id)

	return result


func _validate_root() -> bool:
	components_error = ""

	if not is_inside_tree():
		components_error = "Components không nằm trong SceneTree"
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Components: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
			% [EXPECTED_NODE_NAME, name]
		)

	return true


func _fail(reason: String) -> bool:
	state = State.FAILED
	components_error = reason

	components_failed.emit(reason)

	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING

	components_stopping.emit()

	if stop_components_on_shutdown:
		stop_all()

	state = State.STOPPED

	components_stopped.emit()

	_log("Components Stopped")


func _log(message: String) -> void:
	if console_output:
		print("[Components] ", message)


func _log_error(message: String) -> void:
	push_error("[Components] " + message) 
