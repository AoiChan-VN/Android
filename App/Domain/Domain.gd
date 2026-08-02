class_name Domain
extends Node

signal domain_started
signal domain_ready
signal domain_paused
signal domain_resumed
signal domain_stopping
signal domain_stopped
signal domain_failed(reason: String)

signal entity_registered(
	entity_id: StringName,
	entity_type: StringName
)

signal entity_unregistered(
	entity_id: StringName,
	entity_type: StringName
)

signal entity_changed(
	entity_id: StringName,
	version: int
)

signal entity_active_changed(
	entity_id: StringName,
	active: bool
)

signal event_queued(
	entity_id: StringName,
	event: Dictionary
)

enum State {
	IDLE,
	STARTING,
	READY,
	PAUSED,
	STOPPING,
	STOPPED,
	FAILED
}

const EXPECTED_NODE_NAME: StringName = &"Domain"

@export_group("Domain")
@export var auto_start: bool = true
@export var activate_entities: bool = true
@export var deactivate_on_stop: bool = true
@export var allow_replace: bool = false
@export var clear_events_on_stop: bool = false
@export var console_output: bool = true

@export_group("Validation")
@export var validate_root: bool = true

var state: State = State.IDLE
var domain_error: String = ""

var _entities: Dictionary = {}
var _entity_order: Array[StringName] = []
var _type_index: Dictionary = {}
var _event_queue: Array[Dictionary] = []


func _enter_tree() -> void:
	state = State.STARTING


