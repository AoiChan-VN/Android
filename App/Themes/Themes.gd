class_name Themes
extends Node

signal themes_started
signal themes_ready
signal themes_paused
signal themes_resumed
signal themes_stopping
signal themes_stopped
signal themes_failed(reason: String)

signal theme_registered(
	theme_id: StringName,
	theme_path: String
)

signal theme_unregistered(
	theme_id: StringName,
	theme_path: String
)

signal theme_loaded(
	theme_id: StringName,
	theme_path: String
)

signal theme_unloaded(
	theme_id: StringName,
	theme_path: String
)

signal theme_activated(
	theme_id: StringName
)

signal theme_deactivated(
	theme_id: StringName
)

signal theme_applied(
	theme_id: StringName,
	target: Control
)

signal theme_removed(
	target: Control
)

signal theme_changed(
	theme_id: StringName
)

signal theme_saved(
	theme_id: StringName,
	theme_path: String
)

signal theme_load_failed(
	theme_id: StringName,
	theme_path: String,
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

const EXPECTED_NODE_NAME: StringName = &"Themes"

@export_group("Themes")
@export var auto_start: bool = true
@export var validate_paths: bool = true
@export var keep_loaded: bool = true
@export var reapply_on_change: bool = true
@export var clear_targets_on_stop: bool = true
@export var clear_on_stop: bool = false
@export var console_output: bool = true

@export_group("Default")
@export var default_theme_id: StringName = &""
@export var activate_default_on_start: bool = false

@export_group("Validation")
@export var validate_root: bool = true

var state: State = State.IDLE
var themes_error: String = ""

var _entries: Dictionary = {}
var _theme_order: Array[StringName] = []
var _targets: Dictionary = {}
var _active_theme_id: StringName = &""


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
		themes_error = ""

	if validate_root and not _validate_root():
		return _fail(themes_error)

	state = State.STARTING

	themes_started.emit()

	if (
		activate_default_on_start
		and not default_theme_id.is_empty()
		and has_theme(default_theme_id)
	):
		if not set_active_theme(
			default_theme_id,
			false
		):
			return _fail(themes_error)

	state = State.READY

	themes_ready.emit()

	_log("Themes Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	state = State.PAUSED

	themes_paused.emit()

	_log("Themes Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	state = State.READY

	themes_resumed.emit()

	_log("Themes Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func register_theme(
	theme_id: StringName,
	theme_path: String,
	category: StringName = &"",
	replace_existing: bool = false
) -> bool:
	if not _is_operational():
		return false

	if theme_id.is_empty():
		_set_error(
			"Theme ID không được để trống"
		)
		return false

	if theme_path.is_empty():
		_set_error(
			"Theme Path không được để trống"
		)
		return false

	if validate_paths and not ResourceLoader.exists(
		theme_path,
		"Theme"
	):
		_set_error(
			"Theme Path không tồn tại: "
			+ theme_path
		)
		return false

	if _entries.has(theme_id):
		if not replace_existing:
			_set_error(
				"Theme ID đã tồn tại: "
				+ String(theme_id)
			)
			return false

		if not unregister_theme(theme_id):
			return false

	var entry := ThemeEntry.new()

	if not entry.configure(
		theme_id,
		theme_path,
		category
	):
		_set_error(
			"Không thể tạo Theme Entry"
		)
		return false

	_entries[theme_id] = entry
	_theme_order.append(theme_id)

	theme_registered.emit(
		theme_id,
		theme_path
	)

	_log(
		"Theme Registered: "
		+ String(theme_id)
	)

	return true


func register_loaded_theme(
	theme_id: StringName,
	theme: Theme,
	theme_path: String = "",
	category: StringName = &"",
	replace_existing: bool = false
) -> bool:
	if not _is_operational():
		return false

	if theme_id.is_empty():
		_set_error(
			"Theme ID không được để trống"
		)
		return false

	if theme == null:
		_set_error(
			"Theme Resource không hợp lệ"
		)
		return false

	if _entries.has(theme_id):
		if not replace_existing:
			_set_error(
				"Theme ID đã tồn tại: "
				+ String(theme_id)
			)
			return false

		if not unregister_theme(theme_id):
			return false

	var path: String = theme_path

	if path.is_empty():
		path = theme.resource_path

	var entry := ThemeEntry.new()

	if not entry.configure(
		theme_id,
		path,
		category
	):
		_set_error(
			"Không thể tạo Theme Entry"
		)
		return false

	if not entry.set_theme(theme):
		_set_error(
			"Không thể gán Theme Resource"
		)
		return false

	_entries[theme_id] = entry
	_theme_order.append(theme_id)

	_connect_theme_resource(
		theme_id,
		theme
	)

	theme_registered.emit(
		theme_id,
		path
	)

	theme_loaded.emit(
		theme_id,
		path
	)

	_log(
		"Loaded Theme Registered: "
		+ String(theme_id)
	)

	return true


func create_theme(
	theme_id: StringName,
	theme_path: String = "",
	category: StringName = &"",
	replace_existing: bool = false
) -> Theme:
	if not _is_operational():
		return null

	var theme := Theme.new()

	if not register_loaded_theme(
		theme_id,
		theme,
		theme_path,
		category,
		replace_existing
	):
		return null

	return theme


func duplicate_theme(
	source_theme_id: StringName,
	new_theme_id: StringName,
	theme_path: String = "",
	category: StringName = &"",
	replace_existing: bool = false
) -> Theme:
	var source: Theme = get_theme(
		source_theme_id
	)

	if source == null:
		return null

	var duplicate_resource: Theme = (
		source.duplicate(true) as Theme
	)

	if duplicate_resource == null:
		_set_error(
			"Không thể Duplicate Theme: "
			+ String(source_theme_id)
		)
		return null

	if not register_loaded_theme(
		new_theme_id,
		duplicate_resource,
		theme_path,
		category,
		replace_existing
	):
		return null

	return duplicate_resource


func unregister_theme(
	theme_id: StringName
) -> bool:
	var entry: ThemeEntry = get_entry(
		theme_id
	)

	if entry == null:
		return false

	var theme_path: String = entry.get_path()
	var theme: Theme = entry.get_theme()
	var was_active: bool = (
		_active_theme_id == theme_id
	)

	_remove_theme_targets(
		theme_id
	)

	if theme != null:
		_disconnect_theme_resource(
			theme_id,
			theme
		)

	entry.clear_theme()

	_entries.erase(theme_id)
	_theme_order.erase(theme_id)

	if was_active:
		_active_theme_id = &""

		theme_deactivated.emit(
			theme_id
		)

		_refresh_active_targets()

	theme_unregistered.emit(
		theme_id,
		theme_path
	)

	_log(
		"Theme Unregistered: "
		+ String(theme_id)
	)

	return true


func get_entry(
	theme_id: StringName
) -> ThemeEntry:
	if not _entries.has(theme_id):
		return null

	var entry: ThemeEntry = _entries[
		theme_id
	]

	if entry == null:
		_entries.erase(theme_id)
		_theme_order.erase(theme_id)
		return null

	return entry


func get_theme(
	theme_id: StringName
) -> Theme:
	var entry: ThemeEntry = get_entry(
		theme_id
	)

	if entry == null:
		return null

	if entry.is_loaded():
		return entry.get_theme()

	return load_theme(
		theme_id
	)


func load_theme(
	theme_id: StringName,
	cache_mode: ResourceLoader.CacheMode = ResourceLoader.CACHE_MODE_REUSE
) -> Theme:
	if not _is_operational():
		return null

	var entry: ThemeEntry = get_entry(
		theme_id
	)

	if entry == null:
		_set_error(
			"Không tìm thấy Theme ID: "
			+ String(theme_id)
		)

		theme_load_failed.emit(
			theme_id,
			"",
			themes_error
		)

		return null

	if entry.is_loaded() and keep_loaded:
		return entry.get_theme()

	var theme_path: String = entry.get_path()

	if theme_path.is_empty():
		_set_error(
			"Theme Path không được để trống: "
			+ String(theme_id)
		)

		theme_load_failed.emit(
			theme_id,
			theme_path,
			themes_error
		)

		return null

	var resource: Resource = ResourceLoader.load(
		theme_path,
		"Theme",
		cache_mode
	)

	if not resource is Theme:
		_set_error(
			"Resource không phải Theme: "
			+ theme_path
		)

		theme_load_failed.emit(
			theme_id,
			theme_path,
			themes_error
		)

		return null

	var theme: Theme = resource as Theme

	entry.set_theme(theme)

	_connect_theme_resource(
		theme_id,
		theme
	)

	theme_loaded.emit(
		theme_id,
		theme_path
	)

	_log(
		"Theme Loaded: "
		+ String(theme_id)
	)

	return theme


func reload_theme(
	theme_id: StringName
) -> Theme:
	var entry: ThemeEntry = get_entry(
		theme_id
	)

	if entry == null:
		return null

	var theme: Theme = entry.get_theme()

	if theme != null:
		_disconnect_theme_resource(
			theme_id,
			theme
		)

	entry.clear_theme()

	var result: Theme = load_theme(
		theme_id,
		ResourceLoader.CACHE_MODE_REPLACE
	)

	if result != null:
		refresh_theme_targets(
			theme_id
		)

	return result


func unload_theme(
	theme_id: StringName
) -> bool:
	var entry: ThemeEntry = get_entry(
		theme_id
	)

	if entry == null:
		return false

	if not entry.is_loaded():
		return true

	var theme: Theme = entry.get_theme()
	var theme_path: String = entry.get_path()

	if theme != null:
		_disconnect_theme_resource(
			theme_id,
			theme
		)

	entry.clear_theme()

	if _active_theme_id == theme_id:
		_refresh_active_targets()

	refresh_theme_targets(
		theme_id
	)

	theme_unloaded.emit(
		theme_id,
		theme_path
	)

	_log(
		"Theme Unloaded: "
		+ String(theme_id)
	)

	return true


func load_all() -> bool:
	var success: bool = true

	for theme_id in get_theme_ids():
		if load_theme(theme_id) == null:
			success = false

	return success


func unload_all() -> bool:
	var success: bool = true
	var theme_ids: Array[StringName] = (
		get_theme_ids()
	)

	theme_ids.reverse()

	for theme_id in theme_ids:
		if not unload_theme(theme_id):
			success = false

	return success


func save_theme(
	theme_id: StringName,
	theme_path: String = "",
	flags: ResourceSaver.SaverFlags = 0
) -> bool:
	if not _is_operational():
		return false

	var entry: ThemeEntry = get_entry(
		theme_id
	)

	if entry == null:
		_set_error(
			"Không tìm thấy Theme ID: "
			+ String(theme_id)
		)
		return false

	var theme: Theme = get_theme(
		theme_id
	)

	if theme == null:
		return false

	var path: String = theme_path

	if path.is_empty():
		path = entry.get_path()

	if path.is_empty():
		_set_error(
			"Theme Save Path không được để trống"
		)
		return false

	var result: Error = ResourceSaver.save(
		theme,
		path,
		flags
	)

	if result != OK:
		_set_error(
			"Không thể Save Theme: "
			+ path
			+ " - "
			+ error_string(result)
		)
		return false

	entry.set_path(path)

	theme_saved.emit(
		theme_id,
		path
	)

	_log(
		"Theme Saved: "
		+ String(theme_id)
	)

	return true


func set_active_theme(
	theme_id: StringName,
	apply_tracked: bool = true
) -> bool:
	if not _is_operational():
		return false

	if theme_id.is_empty():
		return clear_active_theme(
			apply_tracked
		)

	var theme: Theme = get_theme(
		theme_id
	)

	if theme == null:
		_set_error(
			"Không thể Activate Theme: "
			+ String(theme_id)
		)
		return false

	if _active_theme_id == theme_id:
		if apply_tracked:
			_refresh_active_targets()

		return true

	var previous_theme_id: StringName = (
		_active_theme_id
	)

	_active_theme_id = theme_id

	if not previous_theme_id.is_empty():
		theme_deactivated.emit(
			previous_theme_id
		)

	theme_activated.emit(
		theme_id
	)

	if apply_tracked:
		_refresh_active_targets()

	_log(
		"Theme Activated: "
		+ String(theme_id)
	)

	return true


func clear_active_theme(
	clear_tracked: bool = true
) -> bool:
	if _active_theme_id.is_empty():
		if clear_tracked:
			_refresh_active_targets()

		return true

	var previous_theme_id: StringName = (
		_active_theme_id
	)

	_active_theme_id = &""

	theme_deactivated.emit(
		previous_theme_id
	)

	if clear_tracked:
		_refresh_active_targets()

	_log("Active Theme Cleared")

	return true


func get_active_theme_id() -> StringName:
	return _active_theme_id


func get_active_theme() -> Theme:
	if _active_theme_id.is_empty():
		return null

	return get_theme(
		_active_theme_id
	)


func apply_theme(
	target: Control,
	theme_id: StringName = &"",
	track_target: bool = true
) -> bool:
	if not _is_operational():
		return false

	if not is_instance_valid(target):
		_set_error(
			"Theme Target không hợp lệ"
		)
		return false

	var resolved_theme_id: StringName = (
		_resolve_theme_id(theme_id)
	)

	if resolved_theme_id.is_empty():
		_set_error(
			"Không có Theme Active để Apply"
		)
		return false

	var theme: Theme = get_theme(
		resolved_theme_id
	)

	if theme == null:
		return false

	target.theme = theme

	if track_target:
		_targets[target.get_instance_id()] = {
			"ref": weakref(target),
			"theme_id": theme_id
		}

	theme_applied.emit(
		resolved_theme_id,
		target
	)

	return true


func apply_active_theme(
	target: Control,
	track_target: bool = true
) -> bool:
	return apply_theme(
		target,
		&"",
		track_target
	)


func apply_to_group(
	group_id: StringName,
	theme_id: StringName = &"",
	track_targets: bool = true
) -> int:
	if not _is_operational():
		return 0

	if group_id.is_empty():
		return 0

	var applied_count: int = 0

	for node in get_tree().get_nodes_in_group(
		group_id
	):
		if not node is Control:
			continue

		var target: Control = node as Control

		if apply_theme(
			target,
			theme_id,
			track_targets
		):
			applied_count += 1

	return applied_count


func remove_from_control(
	target: Control,
	clear_theme: bool = true
) -> bool:
	if not is_instance_valid(target):
		return false

	var target_id: int = target.get_instance_id()

	if clear_theme:
		target.theme = null

	_targets.erase(target_id)

	theme_removed.emit(
		target
	)

	return true


func refresh_target(
	target: Control
) -> bool:
	if not is_instance_valid(target):
		return false

	var target_id: int = target.get_instance_id()

	if not _targets.has(target_id):
		return false

	var record: Dictionary = _targets[
		target_id
	]

	var requested_theme_id: StringName = StringName(
		str(
			record.get(
				"theme_id",
				""
			)
		)
	)

	return _apply_tracked_theme(
		target,
		requested_theme_id
	)


func refresh_all_targets() -> int:
	var refreshed_count: int = 0
	var target_ids: Array = _targets.keys()

	for target_id in target_ids:
		var target: Control = _get_target(
			target_id
		)

		if target == null:
			_targets.erase(target_id)
			continue

		if refresh_target(target):
			refreshed_count += 1

	return refreshed_count


func refresh_theme_targets(
	theme_id: StringName
) -> int:
	var refreshed_count: int = 0
	var target_ids: Array = _targets.keys()

	for target_id in target_ids:
		var target: Control = _get_target(
			target_id
		)

		if target == null:
			_targets.erase(target_id)
			continue

		var record: Dictionary = _targets[
			target_id
		]

		var requested_theme_id: StringName = StringName(
			str(
				record.get(
					"theme_id",
					""
				)
			)
		)

		var resolved_theme_id: StringName = (
			_resolve_theme_id(
				requested_theme_id
			)
		)

		if resolved_theme_id != theme_id:
			continue

		if _apply_tracked_theme(
			target,
			requested_theme_id
		):
			refreshed_count += 1

	return refreshed_count


func clear_targets(
	clear_themes: bool = true
) -> void:
	var target_ids: Array = _targets.keys()

	for target_id in target_ids:
		var target: Control = _get_target(
			target_id
		)

		if target == null:
			continue

		if clear_themes:
			target.theme = null

		theme_removed.emit(
			target
		)

	_targets.clear()


func get_target_count() -> int:
	_cleanup_targets()

	return _targets.size()


func set_theme_item(
	theme_id: StringName,
	data_type: int,
	item_name: StringName,
	theme_type: StringName,
	value: Variant
) -> bool:
	var theme: Theme = get_theme(
		theme_id
	)

	if theme == null:
		return false

	if (
		data_type < Theme.DATA_TYPE_COLOR
		or data_type >= Theme.DATA_TYPE_MAX
	):
		_set_error(
			"Theme Data Type không hợp lệ"
		)
		return false

	if item_name.is_empty():
		_set_error(
			"Theme Item Name không được để trống"
		)
		return false

	if theme_type.is_empty():
		_set_error(
			"Theme Type không được để trống"
		)
		return false

	theme.set_theme_item(
		data_type,
		item_name,
		theme_type,
		value
	)

	return true


func get_theme_item(
	theme_id: StringName,
	data_type: int,
	item_name: StringName,
	theme_type: StringName
) -> Variant:
	var theme: Theme = get_theme(
		theme_id
	)

	if theme == null:
		return null

	if not theme.has_theme_item(
		data_type,
		item_name,
		theme_type
	):
		return null

	return theme.get_theme_item(
		data_type,
		item_name,
		theme_type
	)


func has_theme_item(
	theme_id: StringName,
	data_type: int,
	item_name: StringName,
	theme_type: StringName
) -> bool:
	var theme: Theme = get_theme(
		theme_id
	)

	if theme == null:
		return false

	return theme.has_theme_item(
		data_type,
		item_name,
		theme_type
	)


func clear_theme_item(
	theme_id: StringName,
	data_type: int,
	item_name: StringName,
	theme_type: StringName
) -> bool:
	var theme: Theme = get_theme(
		theme_id
	)

	if theme == null:
		return false

	if not theme.has_theme_item(
		data_type,
		item_name,
		theme_type
	):
		return false

	theme.clear_theme_item(
		data_type,
		item_name,
		theme_type
	)

	return true


func set_color(
	theme_id: StringName,
	item_name: StringName,
	theme_type: StringName,
	value: Color
) -> bool:
	return set_theme_item(
		theme_id,
		Theme.DATA_TYPE_COLOR,
		item_name,
		theme_type,
		value
	)


func set_constant(
	theme_id: StringName,
	item_name: StringName,
	theme_type: StringName,
	value: int
) -> bool:
	return set_theme_item(
		theme_id,
		Theme.DATA_TYPE_CONSTANT,
		item_name,
		theme_type,
		value
	)


func set_font(
	theme_id: StringName,
	item_name: StringName,
	theme_type: StringName,
	value: Font
) -> bool:
	if value == null:
		return false

	return set_theme_item(
		theme_id,
		Theme.DATA_TYPE_FONT,
		item_name,
		theme_type,
		value
	)


func set_font_size(
	theme_id: StringName,
	item_name: StringName,
	theme_type: StringName,
	value: int
) -> bool:
	if value < 1:
		return false

	return set_theme_item(
		theme_id,
		Theme.DATA_TYPE_FONT_SIZE,
		item_name,
		theme_type,
		value
	)


func set_icon(
	theme_id: StringName,
	item_name: StringName,
	theme_type: StringName,
	value: Texture2D
) -> bool:
	if value == null:
		return false

	return set_theme_item(
		theme_id,
		Theme.DATA_TYPE_ICON,
		item_name,
		theme_type,
		value
	)


func set_stylebox(
	theme_id: StringName,
	item_name: StringName,
	theme_type: StringName,
	value: StyleBox
) -> bool:
	if value == null:
		return false

	return set_theme_item(
		theme_id,
		Theme.DATA_TYPE_STYLEBOX,
		item_name,
		theme_type,
		value
	)


func set_theme_defaults(
	theme_id: StringName,
	base_scale: float = 0.0,
	default_font: Font = null,
	default_font_size: int = -1
) -> bool:
	var theme: Theme = get_theme(
		theme_id
	)

	if theme == null:
		return false

	theme.default_base_scale = base_scale
	theme.default_font = default_font
	theme.default_font_size = default_font_size

	return true


func set_type_variation(
	theme_id: StringName,
	theme_type: StringName,
	base_type: StringName
) -> bool:
	var theme: Theme = get_theme(
		theme_id
	)

	if theme == null:
		return false

	if theme_type.is_empty() or base_type.is_empty():
		return false

	theme.set_type_variation(
		theme_type,
		base_type
	)

	return true


func clear_type_variation(
	theme_id: StringName,
	theme_type: StringName
) -> bool:
	var theme: Theme = get_theme(
		theme_id
	)

	if theme == null:
		return false

	if theme_type.is_empty():
		return false

	theme.clear_type_variation(
		theme_type
	)

	return true


func merge_themes(
	target_theme_id: StringName,
	source_theme_id: StringName
) -> bool:
	var target: Theme = get_theme(
		target_theme_id
	)

	var source: Theme = get_theme(
		source_theme_id
	)

	if target == null or source == null:
		return false

	if target == source:
		return false

	target.merge_with(source)

	return true


func clear_theme_data(
	theme_id: StringName
) -> bool:
	var theme: Theme = get_theme(
		theme_id
	)

	if theme == null:
		return false

	theme.clear()

	return true


func has_theme(
	theme_id: StringName
) -> bool:
	return get_entry(theme_id) != null


func is_theme_loaded(
	theme_id: StringName
) -> bool:
	var entry: ThemeEntry = get_entry(
		theme_id
	)

	if entry == null:
		return false

	return entry.is_loaded()


func get_theme_path(
	theme_id: StringName
) -> String:
	var entry: ThemeEntry = get_entry(
		theme_id
	)

	if entry == null:
		return ""

	return entry.get_path()


func get_theme_category(
	theme_id: StringName
) -> StringName:
	var entry: ThemeEntry = get_entry(
		theme_id
	)

	if entry == null:
		return &""

	return entry.get_category()


func get_theme_count() -> int:
	return _entries.size()


func get_theme_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for theme_id in _theme_order:
		if _entries.has(theme_id):
			result.append(theme_id)

	return result


func get_loaded_theme_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for theme_id in get_theme_ids():
		var entry: ThemeEntry = get_entry(
			theme_id
		)

		if entry != null and entry.is_loaded():
			result.append(theme_id)

	return result


func get_theme_ids_by_category(
	category: StringName
) -> Array[StringName]:
	var result: Array[StringName] = []

	if category.is_empty():
		return result

	for theme_id in get_theme_ids():
		var entry: ThemeEntry = get_entry(
			theme_id
		)

		if (
			entry != null
			and entry.get_category() == category
		):
			result.append(theme_id)

	return result


func validate_registered_paths() -> bool:
	themes_error = ""

	for theme_id in get_theme_ids():
		var entry: ThemeEntry = get_entry(
			theme_id
		)

		if entry == null:
			continue

		var theme_path: String = entry.get_path()

		if theme_path.is_empty():
			if entry.is_loaded():
				continue

			themes_error = (
				"Theme Path không được để trống: "
				+ String(theme_id)
			)
			return false

		if not ResourceLoader.exists(
			theme_path,
			"Theme"
		):
			themes_error = (
				"Theme Path không tồn tại: "
				+ theme_path
			)
			return false

	return true


func create_snapshot() -> Dictionary:
	var records: Array = []

	for theme_id in get_theme_ids():
		var entry: ThemeEntry = get_entry(
			theme_id
		)

		if entry == null:
			continue

		records.append(
			entry.to_dictionary()
		)

	return {
		"active_theme_id": String(
			_active_theme_id
		),
		"themes": records,
		"target_count": get_target_count()
	}


func clear_themes() -> void:
	clear_targets(true)

	var theme_ids: Array[StringName] = (
		get_theme_ids()
	)

	theme_ids.reverse()

	for theme_id in theme_ids:
		unregister_theme(
			theme_id
		)

	_entries.clear()
	_theme_order.clear()
	_active_theme_id = &""


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
	return themes_error


func _connect_theme_resource(
	theme_id: StringName,
	theme: Theme
) -> void:
	if theme == null:
		return

	var callback: Callable = Callable(
		self,
		"_on_theme_resource_changed"
	).bind(theme_id)

	if not theme.changed.is_connected(
		callback
	):
		theme.changed.connect(
			callback
		)


func _disconnect_theme_resource(
	theme_id: StringName,
	theme: Theme
) -> void:
	if theme == null:
		return

	var callback: Callable = Callable(
		self,
		"_on_theme_resource_changed"
	).bind(theme_id)

	if theme.changed.is_connected(
		callback
	):
		theme.changed.disconnect(
			callback
		)


func _on_theme_resource_changed(
	theme_id: StringName
) -> void:
	theme_changed.emit(
		theme_id
	)

	if reapply_on_change:
		refresh_theme_targets(
			theme_id
		)


func _resolve_theme_id(
	theme_id: StringName
) -> StringName:
	if not theme_id.is_empty():
		return theme_id

	return _active_theme_id


func _apply_tracked_theme(
	target: Control,
	requested_theme_id: StringName
) -> bool:
	var resolved_theme_id: StringName = (
		_resolve_theme_id(
			requested_theme_id
		)
	)

	if resolved_theme_id.is_empty():
		target.theme = null
		return true

	var theme: Theme = get_theme(
		resolved_theme_id
	)

	if theme == null:
		target.theme = null
		return false

	target.theme = theme

	theme_applied.emit(
		resolved_theme_id,
		target
	)

	return true


func _refresh_active_targets() -> void:
	var target_ids: Array = _targets.keys()

	for target_id in target_ids:
		var target: Control = _get_target(
			target_id
		)

		if target == null:
			_targets.erase(target_id)
			continue

		var record: Dictionary = _targets[
			target_id
		]

		var requested_theme_id: StringName = StringName(
			str(
				record.get(
					"theme_id",
					""
				)
			)
		)

		if not requested_theme_id.is_empty():
			continue

		_apply_tracked_theme(
			target,
			requested_theme_id
		)


func _remove_theme_targets(
	theme_id: StringName
) -> void:
	var target_ids: Array = _targets.keys()

	for target_id in target_ids:
		var target: Control = _get_target(
			target_id
		)

		if target == null:
			_targets.erase(target_id)
			continue

		var record: Dictionary = _targets[
			target_id
		]

		var requested_theme_id: StringName = StringName(
			str(
				record.get(
					"theme_id",
					""
				)
			)
		)

		if requested_theme_id != theme_id:
			continue

		target.theme = null

		_targets.erase(target_id)

		theme_removed.emit(
			target
		)


func _get_target(
	target_id: Variant
) -> Control:
	if not _targets.has(target_id):
		return null

	var record: Dictionary = _targets[
		target_id
	]

	var target_ref: WeakRef = (
		record.get(
			"ref",
			null
		) as WeakRef
	)

	if target_ref == null:
		return null

	var target_object: Object = target_ref.get_ref()

	if not target_object is Control:
		return null

	return target_object as Control


func _cleanup_targets() -> void:
	var target_ids: Array = _targets.keys()

	for target_id in target_ids:
		if _get_target(target_id) == null:
			_targets.erase(target_id)


func _validate_root() -> bool:
	themes_error = ""

	if not is_inside_tree():
		themes_error = (
			"Themes không nằm trong SceneTree"
		)
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Themes: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
			% [
				EXPECTED_NODE_NAME,
				name
			]
		)

	return true


func _is_operational() -> bool:
	return (
		state == State.READY
		or state == State.PAUSED
	)


func _set_error(
	message: String
) -> void:
	themes_error = message

	_log_error(
		message
	)


func _fail(
	reason: String
) -> bool:
	state = State.FAILED
	themes_error = reason

	themes_failed.emit(
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

	themes_stopping.emit()

	if clear_targets_on_stop:
		clear_targets(true)

	if clear_on_stop:
		clear_themes()
	elif not keep_loaded:
		unload_all()

	state = State.STOPPED

	themes_stopped.emit()

	_log("Themes Stopped")


func _log(
	message: String
) -> void:
	if console_output:
		print(
			"[Themes] ",
			message
		)


func _log_error(
	message: String
) -> void:
	push_error(
		"[Themes] "
		+ message
	) 
