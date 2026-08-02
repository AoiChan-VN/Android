class_name Services
extends Node

signal services_started
signal services_ready
signal services_paused
signal services_resumed
signal services_stopping
signal services_stopped
signal services_failed(reason: String)

signal service_registered(service_id: StringName)
signal service_unregistered(service_id: StringName)
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

const EXPECTED_NODE_NAME: StringName = &"Services"

@export_group("Services")
@export var auto_start: bool = true
@export var auto_register_children: bool = true
@export var start_registered_services: bool = true
@export var stop_services_on_shutdown: bool = true
@export var console_output: bool = true
@export var free_on_remove: bool = false

@export_group("Validation")
@export var validate_root: bool = true

var state: State = State.IDLE
var services_error: String = ""

var _services: Dictionary = {}


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
		return _fail(services_error)

	state = State.STARTING
	services_started.emit()

	var success: bool = true

	if start_registered_services:
		success = start_all()

	if not success:
		return _fail("Một hoặc nhiều Service không thể khởi động")

	state = State.READY
	services_ready.emit()

	_log("Services Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	state = State.PAUSED
	services_paused.emit()

	for service_id in _get_service_ids_copy():
		var service: Service = get_service(service_id)

		if service == null:
			continue

		if service.is_ready():
			service.pause()

	_log("Services Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	state = State.READY
	services_resumed.emit()

	for service_id in _get_service_ids_copy():
		var service: Service = get_service(service_id)

		if service == null:
			continue

		if service.is_paused():
			service.resume()

	_log("Services Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func add_service(service: Service) -> bool:
	if not is_instance_valid(service):
		_log_error("Không thể thêm Service không hợp lệ")
		return false

	if service.get_parent() != null and service.get_parent() != self:
		_log_error(
			"Service đang thuộc Node khác: "
			+ String(service.get_service_id())
		)
		return false

	if service.get_parent() == null:
		add_child(service)

	return register_service(service)


func register_service(service: Service) -> bool:
	if not is_instance_valid(service):
		_log_error("Không thể đăng ký Service không hợp lệ")
		return false

	if service.get_parent() != self:
		_log_error("Service phải là Child trực tiếp của Services")
		return false

	var service_id: StringName = service.get_service_id()

	if service_id.is_empty():
		_log_error("Service ID không được để trống")
		return false

	if _services.has(service_id):
		_log_error("Service ID đã tồn tại: " + String(service_id))
		return false

	_services[service_id] = service

	_connect_service(service)

	service_registered.emit(service_id)

	_log("Service Registered: " + String(service_id))

	return true


func unregister_service(service_id: StringName) -> bool:
	if not _services.has(service_id):
		return false

	var service: Service = _services[service_id]

	if is_instance_valid(service):
		if service.is_ready() or service.is_paused():
			service.stop()

		_disconnect_service(service)

		if service.get_parent() == self:
			remove_child(service)

	_services.erase(service_id)

	service_unregistered.emit(service_id)

	_log("Service Unregistered: " + String(service_id))

	if free_on_remove and is_instance_valid(service):
		service.queue_free()

	return true


func get_service(service_id: StringName) -> Service:
	if not _services.has(service_id):
		return null

	var service: Service = _services[service_id]

	if not is_instance_valid(service):
		_services.erase(service_id)
		return null

	return service


func has_service(service_id: StringName) -> bool:
	return _services.has(service_id)


func get_service_count() -> int:
	return _services.size()


func get_service_ids() -> Array[StringName]:
	return _get_service_ids_copy()


func start_service(service_id: StringName) -> bool:
	var service: Service = get_service(service_id)

	if service == null:
		return false

	return service.start()


func pause_service(service_id: StringName) -> bool:
	var service: Service = get_service(service_id)

	if service == null:
		return false

	return service.pause()


func resume_service(service_id: StringName) -> bool:
	var service: Service = get_service(service_id)

	if service == null:
		return false

	return service.resume()


func stop_service(service_id: StringName) -> bool:
	var service: Service = get_service(service_id)

	if service == null:
		return false

	return service.stop()


func start_all() -> bool:
	var success: bool = true

	for service_id in _get_service_ids_copy():
		var service: Service = get_service(service_id)

		if service == null:
			continue

		if not service.start():
			success = false

	return success


func pause_all() -> bool:
	var success: bool = true

	for service_id in _get_service_ids_copy():
		var service: Service = get_service(service_id)

		if service == null:
			continue

		if service.is_ready() and not service.pause():
			success = false

	return success


func resume_all() -> bool:
	var success: bool = true

	for service_id in _get_service_ids_copy():
		var service: Service = get_service(service_id)

		if service == null:
			continue

		if service.is_paused() and not service.resume():
			success = false

	return success


func stop_all() -> bool:
	var success: bool = true

	for service_id in _get_service_ids_copy():
		var service: Service = get_service(service_id)

		if service == null:
			continue

		if not service.is_stopped() and not service.stop():
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


func get_services_error() -> String:
	return services_error


func _register_existing_children() -> void:
	for child in get_children():
		if child is Service:
			register_service(child)


func _connect_service(service: Service) -> void:
	if not service.service_started.is_connected(_on_service_started):
		service.service_started.connect(_on_service_started)

	if not service.service_ready.is_connected(_on_service_ready):
		service.service_ready.connect(_on_service_ready)

	if not service.service_paused.is_connected(_on_service_paused):
		service.service_paused.connect(_on_service_paused)

	if not service.service_resumed.is_connected(_on_service_resumed):
		service.service_resumed.connect(_on_service_resumed)

	if not service.service_stopping.is_connected(_on_service_stopping):
		service.service_stopping.connect(_on_service_stopping)

	if not service.service_stopped.is_connected(_on_service_stopped):
		service.service_stopped.connect(_on_service_stopped)

	if not service.service_failed.is_connected(_on_service_failed):
		service.service_failed.connect(_on_service_failed)


func _disconnect_service(service: Service) -> void:
	if not is_instance_valid(service):
		return

	if service.service_started.is_connected(_on_service_started):
		service.service_started.disconnect(_on_service_started)

	if service.service_ready.is_connected(_on_service_ready):
		service.service_ready.disconnect(_on_service_ready)

	if service.service_paused.is_connected(_on_service_paused):
		service.service_paused.disconnect(_on_service_paused)

	if service.service_resumed.is_connected(_on_service_resumed):
		service.service_resumed.disconnect(_on_service_resumed)

	if service.service_stopping.is_connected(_on_service_stopping):
		service.service_stopping.disconnect(_on_service_stopping)

	if service.service_stopped.is_connected(_on_service_stopped):
		service.service_stopped.disconnect(_on_service_stopped)

	if service.service_failed.is_connected(_on_service_failed):
		service.service_failed.disconnect(_on_service_failed)


func _on_service_started(service_id: StringName) -> void:
	service_started.emit(service_id)


func _on_service_ready(service_id: StringName) -> void:
	service_ready.emit(service_id)


func _on_service_paused(service_id: StringName) -> void:
	service_paused.emit(service_id)


func _on_service_resumed(service_id: StringName) -> void:
	service_resumed.emit(service_id)


func _on_service_stopping(service_id: StringName) -> void:
	service_stopping.emit(service_id)


func _on_service_stopped(service_id: StringName) -> void:
	service_stopped.emit(service_id)


func _on_service_failed(
	service_id: StringName,
	reason: String
) -> void:
	service_failed.emit(service_id, reason)

	_log_error(
		"Service Failed ["
		+ String(service_id)
		+ "]: "
		+ reason
	)


func _get_service_ids_copy() -> Array[StringName]:
	var result: Array[StringName] = []

	for service_id in _services.keys():
		result.append(service_id)

	return result


func _validate_root() -> bool:
	services_error = ""

	if not is_inside_tree():
		services_error = "Services không nằm trong SceneTree"
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Services: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
			% [EXPECTED_NODE_NAME, name]
		)

	return true


func _fail(reason: String) -> bool:
	state = State.FAILED
	services_error = reason

	services_failed.emit(reason)
	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING
	services_stopping.emit()

	if stop_services_on_shutdown:
		stop_all()

	state = State.STOPPED
	services_stopped.emit()

	_log("Services Stopped")


func _log(message: String) -> void:
	if console_output:
		print("[Services] ", message)


func _log_error(message: String) -> void:
	push_error("[Services] " + message) 
