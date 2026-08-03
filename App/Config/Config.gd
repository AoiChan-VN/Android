class_name Config
extends Node

signal config_started
signal config_ready
signal config_loaded
signal config_saved
signal config_changed(
	section: String,
	key: String
)
signal config_section_changed(
	section: String
)
signal config_paused
signal config_resumed
signal config_stopping
signal config_stopped
signal config_failed(
	reason: String
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

const EXPECTED_NODE_NAME: StringName = &"Config"
const DEFAULT_CONFIG_PATH: String = "user://config/app.cfg"

@export_group("Config")
@export var auto_start: bool = true
@export var auto_load: bool = true
@export var auto_save: bool = false
@export var create_on_missing: bool = true
@export var save_on_stop: bool = false
@export var clear_on_stop: bool = false
@export var console_output: bool = true

@export_group("File")
@export var config_path: String = DEFAULT_CONFIG_PATH
@export var create_directory: bool = true

@export_group("Validation")
@export var validate_root: bool = true
@export var validate_path: bool = true

var state: State = State.IDLE
var config_error: String = ""

var _config_file: ConfigFile = ConfigFile.new()
var _loaded: bool = false
var _dirty: bool = false


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
		config_error = ""

	if validate_root and not _validate_root():
		return _fail(config_error)

	if validate_path and not _validate_path():
		return _fail(config_error)

	state = State.STARTING

	config_started.emit()

	if auto_load:
		var load_result: int = load_config()

		if load_result != OK and not create_on_missing:
			return _fail(
				"Không thể Load Config: "
				+ error_string(load_result)
			)

	state = State.READY

	config_ready.emit()

	_log("Config Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	state = State.PAUSED

	config_paused.emit()

	_log("Config Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	state = State.READY

	config_resumed.emit()

	_log("Config Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func load_config() -> int:
	if not _is_operational():
		return ERR_UNCONFIGURED

	if config_path.is_empty():
		_set_error(
			"Config Path không được để trống"
		)
		return ERR_INVALID_PARAMETER

	if not FileAccess.file_exists(config_path):
		_config_file.clear()
		_loaded = false
		_dirty = false

		if create_on_missing:
			if create_directory and not _ensure_directory():
				return ERR_CANT_CREATE

			var save_result: int = _config_file.save(
				config_path
			)

			if save_result != OK:
				_set_error(
					"Không thể tạo Config File: "
					+ error_string(save_result)
				)
				return save_result

			_loaded = true
			_dirty = false

			config_loaded.emit()

			_log(
				"Config Created: "
				+ config_path
			)

			return OK

		return ERR_FILE_NOT_FOUND

	var result: int = _config_file.load(
		config_path
	)

	if result != OK:
		_loaded = false

		_set_error(
			"Không thể Load Config: "
			+ error_string(result)
		)

		return result

	_loaded = true
	_dirty = false

	config_loaded.emit()

	_log(
		"Config Loaded: "
		+ config_path
	)

	return OK


func reload_config() -> int:
	if not _is_operational():
		return ERR_UNCONFIGURED

	return load_config()


func save_config() -> int:
	if not _is_operational():
		return ERR_UNCONFIGURED

	if config_path.is_empty():
		_set_error(
			"Config Path không được để trống"
		)
		return ERR_INVALID_PARAMETER

	if create_directory and not _ensure_directory():
		return ERR_CANT_CREATE

	var result: int = _config_file.save(
		config_path
	)

	if result != OK:
		_set_error(
			"Không thể Save Config: "
			+ error_string(result)
		)

		return result

	_loaded = true
	_dirty = false

	config_saved.emit()

	_log(
		"Config Saved: "
		+ config_path
	)

	return OK


func has_section(
	section: String
) -> bool:
	if not _is_operational():
		return false

	if section.is_empty():
		return false

	return _config_file.has_section(
		section
	)


func has_key(
	section: String,
	key: String
) -> bool:
	if not _is_operational():
		return false

	if section.is_empty() or key.is_empty():
		return false

	return _config_file.has_section_key(
		section,
		key
	)


func get_value(
	section: String,
	key: String,
	default_value: Variant = null
) -> Variant:
	if not _is_operational():
		return default_value

	if section.is_empty() or key.is_empty():
		return default_value

	return _config_file.get_value(
		section,
		key,
		default_value
	)


func set_value(
	section: String,
	key: String,
	value: Variant,
	save_immediately: bool = false
) -> bool:
	if not _is_operational():
		return false

	if section.is_empty():
		_set_error(
			"Config Section không được để trống"
		)
		return false

	if key.is_empty():
		_set_error(
			"Config Key không được để trống"
		)
		return false

	_config_file.set_value(
		section,
		key,
		value
	)

	_dirty = true

	config_changed.emit(
		section,
		key
	)

	config_section_changed.emit(
		section
	)

	if save_immediately:
		return save_config() == OK

	return true


func remove_key(
	section: String,
	key: String,
	save_immediately: bool = false
) -> bool:
	if not _is_operational():
		return false

	if not _config_file.has_section_key(
		section,
		key
	):
		return false

	_config_file.erase_section_key(
		section,
		key
	)

	_dirty = true

	config_changed.emit(
		section,
		key
	)

	config_section_changed.emit(
		section
	)

	if save_immediately:
		return save_config() == OK

	return true


func remove_section(
	section: String,
	save_immediately: bool = false
) -> bool:
	if not _is_operational():
		return false

	if not _config_file.has_section(
		section
	):
		return false

	_config_file.erase_section(
		section
	)

	_dirty = true

	config_section_changed.emit(
		section
	)

	if save_immediately:
		return save_config() == OK

	return true


func get_sections() -> PackedStringArray:
	if not _is_operational():
		return PackedStringArray()

	return _config_file.get_sections()


func get_section_keys(
	section: String
) -> PackedStringArray:
	if not _is_operational():
		return PackedStringArray()

	if not _config_file.has_section(
		section
	):
		return PackedStringArray()

	return _config_file.get_section_keys(
		section
	)


func get_section(
	section: String
) -> Dictionary:
	var result: Dictionary = {}

	if not _is_operational():
		return result

	if not _config_file.has_section(
		section
	):
		return result

	for key in _config_file.get_section_keys(
		section
	):
		result[key] = _config_file.get_value(
			section,
			key,
			null
		)

	return result


func set_section(
	section: String,
	values: Dictionary,
	save_immediately: bool = false
) -> bool:
	if not _is_operational():
		return false

	if section.is_empty():
		_set_error(
			"Config Section không được để trống"
		)
		return false

	for key in values.keys():
		var key_name: String = str(key)

		if key_name.is_empty():
			continue

		_config_file.set_value(
			section,
			key_name,
			values[key]
		)

		config_changed.emit(
			section,
			key_name
		)

	_dirty = true

	config_section_changed.emit(
		section
	)

	if save_immediately:
		return save_config() == OK

	return true


func replace_section(
	section: String,
	values: Dictionary,
	save_immediately: bool = false
) -> bool:
	if not _is_operational():
		return false

	if section.is_empty():
		_set_error(
			"Config Section không được để trống"
		)
		return false

	if _config_file.has_section(
		section
	):
		_config_file.erase_section(
			section
		)

	return set_section(
		section,
		values,
		save_immediately
	)


func clear_config(
	save_immediately: bool = false
) -> bool:
	if not _is_operational():
		return false

	_config_file.clear()

	_dirty = true

	if save_immediately:
		return save_config() == OK

	return true


func create_snapshot() -> Dictionary:
	var snapshot: Dictionary = {
		"sections": {}
	}

	var sections: Dictionary = {}

	for section in _config_file.get_sections():
		var section_data: Dictionary = {}

		for key in _config_file.get_section_keys(
			section
		):
			section_data[key] = _config_file.get_value(
				section,
				key,
				null
			)

		sections[section] = section_data

	snapshot["sections"] = sections

	return snapshot


func restore_snapshot(
	snapshot: Dictionary,
	clear_existing: bool = true,
	save_immediately: bool = false
) -> bool:
	if not _is_operational():
		return false

	if not snapshot.has(
		"sections"
	):
		return false

	var sections: Variant = snapshot[
		"sections"
	]

	if not sections is Dictionary:
		return false

	if clear_existing:
		_config_file.clear()

	for section in sections.keys():
		var section_name: String = str(
			section
		)

		var section_data: Variant = sections[
			section
		]

		if not section_data is Dictionary:
			return false

		for key in section_data.keys():
			_config_file.set_value(
				section_name,
				str(key),
				section_data[key]
			)

	_dirty = true

	if save_immediately:
		return save_config() == OK

	return true


func get_config_text() -> String:
	if not _is_operational():
		return ""

	return _config_file.encode_to_text()


func load_config_text(
	text: String
) -> int:
	if not _is_operational():
		return ERR_UNCONFIGURED

	if text.is_empty():
		_set_error(
			"Config Text không được để trống"
		)
		return ERR_INVALID_PARAMETER

	var result: int = _config_file.parse(
		text
	)

	if result != OK:
		_set_error(
			"Không thể Parse Config Text: "
			+ error_string(result)
		)

		return result

	_loaded = true
	_dirty = true

	config_loaded.emit()

	return OK


func is_loaded() -> bool:
	return _loaded


func is_dirty() -> bool:
	return _dirty


func get_config_path() -> String:
	return config_path


func get_absolute_config_path() -> String:
	return ProjectSettings.globalize_path(
		config_path
	)


func set_config_path(
	path: String,
	reload_after_change: bool = false
) -> bool:
	if path.is_empty():
		_set_error(
			"Config Path không được để trống"
		)
		return false

	config_path = path

	if not validate_path:
		return true

	if not _validate_path():
		return false

	if reload_after_change:
		return load_config() == OK

	return true


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
	return config_error


func _ensure_directory() -> bool:
	var directory: String = config_path.get_base_dir()

	if directory.is_empty():
		return true

	if DirAccess.dir_exists_absolute(
		ProjectSettings.globalize_path(
			directory
		)
	):
		return true

	var result: int = (
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(
				directory
			)
		)
	)

	if result != OK:
		_set_error(
			"Không thể tạo Config Directory: "
			+ directory
		)
		return false

	return true


func _validate_root() -> bool:
	config_error = ""

	if not is_inside_tree():
		config_error = (
			"Config không nằm trong SceneTree"
		)
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Config: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
			% [
				EXPECTED_NODE_NAME,
				name
			]
		)

	return true


func _validate_path() -> bool:
	config_error = ""

	if config_path.is_empty():
		config_error = (
			"Config Path không được để trống"
		)
		return false

	if config_path.contains(
		"\n"
	):
		config_error = (
			"Config Path không hợp lệ"
		)
		return false

	return true


func _is_operational() -> bool:
	return (
		state == State.READY
		or state == State.PAUSED
	)


func _set_error(
	message: String
) -> void:
	config_error = message

	_log_error(
		message
	)


func _fail(
	reason: String
) -> bool:
	state = State.FAILED
	config_error = reason

	config_failed.emit(
		reason
	)

	_log_error(
		reason
	)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING

	config_stopping.emit()

	if save_on_stop and _dirty:
		save_config()

	if clear_on_stop:
		_config_file.clear()
		_loaded = false
		_dirty = false

	state = State.STOPPED

	config_stopped.emit()

	_log(
		"Config Stopped"
	)


func _log(
	message: String
) -> void:
	if console_output:
		print(
			"[Config] ",
			message
		)


func _log_error(
	message: String
) -> void:
	push_error(
		"[Config] "
		+ message
) 
