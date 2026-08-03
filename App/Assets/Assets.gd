class_name Assets
extends Node

signal assets_started
signal assets_ready
signal assets_paused
signal assets_resumed
signal assets_stopping
signal assets_stopped
signal assets_failed(reason: String)

signal asset_registered(
	asset_id: StringName,
	asset_path: String
)

signal asset_unregistered(
	asset_id: StringName,
	asset_path: String
)

signal asset_loaded(
	asset_id: StringName,
	asset_path: String
)

signal asset_unloaded(
	asset_id: StringName,
	asset_path: String
)

signal asset_saved(
	asset_id: StringName,
	asset_path: String
)

signal asset_changed(
	asset_id: StringName,
	asset_path: String
)

signal asset_instantiated(
	asset_id: StringName,
	instance: Node
)

signal asset_load_failed(
	asset_id: StringName,
	asset_path: String,
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

const EXPECTED_NODE_NAME: StringName = &"Assets"

@export_group("Assets")
@export var auto_start: bool = true
@export var validate_paths: bool = true
@export var keep_loaded: bool = true
@export var scan_on_start: bool = false
@export var base_path: String = "res://App/Assets"
@export var console_output: bool = true
@export var clear_on_stop: bool = false

@export_group("Validation")
@export var validate_root: bool = true

var state: State = State.IDLE
var assets_error: String = ""

var _entries: Dictionary = {}
var _asset_order: Array[StringName] = []


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
		assets_error = ""

	if validate_root and not _validate_root():
		return _fail(assets_error)

	if not _validate_base_path():
		return _fail(assets_error)

	state = State.STARTING

	assets_started.emit()

	if scan_on_start:
		if not scan_assets(base_path):
			return _fail(assets_error)

	state = State.READY

	assets_ready.emit()

	_log("Assets Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	state = State.PAUSED

	assets_paused.emit()

	_log("Assets Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	state = State.READY

	assets_resumed.emit()

	_log("Assets Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func register_asset(
	asset_id: StringName,
	asset_path: String,
	category: StringName = &"",
	type_hint: String = "",
	replace_existing: bool = false
) -> bool:
	if not _is_operational():
		return false

	if asset_id.is_empty():
		_set_error(
			"Asset ID không được để trống"
		)
		return false

	if asset_path.is_empty():
		_set_error(
			"Asset Path không được để trống"
		)
		return false

	if validate_paths and not ResourceLoader.exists(
		asset_path,
		type_hint
	):
		_set_error(
			"Asset Path không tồn tại: "
			+ asset_path
		)
		return false

	if _entries.has(asset_id):
		if not replace_existing:
			_set_error(
				"Asset ID đã tồn tại: "
				+ String(asset_id)
			)
			return false

		unregister_asset(asset_id)

	var entry := AssetEntry.new()

	if not entry.configure(
		asset_id,
		asset_path,
		category,
		type_hint
	):
		_set_error(
			"Không thể tạo Asset Entry"
		)
		return false

	_entries[asset_id] = entry
	_asset_order.append(asset_id)

	asset_registered.emit(
		asset_id,
		asset_path
	)

	_log(
		"Asset Registered: "
		+ String(asset_id)
	)

	return true


func register_loaded_asset(
	asset_id: StringName,
	resource: Resource,
	asset_path: String = "",
	category: StringName = &"",
	replace_existing: bool = false
) -> bool:
	if not _is_operational():
		return false

	if asset_id.is_empty():
		_set_error(
			"Asset ID không được để trống"
		)
		return false

	if resource == null:
		_set_error(
			"Asset Resource không hợp lệ"
		)
		return false

	var path: String = asset_path

	if path.is_empty():
		path = resource.resource_path

	if path.is_empty():
		_set_error(
			"Asset Path không được để trống"
		)
		return false

	if _entries.has(asset_id):
		if not replace_existing:
			_set_error(
				"Asset ID đã tồn tại: "
				+ String(asset_id)
			)
			return false

		unregister_asset(asset_id)

	var entry := AssetEntry.new()

	if not entry.configure(
		asset_id,
		path,
		category
	):
		_set_error(
			"Không thể tạo Asset Entry"
		)
		return false

	if not entry.set_resource(resource):
		_set_error(
			"Không thể gán Asset Resource"
		)
		return false

	_entries[asset_id] = entry
	_asset_order.append(asset_id)

	asset_registered.emit(
		asset_id,
		path
	)

	asset_loaded.emit(
		asset_id,
		path
	)

	_log(
		"Loaded Asset Registered: "
		+ String(asset_id)
	)

	return true


func unregister_asset(
	asset_id: StringName
) -> bool:
	if not _entries.has(asset_id):
		return false

	var entry: AssetEntry = _entries[asset_id]

	if entry != null:
		var asset_path: String = entry.get_path()

		entry.clear_resource()

		_entries.erase(asset_id)
		_asset_order.erase(asset_id)

		asset_unregistered.emit(
			asset_id,
			asset_path
		)

		_log(
			"Asset Unregistered: "
			+ String(asset_id)
		)

		return true

	_entries.erase(asset_id)
	_asset_order.erase(asset_id)

	return false


func get_entry(
	asset_id: StringName
) -> AssetEntry:
	if not _entries.has(asset_id):
		return null

	var entry: AssetEntry = _entries[asset_id]

	if entry == null:
		_entries.erase(asset_id)
		_asset_order.erase(asset_id)
		return null

	return entry


func get_asset(
	asset_id: StringName
) -> Resource:
	var entry: AssetEntry = get_entry(
		asset_id
	)

	if entry == null:
		return null

	if entry.is_loaded():
		return entry.get_resource()

	return load_asset(
		asset_id
	)


func load_asset(
	asset_id: StringName,
	cache_mode: ResourceLoader.CacheMode = ResourceLoader.CACHE_MODE_REUSE
) -> Resource:
	if not _is_operational():
		return null

	var entry: AssetEntry = get_entry(
		asset_id
	)

	if entry == null:
		_set_error(
			"Không tìm thấy Asset ID: "
			+ String(asset_id)
		)

		asset_load_failed.emit(
			asset_id,
			"",
			assets_error
		)

		return null

	if entry.is_loaded() and keep_loaded:
		return entry.get_resource()

	var asset_path: String = entry.get_path()
	var type_hint: String = entry.get_type_hint()

	var resource: Resource = ResourceLoader.load(
		asset_path,
		type_hint,
		cache_mode
	)

	if resource == null:
		_set_error(
			"Không thể Load Asset: "
			+ asset_path
		)

		asset_load_failed.emit(
			asset_id,
			asset_path,
			assets_error
		)

		return null

	entry.set_resource(resource)

	asset_loaded.emit(
		asset_id,
		asset_path
	)

	_log(
		"Asset Loaded: "
		+ String(asset_id)
	)

	return resource


func unload_asset(
	asset_id: StringName
) -> bool:
	var entry: AssetEntry = get_entry(
		asset_id
	)

	if entry == null:
		return false

	if not entry.is_loaded():
		return true

	var asset_path: String = entry.get_path()

	entry.clear_resource()

	asset_unloaded.emit(
		asset_id,
		asset_path
	)

	_log(
		"Asset Unloaded: "
		+ String(asset_id)
	)

	return true


func reload_asset(
	asset_id: StringName
) -> Resource:
	if not _is_operational():
		return null

	var entry: AssetEntry = get_entry(
		asset_id
	)

	if entry == null:
		return null

	entry.clear_resource()

	return load_asset(
		asset_id,
		ResourceLoader.CACHE_MODE_REPLACE
	)


func instantiate_scene(
	asset_id: StringName
) -> Node:
	var resource: Resource = get_asset(
		asset_id
	)

	if resource == null:
		return null

	if not resource is PackedScene:
		_set_error(
			"Asset không phải PackedScene: "
			+ String(asset_id)
		)
		return null

	var scene: PackedScene = resource

	var instance: Node = scene.instantiate()

	if instance == null:
		_set_error(
			"Không thể Instantiate Asset: "
			+ String(asset_id)
		)
		return null

	asset_instantiated.emit(
		asset_id,
		instance
	)

	_log(
		"Asset Instantiated: "
		+ String(asset_id)
	)

	return instance


func save_asset(
	asset_id: StringName,
	resource: Resource = null,
	flags: ResourceSaver.SaverFlags = 0
) -> bool:
	if not _is_operational():
		return false

	var entry: AssetEntry = get_entry(
		asset_id
	)

	if entry == null:
		_set_error(
			"Không tìm thấy Asset ID: "
			+ String(asset_id)
		)
		return false

	var target_resource: Resource = resource

	if target_resource == null:
		target_resource = entry.get_resource()

	if target_resource == null:
		target_resource = load_asset(
			asset_id
		)

	if target_resource == null:
		return false

	var asset_path: String = entry.get_path()

	var result: Error = ResourceSaver.save(
		target_resource,
		asset_path,
		flags
	)

	if result != OK:
		_set_error(
			"Không thể Save Asset: "
			+ asset_path
			+ " - "
			+ error_string(result)
		)
		return false

	if not entry.is_loaded():
		entry.set_resource(
			target_resource
		)

	asset_saved.emit(
		asset_id,
		asset_path
	)

	_log(
		"Asset Saved: "
		+ String(asset_id)
	)

	return true


func set_asset(
	asset_id: StringName,
	resource: Resource,
	save_immediately: bool = false
) -> bool:
	if not _is_operational():
		return false

	var entry: AssetEntry = get_entry(
		asset_id
	)

	if entry == null:
		return false

	if resource == null:
		_set_error(
			"Asset Resource không hợp lệ"
		)
		return false

	if not entry.set_resource(resource):
		return false

	asset_changed.emit(
		asset_id,
		entry.get_path()
	)

	if save_immediately:
		return save_asset(
			asset_id,
			resource
		)

	return true


func has_asset(
	asset_id: StringName
) -> bool:
	return get_entry(
		asset_id
	) != null


func is_asset_loaded(
	asset_id: StringName
) -> bool:
	var entry: AssetEntry = get_entry(
		asset_id
	)

	if entry == null:
		return false

	return entry.is_loaded()


func get_asset_path(
	asset_id: StringName
) -> String:
	var entry: AssetEntry = get_entry(
		asset_id
	)

	if entry == null:
		return ""

	return entry.get_path()


func get_asset_category(
	asset_id: StringName
) -> StringName:
	var entry: AssetEntry = get_entry(
		asset_id
	)

	if entry == null:
		return &""

	return entry.get_category()


func get_asset_type(
	asset_id: StringName
) -> String:
	var entry: AssetEntry = get_entry(
		asset_id
	)

	if entry == null:
		return ""

	if entry.is_loaded():
		return entry.get_asset_type()

	return entry.get_type_hint()


func get_asset_count() -> int:
	return _entries.size()


func get_asset_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for asset_id in _asset_order:
		if _entries.has(asset_id):
			result.append(
				asset_id
			)

	return result


func get_loaded_asset_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for asset_id in _asset_order:
		var entry: AssetEntry = get_entry(
			asset_id
		)

		if entry != null and entry.is_loaded():
			result.append(
				asset_id
			)

	return result


func get_unloaded_asset_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for asset_id in _asset_order:
		var entry: AssetEntry = get_entry(
			asset_id
		)

		if entry != null and not entry.is_loaded():
			result.append(
				asset_id
			)

	return result


func get_asset_ids_by_category(
	category: StringName
) -> Array[StringName]:
	var result: Array[StringName] = []

	if category.is_empty():
		return result

	for asset_id in _asset_order:
		var entry: AssetEntry = get_entry(
			asset_id
		)

		if entry == null:
			continue

		if entry.get_category() == category:
			result.append(
				asset_id
			)

	return result


func get_assets_by_category(
	category: StringName
) -> Array[Resource]:
	var result: Array[Resource] = []

	for asset_id in get_asset_ids_by_category(
		category
	):
		var asset: Resource = get_asset(
			asset_id
		)

		if asset != null:
			result.append(
				asset
			)

	return result


func get_assets_by_type(
	type_name: String
) -> Array[Resource]:
	var result: Array[Resource] = []

	if type_name.is_empty():
		return result

	for asset_id in _asset_order:
		var asset: Resource = get_asset(
			asset_id
		)

		if asset == null:
			continue

		if asset.get_class() == type_name:
			result.append(
				asset
			)

	return result


func scan_assets(
	directory_path: String
) -> bool:
	if directory_path.is_empty():
		_set_error(
			"Scan Directory Path không được để trống"
		)
		return false

	if not DirAccess.dir_exists_absolute(
		ProjectSettings.globalize_path(
			directory_path
		)
	):
		_set_error(
			"Scan Directory không tồn tại: "
			+ directory_path
		)
		return false

	var directory := DirAccess.open(
		directory_path
	)

	if directory == null:
		_set_error(
			"Không thể mở Scan Directory: "
			+ directory_path
		)
		return false

	directory.list_dir_begin()

	while true:
		var item_name: String = directory.get_next()

		if item_name.is_empty():
			break

		if item_name.begins_with("."):
			continue

		var item_path: String = directory_path.path_join(
			item_name
		)

		if directory.current_is_dir():
			if not scan_assets(item_path):
				directory.list_dir_end()
				return false

			continue

		if not ResourceLoader.exists(
			item_path
		):
			continue

		var relative_path: String = item_path

		var id_path: String = relative_path

		if id_path.begins_with(
			"res://"
		):
			id_path = id_path.trim_prefix(
				"res://"
			)

		var asset_id: StringName = StringName(
			id_path
		)

		if has_asset(asset_id):
			continue

		var category: StringName = StringName(
			directory_path.get_file()
		)

		if not register_asset(
			asset_id,
			item_path,
			category
		):
			directory.list_dir_end()
			return false

	directory.list_dir_end()

	return true


func scan_base_path() -> bool:
	return scan_assets(
		base_path
	)


func validate_registered_paths() -> bool:
	assets_error = ""

	for asset_id in _asset_order:
		var entry: AssetEntry = get_entry(
			asset_id
		)

		if entry == null:
			continue

		var asset_path: String = entry.get_path()

		if not ResourceLoader.exists(
			asset_path,
			entry.get_type_hint()
		):
			assets_error = (
				"Asset Path không tồn tại: "
				+ asset_path
			)

			return false

	return true


func clear_loaded() -> void:
	for asset_id in _asset_order:
		var entry: AssetEntry = get_entry(
			asset_id
		)

		if entry != null:
			entry.clear_resource()


func clear_assets() -> void:
	for asset_id in _asset_order:
		var entry: AssetEntry = get_entry(
			asset_id
		)

		if entry != null:
			entry.clear_resource()

	_entries.clear()
	_asset_order.clear()


func create_snapshot() -> Dictionary:
	var snapshot: Dictionary = {
		"assets": []
	}

	var records: Array = []

	for asset_id in _asset_order:
		var entry: AssetEntry = get_entry(
			asset_id
		)

		if entry == null:
			continue

		records.append(
			entry.to_dictionary()
		)

	snapshot["assets"] = records

	return snapshot


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
	return assets_error


func _validate_root() -> bool:
	assets_error = ""

	if not is_inside_tree():
		assets_error = (
			"Assets không nằm trong SceneTree"
		)
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Assets: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
			% [
				EXPECTED_NODE_NAME,
				name
			]
		)

	return true


func _validate_base_path() -> bool:
	assets_error = ""

	if base_path.is_empty():
		assets_error = (
			"Assets Base Path không được để trống"
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
	assets_error = message

	_log_error(
		message
	)


func _fail(
	reason: String
) -> bool:
	state = State.FAILED
	assets_error = reason

	assets_failed.emit(
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

	assets_stopping.emit()

	if clear_on_stop:
		clear_assets()
	elif not keep_loaded:
		clear_loaded()

	state = State.STOPPED

	assets_stopped.emit()

	_log(
		"Assets Stopped"
	)


func _log(
	message: String
) -> void:
	if console_output:
		print(
			"[Assets] ",
			message
		)


func _log_error(
	message: String
) -> void:
	push_error(
		"[Assets] "
		+ message
) 