func _ready() -> void:
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
		domain_error = ""

	if validate_root and not _validate_root():
		return _fail(domain_error)

	state = State.STARTING
	domain_started.emit()

	if activate_entities:
		activate_all()

	state = State.READY
	domain_ready.emit()

	_log("Domain Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	state = State.PAUSED
	domain_paused.emit()

	_log("Domain Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	state = State.READY
	domain_resumed.emit()

	_log("Domain Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func create_entity(
	entity_id: StringName,
	entity_type: StringName,
	initial_state: Dictionary = {}
) -> DomainEntity:
	var entity := DomainEntity.new()

	if not entity.configure(
		entity_id,
		entity_type,
		initial_state
	):
		_log_error("Invalid entity configuration")
		return null

	if not register_entity(entity):
		return null

	return entity


func register_entity(entity: DomainEntity) -> bool:
	if entity == null:
		_log_error("Invalid entity")
		return false

	if not entity.is_valid():
		_log_error("Entity ID or type is empty")
		return false

	var entity_id: StringName = entity.get_id()
	var entity_type: StringName = entity.get_type_id()

	if _entities.has(entity_id):
		if not allow_replace:
			_log_error(
				"Entity already exists: "
				+ String(entity_id)
			)
			return false

		unregister_entity(entity_id)

	_entities[entity_id] = entity
	_entity_order.append(entity_id)

	_add_type_index(entity_type, entity_id)
	_connect_entity(entity)

	if state == State.READY and activate_entities:
		entity.activate()

	entity_registered.emit(entity_id, entity_type)

	_log("Entity Registered: " + String(entity_id))

	return true


func unregister_entity(entity_id: StringName) -> bool:
	var entity: DomainEntity = get_entity(entity_id)

	if entity == null:
		return false

	var entity_type: StringName = entity.get_type_id()

	entity.deactivate()
	_disconnect_entity(entity)

	_entities.erase(entity_id)
	_entity_order.erase(entity_id)

	_remove_type_index(entity_type, entity_id)

	entity_unregistered.emit(entity_id, entity_type)

	_log("Entity Unregistered: " + String(entity_id))

	return true


func replace_entity(entity: DomainEntity) -> bool:
	if entity == null:
		return false

	var entity_id: StringName = entity.get_id()

	if String(entity_id).is_empty():
		return false

	if _entities.has(entity_id):
		unregister_entity(entity_id)

	return register_entity(entity)


func get_entity(entity_id: StringName) -> DomainEntity:
	if not _entities.has(entity_id):
		return null

	var entity: DomainEntity = _entities[entity_id]

	if entity == null:
		_entities.erase(entity_id)
		_entity_order.erase(entity_id)
		return null

	return entity


func has_entity(entity_id: StringName) -> bool:
	return get_entity(entity_id) != null


func get_entity_count() -> int:
	return _entities.size()


func get_entity_ids() -> Array[StringName]:
	return _get_entity_ids_copy()


func get_entity_ids_by_type(
	entity_type: StringName
) -> Array[StringName]:
	var result: Array[StringName] = []

	if not _type_index.has(entity_type):
		return result

	var ids: Array = _type_index[entity_type]

	for entity_id in ids:
		if has_entity(entity_id):
			result.append(entity_id)

	return result


func get_entities_by_type(
	entity_type: StringName
) -> Array[DomainEntity]:
	var result: Array[DomainEntity] = []

	for entity_id in get_entity_ids_by_type(entity_type):
		var entity: DomainEntity = get_entity(entity_id)

		if entity != null:
			result.append(entity)

	return result


func update_entity(
	entity_id: StringName,
	patch: Dictionary,
	overwrite: bool = true
) -> bool:
	if state != State.READY:
		return false

	var entity: DomainEntity = get_entity(entity_id)

	if entity == null:
		return false

	if not entity.is_active():
		return false

	return entity.apply(patch, overwrite)


func set_entity_value(
	entity_id: StringName,
	key: StringName,
	value: Variant
) -> bool:
	if state != State.READY:
		return false

	var entity: DomainEntity = get_entity(entity_id)

	if entity == null:
		return false

	if not entity.is_active():
		return false

	return entity.set_value(key, value)


func remove_entity_value(
	entity_id: StringName,
	key: StringName
) -> bool:
	if state != State.READY:
		return false

	var entity: DomainEntity = get_entity(entity_id)

	if entity == null:
		return false

	if not entity.is_active():
		return false

	return entity.remove_value(key)


func add_entity_event(
	entity_id: StringName,
	event_type: StringName,
	payload: Dictionary = {}
) -> bool:
	var entity: DomainEntity = get_entity(entity_id)

	if entity == null:
		return false

	return entity.add_event(event_type, payload)


func activate_entity(entity_id: StringName) -> bool:
	var entity: DomainEntity = get_entity(entity_id)

	if entity == null:
		return false

	return entity.activate()


func deactivate_entity(entity_id: StringName) -> bool:
	var entity: DomainEntity = get_entity(entity_id)

	if entity == null:
		return false

	return entity.deactivate()


func activate_all() -> bool:
	var success: bool = true

	for entity_id in _get_entity_ids_copy():
		var entity: DomainEntity = get_entity(entity_id)

		if entity == null:
			continue

		if not entity.activate():
			success = false

	return success


func deactivate_all() -> bool:
	var success: bool = true
	var entity_ids: Array[StringName] = _get_entity_ids_copy()

	entity_ids.reverse()

	for entity_id in entity_ids:
		var entity: DomainEntity = get_entity(entity_id)

		if entity == null:
			continue

		if not entity.deactivate():
			success = false

	return success


func pop_event() -> Dictionary:
	if _event_queue.is_empty():
		return {}

	var event: Dictionary = _event_queue.pop_front()

	return event.duplicate(true)


func drain_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for event in _event_queue:
		result.append(event.duplicate(true))

	_event_queue.clear()

	return result


func clear_events() -> void:
	_event_queue.clear()


func get_event_count() -> int:
	return _event_queue.size()


func clear_entities() -> void:
	var entity_ids: Array[StringName] = _get_entity_ids_copy()

	entity_ids.reverse()

	for entity_id in entity_ids:
		unregister_entity(entity_id)


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
	return domain_error


func _connect_entity(entity: DomainEntity) -> void:
	if not entity.changed.is_connected(_on_entity_changed):
		entity.changed.connect(_on_entity_changed)

	if not entity.event_added.is_connected(_on_event_added):
		entity.event_added.connect(_on_event_added)

	if not entity.active_changed.is_connected(
		_on_entity_active_changed
	):
		entity.active_changed.connect(
			_on_entity_active_changed
		)


func _disconnect_entity(entity: DomainEntity) -> void:
	if entity.changed.is_connected(_on_entity_changed):
		entity.changed.disconnect(_on_entity_changed)

	if entity.event_added.is_connected(_on_event_added):
		entity.event_added.disconnect(_on_event_added)

	if entity.active_changed.is_connected(
		_on_entity_active_changed
	):
		entity.active_changed.disconnect(
			_on_entity_active_changed
		)


func _on_entity_changed(
	entity_id: StringName,
	version: int
) -> void:
	entity_changed.emit(entity_id, version)


func _on_event_added(
	entity_id: StringName,
	event: Dictionary
) -> void:
	var event_copy: Dictionary = event.duplicate(true)

	_event_queue.append(event_copy)

	event_queued.emit(entity_id, event_copy)


func _on_entity_active_changed(
	entity_id: StringName,
	active: bool
) -> void:
	entity_active_changed.emit(entity_id, active)


func _add_type_index(
	entity_type: StringName,
	entity_id: StringName
) -> void:
	if not _type_index.has(entity_type):
		_type_index[entity_type] = []

	var ids: Array = _type_index[entity_type]

	if not ids.has(entity_id):
		ids.append(entity_id)


func _remove_type_index(
	entity_type: StringName,
	entity_id: StringName
) -> void:
	if not _type_index.has(entity_type):
		return

	var ids: Array = _type_index[entity_type]

	ids.erase(entity_id)

	if ids.is_empty():
		_type_index.erase(entity_type)


func _get_entity_ids_copy() -> Array[StringName]:
	var result: Array[StringName] = []

	for entity_id in _entity_order:
		if _entities.has(entity_id):
			result.append(entity_id)

	return result


func _validate_root() -> bool:
	domain_error = ""

	if not is_inside_tree():
		domain_error = "Domain is not inside SceneTree"
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Domain root name changed from '%s' to '%s'. Runtime is not name dependent."
			% [EXPECTED_NODE_NAME, name]
		)

	return true


func _fail(reason: String) -> bool:
	state = State.FAILED
	domain_error = reason

	domain_failed.emit(reason)

	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING
	domain_stopping.emit()

	if deactivate_on_stop:
		deactivate_all()

	if clear_events_on_stop:
		clear_events()

	state = State.STOPPED
	domain_stopped.emit()

	_log("Domain Stopped")


func _log(message: String) -> void:
	if console_output:
		print("[Domain] ", message)


func _log_error(message: String) -> void:
	push_error("[Domain] " + message) 
