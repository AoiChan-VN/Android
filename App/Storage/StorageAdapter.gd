class_name StorageAdapter
extends Node

signal adapter_started(storage_id: StringName)
signal adapter_ready(storage_id: StringName)
signal adapter_paused(storage_id: StringName)
signal adapter_resumed(storage_id: StringName)
signal adapter_stopping(storage_id: StringName)
signal adapter_stopped(storage_id: StringName)
signal adapter_failed(storage_id: StringName, reason: String)

enum State {
	IDLE,
	STARTING,
	READY,
	PAUSED,
	STOPPING,
	STOPPED,
	FAILED
}

@export_group("Storage")
@export var storage_id: StringName = &""
@export var root_path: String = "user://storage"
@export var auto_start: bool = true
@export var create_root: bool = true
@export var console_output: bool = true

var state: State = State.IDLE
var storage_error: String = ""


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
		storage_error = ""

	state = State.STARTING

	adapter_started.emit(storage_id)

	if not _validate_adapter():
		return _fail(storage_error)

	if create_root and not _ensure_root():
		return _fail(storage_error)

	state = State.READY

	adapter_ready.emit(storage_id)

	_log("Storage Adapter Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	state = State.PAUSED

	adapter_paused.emit(storage_id)

	_log("Storage Adapter Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	state = State.READY

	adapter_resumed.emit(storage_id)

	_log("Storage Adapter Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func ensure_directory(
	relative_path: String = ""
) -> bool:
	if not _is_operational():
		return false

	var path: String = _resolve_path(relative_path)

	if path.is_empty():
		return false

	var absolute_path: String = ProjectSettings.globalize_path(path)

	if DirAccess.dir_exists_absolute(absolute_path):
		return true

	var error: int = DirAccess.make_dir_recursive_absolute(
		absolute_path
	)

	if error != OK:
		storage_error = (
			"Không thể tạo thư mục: "
			+ absolute_path
		)
		_log_error(storage_error)
		return false

	return true


func file_exists(
	relative_path: String
) -> bool:
	var path: String = _resolve_file_path(relative_path)

	if path.is_empty():
		return false

	return FileAccess.file_exists(path)


func write_text(
	relative_path: String,
	content: String
) -> bool:
	if not _is_operational():
		return false

	var path: String = _resolve_file_path(relative_path)

	if path.is_empty():
		return false

	if not _ensure_parent_directory(path):
		return false

	var file := FileAccess.open(
		path,
		FileAccess.WRITE
	)

	if file == null:
		storage_error = (
			"Không thể mở File để ghi: "
			+ path
		)
		_log_error(storage_error)
		return false

	file.store_string(content)
	file.flush()
	file.close()

	return true


func read_text(
	relative_path: String
) -> String:
	if not _is_operational():
		return ""

	var path: String = _resolve_file_path(relative_path)

	if path.is_empty():
		return ""

	if not FileAccess.file_exists(path):
		return ""

	var file := FileAccess.open(
		path,
		FileAccess.READ
	)

	if file == null:
		storage_error = (
			"Không thể mở File để đọc: "
			+ path
		)
		_log_error(storage_error)
		return ""

	var content: String = file.get_as_text()

	file.close()

	return content


func write_bytes(
	relative_path: String,
	data: PackedByteArray
) -> bool:
	if not _is_operational():
		return false

	var path: String = _resolve_file_path(relative_path)

	if path.is_empty():
		return false

	if not _ensure_parent_directory(path):
		return false

	var file := FileAccess.open(
		path,
		FileAccess.WRITE
	)

	if file == null:
		storage_error = (
			"Không thể mở File để ghi Binary: "
			+ path
		)
		_log_error(storage_error)
		return false

	file.store_buffer(data)
	file.flush()
	file.close()

	return true


func read_bytes(
	relative_path: String
) -> PackedByteArray:
	if not _is_operational():
		return PackedByteArray()

	var path: String = _resolve_file_path(relative_path)

	if path.is_empty():
		return PackedByteArray()

	if not FileAccess.file_exists(path):
		return PackedByteArray()

	var file := FileAccess.open(
		path,
		FileAccess.READ
	)

	if file == null:
		storage_error = (
			"Không thể mở File để đọc Binary: "
			+ path
		)
		_log_error(storage_error)
		return PackedByteArray()

	var data: PackedByteArray = file.get_buffer(
		file.get_length()
	)

	file.close()

	return data


func write_json(
	relative_path: String,
	data: Variant,
	indent: String = "\t"
) -> bool:
	var json_text: String = JSON.stringify(
		data,
		indent
	)

	return write_text(
		relative_path,
		json_text
	)


func read_json(
	relative_path: String
) -> Variant:
	var json_text: String = read_text(
		relative_path
	)

	if json_text.is_empty():
		return null

	var json := JSON.new()

	var error: int = json.parse(
		json_text
	)

	if error != OK:
		storage_error = (
			"JSON Parse Error: "
			+ json.get_error_message()
			+ " tại dòng "
			+ str(json.get_error_line())
		)
		_log_error(storage_error)
		return null

	return json.data


func delete_file(
	relative_path: String
) -> bool:
	if not _is_operational():
		return false

	var path: String = _resolve_file_path(relative_path)

	if path.is_empty():
		return false

	if not FileAccess.file_exists(path):
		return false

	var absolute_path: String = ProjectSettings.globalize_path(
		path
	)

	var error: int = DirAccess.remove_absolute(
		absolute_path
	)

	if error != OK:
		storage_error = (
			"Không thể xóa File: "
			+ absolute_path
		)
		_log_error(storage_error)
		return false

	return true


func directory_exists(
	relative_path: String = ""
) -> bool:
	var path: String = _resolve_path(relative_path)

	if path.is_empty():
		return false

	var absolute_path: String = ProjectSettings.globalize_path(
		path
	)

	return DirAccess.dir_exists_absolute(
		absolute_path
	)


func delete_directory(
	relative_path: String
) -> bool:
	if not _is_operational():
		return false

	if relative_path.is_empty():
		return false

	var path: String = _resolve_path(
		relative_path
	)

	if path.is_empty():
		return false

	if path == root_path:
		return false

	var absolute_path: String = ProjectSettings.globalize_path(
		path
	)

	if not DirAccess.dir_exists_absolute(
		absolute_path
	):
		return false

	var error: int = DirAccess.remove_absolute(
		absolute_path
	)

	if error != OK:
		storage_error = (
			"Không thể xóa thư mục: "
			+ absolute_path
		)
		_log_error(storage_error)
		return false

	return true


func list_files(
	relative_path: String = ""
) -> Array[String]:
	var result: Array[String] = []

	if not _is_operational():
		return result

	var path: String = _resolve_path(
		relative_path
	)

	if path.is_empty():
		return result

	var directory := DirAccess.open(
		path
	)

	if directory == null:
		return result

	directory.list_dir_begin()

	while true:
		var file_name: String = directory.get_next()

		if file_name.is_empty():
			break

		if directory.current_is_dir():
			continue

		result.append(file_name)

	directory.list_dir_end()

	return result


func list_directories(
	relative_path: String = ""
) -> Array[String]:
	var result: Array[String] = []

	if not _is_operational():
		return result

	var path: String = _resolve_path(
		relative_path
	)

	if path.is_empty():
		return result

	var directory := DirAccess.open(
		path
	)

	if directory == null:
		return result

	directory.list_dir_begin()

	while true:
		var directory_name: String = directory.get_next()

		if directory_name.is_empty():
			break

		if not directory.current_is_dir():
			continue

		result.append(directory_name)

	directory.list_dir_end()

	return result


func get_storage_id() -> StringName:
	return storage_id


func get_root_path() -> String:
	return root_path


func get_absolute_root_path() -> String:
	return ProjectSettings.globalize_path(
		root_path
	)


func get_state() -> State:
	return state


func get_error() -> String:
	return storage_error


func is_ready() -> bool:
	return state == State.READY


func is_paused() -> bool:
	return state == State.PAUSED


func is_stopped() -> bool:
	return state == State.STOPPED


func is_failed() -> bool:
	return state == State.FAILED


func _validate_adapter() -> bool:
	storage_error = ""

	if not is_inside_tree():
		storage_error = (
			"Storage Adapter không nằm trong SceneTree"
		)
		return false

	if storage_id.is_empty():
		storage_error = (
			"Storage ID không được để trống"
		)
		return false

	if root_path.is_empty():
		storage_error = (
			"Root Path không được để trống"
		)
		return false

	return true


func _ensure_root() -> bool:
	var absolute_path: String = (
		get_absolute_root_path()
	)

	if DirAccess.dir_exists_absolute(
		absolute_path
	):
		return true

	var error: int = (
		DirAccess.make_dir_recursive_absolute(
			absolute_path
		)
	)

	if error != OK:
		storage_error = (
			"Không thể tạo Storage Root: "
			+ absolute_path
		)
		_log_error(storage_error)
		return false

	return true


func _ensure_parent_directory(
	file_path: String
) -> bool:
	var base_directory: String = (
		file_path.get_base_dir()
	)

	if base_directory == root_path:
		return true

	var absolute_path: String = (
		ProjectSettings.globalize_path(
			base_directory
		)
	)

	if DirAccess.dir_exists_absolute(
		absolute_path
	):
		return true

	var error: int = (
		DirAccess.make_dir_recursive_absolute(
			absolute_path
		)
	)

	if error != OK:
		storage_error = (
			"Không thể tạo Parent Directory: "
			+ absolute_path
		)
		_log_error(storage_error)
		return false

	return true


func _resolve_file_path(
	relative_path: String
) -> String:
	var path: String = _resolve_path(
		relative_path
	)

	if path.is_empty():
		return ""

	if path == root_path:
		return ""

	return path


func _resolve_path(
	relative_path: String
) -> String:
	if relative_path.is_empty():
		return root_path

	var normalized: String = (
		relative_path.replace(
			"\\",
			"/"
		)
	)

	if normalized.begins_with("/"):
		return ""

	if normalized.contains("://"):
		return ""

	if normalized.contains(":"):
		return ""

	var parts: PackedStringArray = (
		normalized.split(
			"/",
			false
		)
	)

	for part in parts:
		if part == "..":
			return ""

	return root_path.path_join(
		normalized
	)


func _is_operational() -> bool:
	return (
		state == State.READY
		or state == State.PAUSED
	)


func _fail(
	reason: String
) -> bool:
	state = State.FAILED
	storage_error = reason

	adapter_failed.emit(
		storage_id,
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

	adapter_stopping.emit(
		storage_id
	)

	_log("Storage Adapter Stopping")

	state = State.STOPPED

	adapter_stopped.emit(
		storage_id
	)

	_log("Storage Adapter Stopped")


func _log(
	message: String
) -> void:
	if console_output:
		print(
			"[StorageAdapter:",
			storage_id,
			"] ",
			message
		)


func _log_error(
	message: String
) -> void:
	push_error(
		"[StorageAdapter:%s] %s"
		% [
			storage_id,
			message
		]
) 
