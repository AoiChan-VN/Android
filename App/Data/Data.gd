class_name Data
extends Node

signal data_started
signal data_ready
signal data_paused
signal data_resumed
signal data_stopping
signal data_stopped
signal data_failed(reason: String)

signal record_registered(
	record_id: StringName,
	record_type: StringName
)

signal record_replaced(
	record_id: StringName,
	record_type: StringName
)

signal record_unregistered(
	record_id: StringName,
	record_type: StringName
)

signal record_changed(
	record_id: StringName,
	version: int
)

signal metadata_changed(
	record_id: StringName,
	version: int
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

const EXPECTED_NODE_NAME: StringName = &"Data"

@export_group("Data")
@export var auto_start: bool = true
@export var allow_replace: bool = false
@export var clear_on_stop: bool = false
@export var console_output: bool = true
@export var validate_records: bool = true

@export_group("Validation")
@export var validate_root: bool = true

var state: State = State.IDLE
var data_error: String = ""

var _records: Dictionary = {}
var _record_order: Array[StringName] = []
var _type_index: Dictionary = {}


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
		data_error = ""

	if validate_root and not _validate_root():
		return _fail(data_error)

	state = State.STARTING

	data_started.emit()

	if validate_records and not _validate_all_records():
		return _fail(data_error)

	state = State.READY

	data_ready.emit()

	_log("Data Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	state = State.PAUSED

	data_paused.emit()

	_log("Data Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	state = State.READY

	data_resumed.emit()

	_log("Data Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func create_record(
	record_id: StringName,
	record_type: StringName,
	initial_data: Dictionary = {},
	initial_metadata: Dictionary = {},
	schema_version: int = 1
) -> DataRecord:
	var record := DataRecord.new()

	if not record.configure(
		record_id,
		record_type,
		initial_data,
		initial_metadata,
		schema_version
	):
		_log_error("Invalid DataRecord configuration")
		return null

	if not register_record(record):
		return null

	return record


func register_record(
	record: DataRecord
) -> bool:
	if record == null:
		_log_error("Invalid DataRecord")
		return false

	if validate_records and not record.is_valid():
		_log_error("DataRecord validation failed")
		return false

	var record_id: StringName = record.get_id()
	var record_type: StringName = record.get_type_id()

	if _records.has(record_id):
		if not allow_replace:
			_log_error(
				"DataRecord already exists: "
				+ String(record_id)
			)
			return false

		return replace_record(record)

	_records[record_id] = record
	_record_order.append(record_id)

	_add_type_index(
		record_type,
		record_id
	)

	_connect_record(record)

	record_registered.emit(
		record_id,
		record_type
	)

	_log(
		"DataRecord Registered: "
		+ String(record_id)
	)

	return true


func replace_record(
	record: DataRecord
) -> bool:
	if record == null:
		return false

	if validate_records and not record.is_valid():
		return false

	var record_id: StringName = record.get_id()
	var record_type: StringName = record.get_type_id()

	if _records.has(record_id):
		var previous: DataRecord = _records[record_id]

		if previous != null:
			_disconnect_record(previous)

		_remove_type_index(
			previous.get_type_id(),
			record_id
		)

		_records[record_id] = record

		_add_type_index(
			record_type,
			record_id
		)

		_connect_record(record)

		record_replaced.emit(
			record_id,
			record_type
		)

		_log(
			"DataRecord Replaced: "
			+ String(record_id)
		)

		return true

	return register_record(record)


func unregister_record(
	record_id: StringName
) -> bool:
	var record: DataRecord = get_record(record_id)

	if record == null:
		return false

	var record_type: StringName = record.get_type_id()

	_disconnect_record(record)

	_records.erase(record_id)
	_record_order.erase(record_id)

	_remove_type_index(
		record_type,
		record_id
	)

	record_unregistered.emit(
		record_id,
		record_type
	)

	_log(
		"DataRecord Unregistered: "
		+ String(record_id)
	)

	return true


func get_record(
	record_id: StringName
) -> DataRecord:
	if not _records.has(record_id):
		return null

	var record: DataRecord = _records[record_id]

	if record == null:
		_records.erase(record_id)
		_record_order.erase(record_id)
		return null

	return record


func has_record(
	record_id: StringName
) -> bool:
	return get_record(record_id) != null


func get_record_count() -> int:
	return _records.size()


func get_record_ids() -> Array[StringName]:
	return _get_record_ids_copy()


func get_record_ids_by_type(
	record_type: StringName
) -> Array[StringName]:
	var result: Array[StringName] = []

	if not _type_index.has(record_type):
		return result

	var ids: Array = _type_index[record_type]

	for record_id in ids:
		if has_record(record_id):
			result.append(record_id)

	return result


func get_records_by_type(
	record_type: StringName
) -> Array[DataRecord]:
	var result: Array[DataRecord] = []

	for record_id in get_record_ids_by_type(record_type):
		var record: DataRecord = get_record(record_id)

		if record != null:
			result.append(record)

	return result


func set_value(
	record_id: StringName,
	key: StringName,
	value: Variant
) -> bool:
	if state != State.READY:
		return false

	var record: DataRecord = get_record(record_id)

	if record == null:
		return false

	return record.set_value(
		key,
		value
	)


func get_value(
	record_id: StringName,
	key: StringName,
	default_value: Variant = null
) -> Variant:
	var record: DataRecord = get_record(record_id)

	if record == null:
		return default_value

	return record.get_value(
		key,
		default_value
	)


func remove_value(
	record_id: StringName,
	key: StringName
) -> bool:
	if state != State.READY:
		return false

	var record: DataRecord = get_record(record_id)

	if record == null:
		return false

	return record.remove_value(key)


func apply(
	record_id: StringName,
	patch: Dictionary,
	overwrite: bool = true
) -> bool:
	if state != State.READY:
		return false

	var record: DataRecord = get_record(record_id)

	if record == null:
		return false

	return record.apply(
		patch,
		overwrite
	)


func set_metadata(
	record_id: StringName,
	key: StringName,
	value: Variant
) -> bool:
	if state != State.READY:
		return false

	var record: DataRecord = get_record(record_id)

	if record == null:
		return false

	return record.set_metadata(
		key,
		value
	)


func get_metadata(
	record_id: StringName,
	key: StringName,
	default_value: Variant = null
) -> Variant:
	var record: DataRecord = get_record(record_id)

	if record == null:
		return default_value

	return record.get_metadata(
		key,
		default_value
	)


func create_snapshot() -> Dictionary:
	var snapshot: Dictionary = {
		"version": 1,
		"records": []
	}

	var records: Array = []

	for record_id in _get_record_ids_copy():
		var record: DataRecord = get_record(record_id)

		if record == null:
			continue

		records.append(
			record.to_dictionary()
		)

	snapshot["records"] = records

	return snapshot


func restore_snapshot(
	snapshot: Dictionary,
	clear_existing: bool = true,
	replace_existing: bool = false
) -> bool:
	if state != State.READY:
		return false

	if not snapshot.has("records"):
		return false

	var records: Variant = snapshot["records"]

	if not records is Array:
		return false

	if clear_existing:
		clear_records()

	for item in records:
		if not item is Dictionary:
			return false

		var record := DataRecord.new()

		if not record.load_dictionary(item):
			return false

		var record_id: StringName = record.get_id()

		if _records.has(record_id):
			if not replace_existing:
				return false

			if not replace_record(record):
				return false
		else:
			if not register_record(record):
				return false

	return true


func clear_records() -> void:
	var record_ids: Array[StringName] = _get_record_ids_copy()

	record_ids.reverse()

	for record_id in record_ids:
		unregister_record(record_id)


func get_snapshot_record_count(
	snapshot: Dictionary
) -> int:
	if not snapshot.has("records"):
		return 0

	var records: Variant = snapshot["records"]

	if not records is Array:
		return 0

	return records.size()


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
	return data_error


func _connect_record(
	record: DataRecord
) -> void:
	if not record.changed.is_connected(
		_on_record_changed
	):
		record.changed.connect(
			_on_record_changed
		)

	if not record.metadata_changed.is_connected(
		_on_metadata_changed
	):
		record.metadata_changed.connect(
			_on_metadata_changed
		)


func _disconnect_record(
	record: DataRecord
) -> void:
	if record.changed.is_connected(
		_on_record_changed
	):
		record.changed.disconnect(
			_on_record_changed
		)

	if record.metadata_changed.is_connected(
		_on_metadata_changed
	):
		record.metadata_changed.disconnect(
			_on_metadata_changed
	)


func _on_record_changed(
	record_id: StringName,
	version: int
) -> void:
	record_changed.emit(
		record_id,
		version
	)


func _on_metadata_changed(
	record_id: StringName,
	version: int
) -> void:
	metadata_changed.emit(
		record_id,
		version
	)


func _add_type_index(
	record_type: StringName,
	record_id: StringName
) -> void:
	if not _type_index.has(record_type):
		_type_index[record_type] = []

	var ids: Array = _type_index[record_type]

	if not ids.has(record_id):
		ids.append(record_id)


func _remove_type_index(
	record_type: StringName,
	record_id: StringName
) -> void:
	if not _type_index.has(record_type):
		return

	var ids: Array = _type_index[record_type]

	ids.erase(record_id)

	if ids.is_empty():
		_type_index.erase(record_type)


func _validate_all_records() -> bool:
	data_error = ""

	for record_id in _get_record_ids_copy():
		var record: DataRecord = get_record(record_id)

		if record == null:
			data_error = (
				"DataRecord không hợp lệ: "
				+ String(record_id)
			)
			return false

		if not record.is_valid():
			data_error = (
				"DataRecord validation failed: "
				+ String(record_id)
			)
			return false

	return true


func _get_record_ids_copy() -> Array[StringName]:
	var result: Array[StringName] = []

	for record_id in _record_order:
		if _records.has(record_id):
			result.append(record_id)

	return result


func _validate_root() -> bool:
	data_error = ""

	if not is_inside_tree():
		data_error = "Data không nằm trong SceneTree"
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Data: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
			% [
				EXPECTED_NODE_NAME,
				name
			]
		)

	return true


func _fail(
	reason: String
) -> bool:
	state = State.FAILED
	data_error = reason

	data_failed.emit(reason)

	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING

	data_stopping.emit()

	if clear_on_stop:
		clear_records()

	state = State.STOPPED

	data_stopped.emit()

	_log("Data Stopped")


func _log(
	message: String
) -> void:
	if console_output:
		print(
			"[Data] ",
			message
		)


func _log_error(
	message: String
) -> void:
	push_error(
		"[Data] "
		+ message
	) 
