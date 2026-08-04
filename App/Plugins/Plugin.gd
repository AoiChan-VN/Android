class_name AppPlugin
extends Node

signal plugin_loading(plugin_id: StringName)
signal plugin_loaded(plugin_id: StringName)
signal plugin_activated(plugin_id: StringName)
signal plugin_deactivated(plugin_id: StringName)
signal plugin_paused(plugin_id: StringName)
signal plugin_resumed(plugin_id: StringName)
signal plugin_unloading(plugin_id: StringName)
signal plugin_unloaded(plugin_id: StringName)
signal plugin_failed(
	plugin_id: StringName,
	reason: String
)

enum State {
	IDLE,
	LOADING,
	LOADED,
	ACTIVE,
	INACTIVE,
	PAUSED,
	UNLOADING,
	UNLOADED,
	FAILED
}

@export_group("Plugin")
@export var manifest: PluginManifest
@export var auto_load: bool = false
@export var auto_activate: bool = false
@export var console_output: bool = true

@export_group("Process")
@export var process_enabled: bool = false
@export var priority: int = 0

var state: State = State.IDLE
var plugin_error: String = ""
var elapsed_time: float = 0.0
var frame_count: int = 0

var _context: Dictionary = {}
var _dependency_check: Callable = Callable()
var _permission_check: Callable = Callable()


func _enter_tree() -> void:
	state = State.IDLE


func _ready() -> void:
	process_priority = priority
	set_process(process_enabled)

	if auto_load:
		if load_plugin({}) and auto_activate:
			activate_plugin()


func _process(delta: float) -> void:
	if state != State.ACTIVE:
		return

	elapsed_time += delta
	frame_count += 1

	_on_plugin_process(delta)


func _exit_tree() -> void:
	_shutdown()


func load_plugin(
	context: Dictionary = {}
) -> bool:
	if (
		state == State.LOADED
		or state == State.ACTIVE
		or state == State.INACTIVE
		or state == State.PAUSED
	):
		return true

	if state == State.LOADING or state == State.UNLOADING:
		return false

	if state == State.FAILED or state == State.UNLOADED:
		state = State.IDLE
		plugin_error = ""

	state = State.LOADING

	plugin_loading.emit(
		get_plugin_id()
	)

	if not _validate_plugin():
		return _fail(plugin_error)

	var missing_dependencies: Array[StringName] = (
		get_missing_dependencies()
	)

	if not missing_dependencies.is_empty():
		return _fail(
			"Dependency chưa sẵn sàng: "
			+ _join_ids(missing_dependencies)
		)

	var missing_permissions: Array[StringName] = (
		get_missing_permissions()
	)

	if not missing_permissions.is_empty():
		return _fail(
			"Permission chưa được cấp: "
			+ _join_ids(missing_permissions)
		)

	_context = context.duplicate(true)

	if not _on_plugin_load(_context):
		if plugin_error.is_empty():
			plugin_error = (
				"Plugin không thể Load"
			)

		return _fail(plugin_error)

	state = State.LOADED

	plugin_loaded.emit(
		get_plugin_id()
	)

	_log("Plugin Loaded")

	return true


func activate_plugin() -> bool:
	if state == State.ACTIVE:
		return true

	if state != State.LOADED and state != State.INACTIVE:
		return false

	var missing_dependencies: Array[StringName] = (
		get_missing_dependencies()
	)

	if not missing_dependencies.is_empty():
		_set_error(
			"Dependency chưa sẵn sàng: "
			+ _join_ids(missing_dependencies)
		)
		return false

	var missing_permissions: Array[StringName] = (
		get_missing_permissions()
	)

	if not missing_permissions.is_empty():
		_set_error(
			"Permission chưa được cấp: "
			+ _join_ids(missing_permissions)
		)
		return false

	if not _on_plugin_activate():
		if plugin_error.is_empty():
			plugin_error = (
				"Plugin không thể Activate"
			)

		return false

	state = State.ACTIVE

	plugin_activated.emit(
		get_plugin_id()
	)

	_log("Plugin Activated")

	return true


