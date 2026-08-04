class_name Plugins
extends Node

signal plugins_started
signal plugins_ready
signal plugins_paused
signal plugins_resumed
signal plugins_stopping
signal plugins_stopped
signal plugins_failed(reason: String)

signal plugin_registered(plugin_id: StringName)
signal plugin_unregistered(plugin_id: StringName)
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

signal permission_granted(permission_id: StringName)
signal permission_revoked(permission_id: StringName)

enum State {
	IDLE,
	STARTING,
	READY,
	PAUSED,
	STOPPING,
	STOPPED,
	FAILED
}

const EXPECTED_NODE_NAME: StringName = &"Plugins"

@export_group("Plugins")
@export var auto_start: bool = true
@export var scan_children: bool = true
@export var load_registered: bool = true
@export var activate_registered: bool = true
@export var stop_on_exit: bool = true
@export var retry_on_change: bool = true
@export var strict_start: bool = false
@export var free_on_remove: bool = false
@export var console_output: bool = true

@export_group("Contract")
@export var plugin_api_version: String = "1.0.0"
@export var granted_permissions: Array[StringName] = []

@export_group("Validation")
@export var validate_root: bool = true

var state: State = State.IDLE
var plugins_error: String = ""

var _plugins: Dictionary = {}
var _plugin_order: Array[StringName] = []
var _loaded_order: Array[StringName] = []


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
		plugins_error = ""

	if validate_root and not _validate_root():
		return _fail(plugins_error)

	if not _validate_api_version():
		return _fail(plugins_error)

	if not _validate_permissions():
		return _fail(plugins_error)

	state = State.STARTING

	plugins_started.emit()

	var success: bool = true

	if load_registered:
		success = start_all()

	if strict_start and not success:
		return _fail(
			"Một hoặc nhiều Plugin không thể khởi động"
		)

	state = State.READY

	plugins_ready.emit()

	_log("Plugins Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	var success: bool = pause_all()

	if strict_start and not success:
		return false

	state = State.PAUSED

	plugins_paused.emit()

	_log("Plugins Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	var success: bool = resume_all()

	if strict_start and not success:
		return false

	state = State.READY

	plugins_resumed.emit()

	_log("Plugins Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func add_plugin(
	plugin: AppPlugin
) -> bool:
	if not is_instance_valid(plugin):
		_log_error(
			"Plugin không hợp lệ"
		)
		return false

	if (
		plugin.get_parent() != null
		and plugin.get_parent() != self
	):
		_log_error(
			"Plugin đang thuộc Node khác"
		)
		return false

	if plugin.get_parent() == null:
		add_child(plugin)

	return register_plugin(plugin)


func register_plugin(
	plugin: AppPlugin
) -> bool:
	if not is_instance_valid(plugin):
		_log_error(
			"Plugin không hợp lệ"
		)
		return false

	if plugin.get_parent() != self:
		_log_error(
			"Plugin phải là Child trực tiếp của Plugins"
		)
		return false

	var manifest: PluginManifest = (
		plugin.get_manifest()
	)

	if manifest == null:
		_log_error(
			"Plugin Manifest không hợp lệ"
		)
		return false

	if not manifest.validate():
		_log_error(
			manifest.get_error()
		)
		return false

	if not is_api_compatible(
		manifest.get_api_version()
	):
		_log_error(
			"Plugin API không tương thích: "
			+ manifest.get_api_version()
		)
		return false

	var plugin_id: StringName = (
		manifest.get_id()
	)

	if _plugins.has(plugin_id):
		_log_error(
			"Plugin ID đã tồn tại: "
			+ String(plugin_id)
		)
		return false

	_plugins[plugin_id] = plugin
	_plugin_order.append(plugin_id)

	plugin.bind_dependency_check(
		_is_dependency_ready
	)

	plugin.bind_permission_check(
		has_permission
	)

	_connect_plugin(plugin)

	plugin_registered.emit(
		plugin_id
	)

	_log(
		"Plugin Registered: "
		+ String(plugin_id)
	)

	if state == State.READY and load_registered:
		var success: bool = start_plugin(
			plugin_id
		)

		if retry_on_change:
			retry_failed()

		if strict_start and not success:
			return false

	return true


func replace_plugin(
	plugin: AppPlugin
) -> bool:
	if not is_instance_valid(plugin):
		return false

	var plugin_id: StringName = (
		plugin.get_plugin_id()
	)

	if plugin_id.is_empty():
		return false

	if _plugins.has(plugin_id):
		if not unregister_plugin(plugin_id):
			return false

	return add_plugin(plugin)


func unregister_plugin(
	plugin_id: StringName
) -> bool:
	var plugin: AppPlugin = get_plugin(
		plugin_id
	)

	if plugin == null:
		return false

	if not plugin.is_unloaded():
		plugin.unload_plugin()

	_disconnect_plugin(plugin)
	plugin.clear_checks()

	if plugin.get_parent() == self:
		remove_child(plugin)

	_plugins.erase(plugin_id)
	_plugin_order.erase(plugin_id)
	_loaded_order.erase(plugin_id)

	plugin_unregistered.emit(
		plugin_id
	)

	_block_dependents(
		plugin_id,
		"Dependency đã bị gỡ bỏ"
	)

	_log(
		"Plugin Unregistered: "
		+ String(plugin_id)
	)

	if free_on_remove and is_instance_valid(plugin):
		plugin.queue_free()

	return true


func load_manifest(
	manifest_path: String
) -> PluginManifest:
	if manifest_path.is_empty():
		_set_error(
			"Plugin Manifest Path không được để trống"
		)
		return null

	if not ResourceLoader.exists(
		manifest_path
	):
		_set_error(
			"Plugin Manifest không tồn tại: "
			+ manifest_path
		)
		return null

	var resource: Resource = ResourceLoader.load(
		manifest_path
	)

	if not resource is PluginManifest:
		_set_error(
			"Resource không phải PluginManifest: "
			+ manifest_path
		)
		return null

	var manifest: PluginManifest = resource

	if not manifest.validate():
		_set_error(
			manifest.get_error()
		)
		return null

	return manifest


func instantiate_manifest(
	manifest: PluginManifest
) -> AppPlugin:
	if manifest == null:
		_set_error(
			"Plugin Manifest không hợp lệ"
		)
		return null

	if not manifest.validate():
		_set_error(
			manifest.get_error()
		)
		return null

	if not is_api_compatible(
		manifest.get_api_version()
	):
		_set_error(
			"Plugin API không tương thích: "
			+ manifest.get_api_version()
		)
		return null

	var main_scene: String = (
		manifest.get_main_scene()
	)

	if main_scene.is_empty():
		_set_error(
			"Plugin Main Scene không được để trống"
		)
		return null

	if not ResourceLoader.exists(
		main_scene,
		"PackedScene"
	):
		_set_error(
			"Plugin Main Scene không tồn tại: "
			+ main_scene
		)
		return null

	var resource: Resource = ResourceLoader.load(
		main_scene,
		"PackedScene"
	)

	if not resource is PackedScene:
		_set_error(
			"Plugin Main Scene không phải PackedScene"
		)
		return null

	var scene: PackedScene = resource
	var instance: Node = scene.instantiate()

	if not instance is AppPlugin:
		instance.free()

		_set_error(
			"Plugin Scene Root phải kế thừa AppPlugin"
		)
		return null

	var plugin: AppPlugin = instance

	plugin.manifest = manifest.duplicate_manifest()

	return plugin


func register_manifest(
	manifest: PluginManifest
) -> bool:
	var plugin: AppPlugin = instantiate_manifest(
		manifest
	)

	if plugin == null:
		return false

	if not add_plugin(plugin):
		plugin.free()
		return false

	return true


func register_manifest_path(
	manifest_path: String
) -> bool:
	var manifest: PluginManifest = load_manifest(
		manifest_path
	)

	if manifest == null:
		return false

	return register_manifest(
		manifest
	)


func get_plugin(
	plugin_id: StringName
) -> AppPlugin:
	if not _plugins.has(plugin_id):
		return null

	var plugin: AppPlugin = _plugins[
		plugin_id
	]

	if not is_instance_valid(plugin):
		_plugins.erase(plugin_id)
		_plugin_order.erase(plugin_id)
		_loaded_order.erase(plugin_id)
		return null

	return plugin


func get_manifest(
	plugin_id: StringName
) -> PluginManifest:
	var plugin: AppPlugin = get_plugin(
		plugin_id
	)

	if plugin == null:
		return null

	return plugin.get_manifest()


func has_plugin(
	plugin_id: StringName
) -> bool:
	return get_plugin(
		plugin_id
	) != null


func get_plugin_count() -> int:
	return _plugins.size()


func get_plugin_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for plugin_id in _plugin_order:
		if _plugins.has(plugin_id):
			result.append(plugin_id)

	return result


func get_loaded_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for plugin_id in get_plugin_ids():
		var plugin: AppPlugin = get_plugin(
			plugin_id
		)

		if plugin != null and plugin.is_loaded():
			result.append(plugin_id)

	return result


func get_active_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for plugin_id in get_plugin_ids():
		var plugin: AppPlugin = get_plugin(
			plugin_id
		)

		if plugin != null and plugin.is_active():
			result.append(plugin_id)

	return result


func get_failed_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for plugin_id in get_plugin_ids():
		var plugin: AppPlugin = get_plugin(
			plugin_id
		)

		if plugin != null and plugin.is_failed():
			result.append(plugin_id)

	return result


func get_ids_by_capability(
	capability_id: StringName
) -> Array[StringName]:
	var result: Array[StringName] = []

	if capability_id.is_empty():
		return result

	for plugin_id in get_plugin_ids():
		var plugin: AppPlugin = get_plugin(
			plugin_id
		)

		if (
			plugin != null
			and plugin.has_capability(
				capability_id
			)
		):
			result.append(plugin_id)

	return result


func get_dependents(
	plugin_id: StringName
) -> Array[StringName]:
	var result: Array[StringName] = []

	for target_id in get_plugin_ids():
		var plugin: AppPlugin = get_plugin(
			target_id
		)

		if (
			plugin != null
			and plugin.has_dependency(
				plugin_id
			)
		):
			result.append(target_id)

	return result


func start_plugin(
	plugin_id: StringName,
	context: Dictionary = {}
) -> bool:
	var plugin: AppPlugin = get_plugin(
		plugin_id
	)

	if plugin == null:
		return false

	if not plugin.load_plugin(context):
		return false

	_add_loaded(plugin_id)

	var manifest: PluginManifest = (
		plugin.get_manifest()
	)

	if (
		activate_registered
		and manifest != null
		and manifest.enabled_by_default
	):
		if not plugin.activate_plugin():
			return false

	if retry_on_change:
		retry_failed()

	return true


func load_plugin(
	plugin_id: StringName,
	context: Dictionary = {}
) -> bool:
	var plugin: AppPlugin = get_plugin(
		plugin_id
	)

	if plugin == null:
		return false

	var success: bool = plugin.load_plugin(
		context
	)

	if success:
		_add_loaded(plugin_id)

	return success


func activate_plugin(
	plugin_id: StringName
) -> bool:
	var plugin: AppPlugin = get_plugin(
		plugin_id
	)

	if plugin == null:
		return false

	if not plugin.is_loaded():
		if not plugin.load_plugin({}):
			return false

		_add_loaded(plugin_id)

	var success: bool = plugin.activate_plugin()

	if success and retry_on_change:
		retry_failed()

	return success


func deactivate_plugin(
	plugin_id: StringName
) -> bool:
	var plugin: AppPlugin = get_plugin(
		plugin_id
	)

	if plugin == null:
		return false

	var success: bool = plugin.deactivate_plugin()

	if success:
		_block_dependents(
			plugin_id,
			"Dependency đã bị Deactivate"
		)

	return success


func pause_plugin(
	plugin_id: StringName
) -> bool:
	var plugin: AppPlugin = get_plugin(
		plugin_id
	)

	if plugin == null:
		return false

	return plugin.pause_plugin()


func resume_plugin(
	plugin_id: StringName
) -> bool:
	var plugin: AppPlugin = get_plugin(
		plugin_id
	)

	if plugin == null:
		return false

	var success: bool = plugin.resume_plugin()

	if success and retry_on_change:
		retry_failed()

	return success


func unload_plugin(
	plugin_id: StringName
) -> bool:
	var plugin: AppPlugin = get_plugin(
		plugin_id
	)

	if plugin == null:
		return false

	var success: bool = plugin.unload_plugin()

	if success:
		_loaded_order.erase(plugin_id)

		_block_dependents(
			plugin_id,
			"Dependency đã bị Unload"
		)

	return success


func retry_plugin(
	plugin_id: StringName,
	context: Dictionary = {}
) -> bool:
	var plugin: AppPlugin = get_plugin(
		plugin_id
	)

	if plugin == null:
		return false

	var success: bool = plugin.retry(
		context
	)

	if not success:
		return false

	_add_loaded(plugin_id)

	var manifest: PluginManifest = (
		plugin.get_manifest()
	)

	if (
		activate_registered
		and manifest != null
		and manifest.enabled_by_default
	):
		success = plugin.activate_plugin()

	return success


func start_all() -> bool:
	var pending: Array[StringName] = (
		get_plugin_ids()
	)

	var success: bool = true
	var progress: bool = true

	while progress and not pending.is_empty():
		progress = false

		var next: Array[StringName] = []

		for plugin_id in pending:
			var plugin: AppPlugin = get_plugin(
				plugin_id
			)

			if plugin == null:
				success = false
				continue

			if plugin.is_loaded():
				_add_loaded(plugin_id)
				progress = true
				continue

			if not plugin.get_missing_dependencies().is_empty():
				next.append(plugin_id)
				continue

			if not plugin.get_missing_permissions().is_empty():
				success = false
				continue

			if start_plugin(
				plugin_id,
				{}
			):
				progress = true
			else:
				success = false

		pending = next

	if not pending.is_empty():
		success = false

		for plugin_id in pending:
			var plugin: AppPlugin = get_plugin(
				plugin_id
			)

			if plugin == null:
				continue

			plugin.block(
				"Dependency thiếu hoặc bị vòng lặp: "
				+ _join_ids(
					plugin.get_missing_dependencies()
				)
			)

	return success


func activate_all() -> bool:
	var success: bool = true

	for plugin_id in get_loaded_ids():
		var plugin: AppPlugin = get_plugin(
			plugin_id
		)

		if plugin == null:
			continue

		if plugin.is_active():
			continue

		if not plugin.activate_plugin():
			success = false

	return success


func deactivate_all() -> bool:
	var success: bool = true
	var plugin_ids: Array[StringName] = (
		get_loaded_ids()
	)

	plugin_ids.reverse()

	for plugin_id in plugin_ids:
		var plugin: AppPlugin = get_plugin(
			plugin_id
		)

		if plugin == null:
			continue

		if (
			plugin.is_active()
			or plugin.is_paused()
		):
			if not plugin.deactivate_plugin():
				success = false

	return success


func pause_all() -> bool:
	var success: bool = true
	var plugin_ids: Array[StringName] = (
		get_active_ids()
	)

	plugin_ids.reverse()

	for plugin_id in plugin_ids:
		var plugin: AppPlugin = get_plugin(
			plugin_id
		)

		if plugin == null:
			continue

		if not plugin.pause_plugin():
			success = false

	return success


func resume_all() -> bool:
	var success: bool = true

	for plugin_id in _loaded_order:
		var plugin: AppPlugin = get_plugin(
			plugin_id
		)

		if plugin == null:
			continue

		if (
			plugin.is_paused()
			and not plugin.resume_plugin()
		):
			success = false

	return success


func retry_failed() -> bool:
	var success: bool = true
	var progress: bool = true

	while progress:
		progress = false

		for plugin_id in get_failed_ids():
			var plugin: AppPlugin = get_plugin(
				plugin_id
			)

			if plugin == null:
				continue

			if not plugin.get_missing_dependencies().is_empty():
				continue

			if not plugin.get_missing_permissions().is_empty():
				continue

			if retry_plugin(
				plugin_id,
				{}
			):
				progress = true
			else:
				success = false

	return success


func unload_all() -> bool:
	var success: bool = true
	var handled: Dictionary = {}
	var plugin_ids: Array[StringName] = []

	plugin_ids.assign(_loaded_order)
	plugin_ids.reverse()

	for plugin_id in plugin_ids:
		var plugin: AppPlugin = get_plugin(
			plugin_id
		)

		if plugin == null:
			continue

		handled[plugin_id] = true

		if not plugin.unload_plugin():
			success = false

	var all_ids: Array[StringName] = (
		get_plugin_ids()
	)

	all_ids.reverse()

	for plugin_id in all_ids:
		if handled.has(plugin_id):
			continue

		var plugin: AppPlugin = get_plugin(
			plugin_id
		)

		if plugin == null:
			continue

		if (
			not plugin.is_unloaded()
			and not plugin.unload_plugin()
		):
			success = false

	_loaded_order.clear()

	return success


func grant_permission(
	permission_id: StringName
) -> bool:
	if permission_id.is_empty():
		return false

	if granted_permissions.has(
		permission_id
	):
		return true

	granted_permissions.append(
		permission_id
	)

	permission_granted.emit(
		permission_id
	)

	_log(
		"Permission Granted: "
		+ String(permission_id)
	)

	if retry_on_change:
		retry_failed()

	return true


func revoke_permission(
	permission_id: StringName
) -> bool:
	if not granted_permissions.has(
		permission_id
	):
		return false

	granted_permissions.erase(
		permission_id
	)

	permission_revoked.emit(
		permission_id
	)

	for plugin_id in get_plugin_ids():
		var plugin: AppPlugin = get_plugin(
			plugin_id
		)

		if (
			plugin != null
			and plugin.requires_permission(
				permission_id
			)
			and plugin.is_loaded()
		):
			plugin.block(
				"Permission đã bị thu hồi: "
				+ String(permission_id)
			)

			_loaded_order.erase(
				plugin_id
			)

	_log(
		"Permission Revoked: "
		+ String(permission_id)
	)

	return true


func has_permission(
	permission_id: StringName
) -> bool:
	return granted_permissions.has(
		permission_id
	)


func get_permissions() -> Array[StringName]:
	var result: Array[StringName] = []

	result.assign(
		granted_permissions
	)

	return result


func get_missing_permissions(
	plugin_id: StringName
) -> Array[StringName]:
	var plugin: AppPlugin = get_plugin(
		plugin_id
	)

	if plugin == null:
		return []

	return plugin.get_missing_permissions()


func is_api_compatible(
	required_version: String
) -> bool:
	var host_major: int = _get_major(
		plugin_api_version
	)

	var required_major: int = _get_major(
		required_version
	)

	if host_major < 0 or required_major < 0:
		return false

	return host_major == required_major


func create_snapshot() -> Dictionary:
	var records: Array = []

	for plugin_id in get_plugin_ids():
		var plugin: AppPlugin = get_plugin(
			plugin_id
		)

		if plugin == null:
			continue

		var manifest: PluginManifest = (
			plugin.get_manifest()
		)

		records.append(
			{
				"plugin_id": String(plugin_id),
				"state": int(plugin.get_state()),
				"error": plugin.get_error(),
				"manifest": (
					manifest.to_dictionary()
					if manifest != null
					else {}
				)
			}
		)

	return {
		"api_version": plugin_api_version,
		"permissions": _ids_to_strings(
			granted_permissions
		),
		"plugins": records
	}


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
	return plugins_error


func _register_children() -> void:
	for child in get_children():
		if child is AppPlugin:
			register_plugin(child)


func _connect_plugin(
	plugin: AppPlugin
) -> void:
	if not plugin.plugin_loading.is_connected(
		_on_plugin_loading
	):
		plugin.plugin_loading.connect(
			_on_plugin_loading
		)

	if not plugin.plugin_loaded.is_connected(
		_on_plugin_loaded
	):
		plugin.plugin_loaded.connect(
			_on_plugin_loaded
		)

	if not plugin.plugin_activated.is_connected(
		_on_plugin_activated
	):
		plugin.plugin_activated.connect(
			_on_plugin_activated
		)

	if not plugin.plugin_deactivated.is_connected(
		_on_plugin_deactivated
	):
		plugin.plugin_deactivated.connect(
			_on_plugin_deactivated
		)

	if not plugin.plugin_paused.is_connected(
		_on_plugin_paused
	):
		plugin.plugin_paused.connect(
			_on_plugin_paused
		)

	if not plugin.plugin_resumed.is_connected(
		_on_plugin_resumed
	):
		plugin.plugin_resumed.connect(
			_on_plugin_resumed
		)

	if not plugin.plugin_unloading.is_connected(
		_on_plugin_unloading
	):
		plugin.plugin_unloading.connect(
			_on_plugin_unloading
		)

	if not plugin.plugin_unloaded.is_connected(
		_on_plugin_unloaded
	):
		plugin.plugin_unloaded.connect(
			_on_plugin_unloaded
		)

	if not plugin.plugin_failed.is_connected(
		_on_plugin_failed
	):
		plugin.plugin_failed.connect(
			_on_plugin_failed
		)


func _disconnect_plugin(
	plugin: AppPlugin
) -> void:
	if not is_instance_valid(plugin):
		return

	if plugin.plugin_loading.is_connected(
		_on_plugin_loading
	):
		plugin.plugin_loading.disconnect(
			_on_plugin_loading
		)

	if plugin.plugin_loaded.is_connected(
		_on_plugin_loaded
	):
		plugin.plugin_loaded.disconnect(
			_on_plugin_loaded
		)

	if plugin.plugin_activated.is_connected(
		_on_plugin_activated
	):
		plugin.plugin_activated.disconnect(
			_on_plugin_activated
		)

	if plugin.plugin_deactivated.is_connected(
		_on_plugin_deactivated
	):
		plugin.plugin_deactivated.disconnect(
			_on_plugin_deactivated
		)

	if plugin.plugin_paused.is_connected(
		_on_plugin_paused
	):
		plugin.plugin_paused.disconnect(
			_on_plugin_paused
		)

	if plugin.plugin_resumed.is_connected(
		_on_plugin_resumed
	):
		plugin.plugin_resumed.disconnect(
			_on_plugin_resumed
		)

	if plugin.plugin_unloading.is_connected(
		_on_plugin_unloading
	):
		plugin.plugin_unloading.disconnect(
			_on_plugin_unloading
		)

	if plugin.plugin_unloaded.is_connected(
		_on_plugin_unloaded
	):
		plugin.plugin_unloaded.disconnect(
			_on_plugin_unloaded
		)

	if plugin.plugin_failed.is_connected(
		_on_plugin_failed
	):
		plugin.plugin_failed.disconnect(
			_on_plugin_failed
		)


func _on_plugin_loading(
	plugin_id: StringName
) -> void:
	plugin_loading.emit(
		plugin_id
	)


func _on_plugin_loaded(
	plugin_id: StringName
) -> void:
	_add_loaded(plugin_id)

	plugin_loaded.emit(
		plugin_id
	)


func _on_plugin_activated(
	plugin_id: StringName
) -> void:
	plugin_activated.emit(
		plugin_id
	)


func _on_plugin_deactivated(
	plugin_id: StringName
) -> void:
	plugin_deactivated.emit(
		plugin_id
	)


func _on_plugin_paused(
	plugin_id: StringName
) -> void:
	plugin_paused.emit(
		plugin_id
	)


func _on_plugin_resumed(
	plugin_id: StringName
) -> void:
	plugin_resumed.emit(
		plugin_id
	)


func _on_plugin_unloading(
	plugin_id: StringName
) -> void:
	plugin_unloading.emit(
		plugin_id
	)


func _on_plugin_unloaded(
	plugin_id: StringName
) -> void:
	_loaded_order.erase(
		plugin_id
	)

	plugin_unloaded.emit(
		plugin_id
	)


func _on_plugin_failed(
	plugin_id: StringName,
	reason: String
) -> void:
	_loaded_order.erase(
		plugin_id
	)

	plugin_failed.emit(
		plugin_id,
		reason
	)

	_block_dependents(
		plugin_id,
		"Dependency đã Failed"
	)

	_log_error(
		"Plugin Failed ["
		+ String(plugin_id)
		+ "]: "
		+ reason
	)


func _is_dependency_ready(
	plugin_id: StringName
) -> bool:
	var plugin: AppPlugin = get_plugin(
		plugin_id
	)

	return (
		plugin != null
		and plugin.is_loaded()
		and not plugin.is_failed()
	)


func _block_dependents(
	plugin_id: StringName,
	reason: String
) -> void:
	for dependent_id in get_dependents(
		plugin_id
	):
		var plugin: AppPlugin = get_plugin(
			dependent_id
		)

		if plugin == null:
			continue

		if plugin.is_loaded():
			plugin.block(
				reason
				+ ": "
				+ String(plugin_id)
			)

			_loaded_order.erase(
				dependent_id
			)


func _add_loaded(
	plugin_id: StringName
) -> void:
	if not _loaded_order.has(
		plugin_id
	):
		_loaded_order.append(
			plugin_id
		)


func _validate_root() -> bool:
	plugins_error = ""

	if not is_inside_tree():
		plugins_error = (
			"Plugins không nằm trong SceneTree"
		)
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Plugins: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
			% [
				EXPECTED_NODE_NAME,
				name
			]
		)

	return true


func _validate_api_version() -> bool:
	plugins_error = ""

	if _get_major(plugin_api_version) < 0:
		plugins_error = (
			"Plugin API Version không hợp lệ: "
			+ plugin_api_version
		)
		return false

	return true


func _validate_permissions() -> bool:
	var found: Dictionary = {}

	for permission_id in granted_permissions:
		if permission_id.is_empty():
			plugins_error = (
				"Granted Permission không được để trống"
			)
			return false

		if found.has(permission_id):
			plugins_error = (
				"Granted Permission bị trùng: "
				+ String(permission_id)
			)
			return false

		found[permission_id] = true

	return true


func _get_major(
	version: String
) -> int:
	if version.is_empty():
		return -1

	var parts: PackedStringArray = version.split(
		".",
		false
	)

	if parts.is_empty():
		return -1

	if not parts[0].is_valid_int():
		return -1

	return parts[0].to_int()


func _join_ids(
	ids: Array[StringName]
) -> String:
	var values: PackedStringArray = []

	for id in ids:
		values.append(
			String(id)
		)

	return ", ".join(values)


func _ids_to_strings(
	ids: Array[StringName]
) -> PackedStringArray:
	var result: PackedStringArray = []

	for id in ids:
		result.append(
			String(id)
		)

	return result


func _set_error(
	message: String
) -> void:
	plugins_error = message
	_log_error(message)


func _fail(
	reason: String
) -> bool:
	state = State.FAILED
	plugins_error = reason

	plugins_failed.emit(
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

	plugins_stopping.emit()

	if stop_on_exit:
		unload_all()

	state = State.STOPPED

	plugins_stopped.emit()

	_log("Plugins Stopped")


func _log(
	message: String
) -> void:
	if console_output:
		print(
			"[Plugins] ",
			message
		)


func _log_error(
	message: String
) -> void:
	push_error(
		"[Plugins] "
		+ message
	) 