func deactivate_plugin() -> bool:
	if state == State.INACTIVE:
		return true

	if state != State.ACTIVE and state != State.PAUSED:
		return false

	if not _on_plugin_deactivate():
		if plugin_error.is_empty():
			plugin_error = (
				"Plugin không thể Deactivate"
			)

		return false

	state = State.INACTIVE

	plugin_deactivated.emit(
		get_plugin_id()
	)

	_log("Plugin Deactivated")

	return true


func pause_plugin() -> bool:
	if state != State.ACTIVE:
		return false

	if not _on_plugin_pause():
		return false

	state = State.PAUSED

	plugin_paused.emit(
		get_plugin_id()
	)

	_log("Plugin Paused")

	return true


func resume_plugin() -> bool:
	if state != State.PAUSED:
		return false

	var missing_dependencies: Array[StringName] = (
		get_missing_dependencies()
	)

	if not missing_dependencies.is_empty():
		_set_error(
			"Dependency chưa sẵn sàng: "
			+ _join_ids(missing_dependencies)
		)
		return false

	var missing_permissions: Array[StringName] = (
		get_missing_permissions()
	)

	if not missing_permissions.is_empty():
		_set_error(
			"Permission chưa được cấp: "
			+ _join_ids(missing_permissions)
		)
		return false

	if not _on_plugin_resume():
		return false

	state = State.ACTIVE

	plugin_resumed.emit(
		get_plugin_id()
	)

	_log("Plugin Resumed")

	return true


func unload_plugin() -> bool:
	if state == State.UNLOADED:
		return true

	if state == State.IDLE:
		state = State.UNLOADED
		return true

	if state == State.UNLOADING:
		return false

	if state == State.ACTIVE or state == State.PAUSED:
		if not deactivate_plugin():
			return false

	state = State.UNLOADING

	plugin_unloading.emit(
		get_plugin_id()
	)

	if not _on_plugin_unload():
		if plugin_error.is_empty():
			plugin_error = (
				"Plugin không thể Unload"
			)

		return _fail(plugin_error)

	_context.clear()

	state = State.UNLOADED

	plugin_unloaded.emit(
		get_plugin_id()
	)

	_log("Plugin Unloaded")

	return true


func retry(
	context: Dictionary = {}
) -> bool:
	if state != State.FAILED and state != State.UNLOADED:
		return false

	state = State.IDLE
	plugin_error = ""

	return load_plugin(context)


func block(
	reason: String
) -> bool:
	if reason.is_empty():
		return false

	if state == State.ACTIVE or state == State.PAUSED:
		_on_plugin_deactivate()

	if is_loaded():
		_on_plugin_unload()

	_context.clear()

	return _fail(reason)


func bind_dependency_check(
	check: Callable
) -> bool:
	if not check.is_valid():
		return false

	_dependency_check = check

	return true


func bind_permission_check(
	check: Callable
) -> bool:
	if not check.is_valid():
		return false

	_permission_check = check

	return true


func clear_checks() -> void:
	_dependency_check = Callable()
	_permission_check = Callable()


func get_missing_dependencies() -> Array[StringName]:
	var result: Array[StringName] = []

	if manifest == null:
		return result

	var dependencies: Array[StringName] = (
		manifest.get_dependencies()
	)

	if dependencies.is_empty():
		return result

	if not _dependency_check.is_valid():
		result.assign(dependencies)
		return result

	for dependency_id in dependencies:
		var available: bool = bool(
			_dependency_check.call(
				dependency_id
			)
		)

		if not available:
			result.append(
				dependency_id
			)

	return result


func get_missing_permissions() -> Array[StringName]:
	var result: Array[StringName] = []

	if manifest == null:
		return result

	var permissions: Array[StringName] = (
		manifest.get_permissions()
	)

	if permissions.is_empty():
		return result

	if not _permission_check.is_valid():
		result.assign(permissions)
		return result

	for permission_id in permissions:
		var granted: bool = bool(
			_permission_check.call(
				permission_id
			)
		)

		if not granted:
			result.append(
				permission_id
			)

	return result


func get_plugin_id() -> StringName:
	if manifest == null:
		return &""

	return manifest.get_id()


func get_manifest() -> PluginManifest:
	return manifest


func get_version() -> String:
	if manifest == null:
		return ""

	return manifest.get_version()


func get_api_version() -> String:
	if manifest == null:
		return ""

	return manifest.get_api_version()


func get_dependencies() -> Array[StringName]:
	if manifest == null:
		return []

	return manifest.get_dependencies()


func get_capabilities() -> Array[StringName]:
	if manifest == null:
		return []

	return manifest.get_capabilities()


func get_permissions() -> Array[StringName]:
	if manifest == null:
		return []

	return manifest.get_permissions()


func has_dependency(
	dependency_id: StringName
) -> bool:
	if manifest == null:
		return false

	return manifest.has_dependency(
		dependency_id
	)


func has_capability(
	capability_id: StringName
) -> bool:
	if manifest == null:
		return false

	return manifest.has_capability(
		capability_id
	)


func requires_permission(
	permission_id: StringName
) -> bool:
	if manifest == null:
		return false

	return manifest.requires_permission(
		permission_id
	)


func get_context() -> Dictionary:
	return _context.duplicate(true)


func get_state() -> State:
	return state


func get_error() -> String:
	return plugin_error


func get_elapsed_time() -> float:
	return elapsed_time


func get_frame_count() -> int:
	return frame_count


func is_loaded() -> bool:
	return (
		state == State.LOADED
		or state == State.ACTIVE
		or state == State.INACTIVE
		or state == State.PAUSED
	)


func is_active() -> bool:
	return state == State.ACTIVE


func is_inactive() -> bool:
	return state == State.INACTIVE


func is_paused() -> bool:
	return state == State.PAUSED


func is_unloaded() -> bool:
	return state == State.UNLOADED


func is_failed() -> bool:
	return state == State.FAILED


func set_processing(
	enabled: bool
) -> void:
	process_enabled = enabled
	set_process(enabled)


func _validate_plugin() -> bool:
	plugin_error = ""

	if not is_inside_tree():
		plugin_error = (
			"Plugin không nằm trong SceneTree"
		)
		return false

	if manifest == null:
		plugin_error = (
			"Plugin Manifest không hợp lệ"
		)
		return false

	if not manifest.validate():
		plugin_error = manifest.get_error()
		return false

	return true


func _on_plugin_load(
	_context_data: Dictionary
) -> bool:
	return true


func _on_plugin_activate() -> bool:
	return true


func _on_plugin_deactivate() -> bool:
	return true


func _on_plugin_pause() -> bool:
	return true


func _on_plugin_resume() -> bool:
	return true


func _on_plugin_process(
	_delta: float
) -> void:
	return


func _on_plugin_unload() -> bool:
	return true


func _set_error(
	message: String
) -> void:
	plugin_error = message
	_log_error(message)


func _fail(
	reason: String
) -> bool:
	state = State.FAILED
	plugin_error = reason

	plugin_failed.emit(
		get_plugin_id(),
		reason
	)

	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.UNLOADED:
		return

	if state == State.IDLE:
		return

	unload_plugin()


func _join_ids(
	ids: Array[StringName]
) -> String:
	var values: PackedStringArray = []

	for id in ids:
		values.append(
			String(id)
		)

	return ", ".join(values)


func _log(
	message: String
) -> void:
	if console_output:
		print(
			"[Plugin:",
			get_plugin_id(),
			"] ",
			message
		)


func _log_error(
	message: String
) -> void:
	push_error(
		"[Plugin:%s] %s"
		% [
			get_plugin_id(),
			message
		]
	) 
