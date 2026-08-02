class_name Presentation
extends Node

signal presentation_started
signal presentation_ready
signal presentation_paused
signal presentation_resumed
signal presentation_stopping
signal presentation_stopped
signal presentation_failed(reason: String)

signal view_registered(view_id: StringName)
signal view_unregistered(view_id: StringName)
signal view_opening(view_id: StringName)
signal view_opened(view_id: StringName)
signal view_closing(view_id: StringName)
signal view_closed(view_id: StringName)
signal view_paused(view_id: StringName)
signal view_resumed(view_id: StringName)
signal view_failed(view_id: StringName, reason: String)
signal active_changed(view_id: StringName)

enum State {
	IDLE,
	STARTING,
	READY,
	PAUSED,
	STOPPING,
	STOPPED,
	FAILED
}

const EXPECTED_NODE_NAME: StringName = &"Presentation"

@export_group("Presentation")
@export var auto_start: bool = true
@export var scan_children: bool = true
@export var open_auto_views: bool = true
@export var close_on_exit: bool = true
@export var strict_open: bool = false
@export var console_output: bool = true
@export var free_on_remove: bool = false

@export_group("Validation")
@export var validate_root: bool = true

var state: State = State.IDLE
var presentation_error: String = ""

var _views: Dictionary = {}
var _view_order: Array[StringName] = []
var _open_stack: Array[StringName] = []
var _active_id: StringName = &""


func _enter_tree() -> void:
	state = State.STARTING


func _ready() -> void:
	if scan_children:
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

	if state == State.FAILED or state == State.STOPPED:
		state = State.IDLE
		presentation_error = ""

	if validate_root and not _validate_root():
		return _fail(presentation_error)

	state = State.STARTING

	presentation_started.emit()

	var success: bool = true

	if open_auto_views:
		success = _open_auto_views()

	if strict_open and not success:
		return _fail("Một hoặc nhiều View không thể mở")

	state = State.READY

	presentation_ready.emit()

	_log("Presentation Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	var success: bool = pause_all()

	if strict_open and not success:
		return false

	state = State.PAUSED

	presentation_paused.emit()

	_log("Presentation Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	var success: bool = resume_all()

	if strict_open and not success:
		return false

	state = State.READY

	presentation_resumed.emit()

	_log("Presentation Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func add_view(view: PresentView) -> bool:
	if not is_instance_valid(view):
		_log_error("Không thể thêm View không hợp lệ")
		return false

	if view.get_parent() != null and view.get_parent() != self:
		_log_error(
			"View đang thuộc Node khác: "
			+ String(view.get_view_id())
		)
		return false

	if view.get_parent() == null:
		add_child(view)

	return register_view(view)


func register_view(view: PresentView) -> bool:
	if not is_instance_valid(view):
		_log_error("Không thể đăng ký View không hợp lệ")
		return false

	if view.get_parent() != self:
		_log_error("View phải là Child trực tiếp của Presentation")
		return false

	var view_id: StringName = view.get_view_id()

	if view_id.is_empty():
		_log_error("View ID không được để trống")
		return false

	if _views.has(view_id):
		_log_error("View ID đã tồn tại: " + String(view_id))
		return false

	_views[view_id] = view
	_view_order.append(view_id)

	view.set_order(view.order)

	_connect_view(view)

	if view.is_active():
		_push_open(view_id)

	view_registered.emit(view_id)

	_log("View Registered: " + String(view_id))

	if state == State.READY and open_auto_views and view.auto_open:
		view.open()

	return true


func unregister_view(view_id: StringName) -> bool:
	if not _views.has(view_id):
		return false

	var view: PresentView = _views[view_id]

	if is_instance_valid(view):
		if view.is_active() or view.is_failed():
			view.close()

		_disconnect_view(view)

		if view.get_parent() == self:
			remove_child(view)

	_views.erase(view_id)
	_view_order.erase(view_id)
	_open_stack.erase(view_id)

	view_unregistered.emit(view_id)

	_update_active()

	_log("View Unregistered: " + String(view_id))

	if free_on_remove and is_instance_valid(view):
		view.queue_free()

	return true


func get_view(view_id: StringName) -> PresentView:
	if not _views.has(view_id):
		return null

	var view: PresentView = _views[view_id]

	if not is_instance_valid(view):
		_views.erase(view_id)
		_view_order.erase(view_id)
		_open_stack.erase(view_id)
		_update_active()
		return null

	return view


func has_view(view_id: StringName) -> bool:
	return get_view(view_id) != null


func get_view_count() -> int:
	return _views.size()


func get_view_ids() -> Array[StringName]:
	return _get_view_ids_copy()


func get_open_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for view_id in _open_stack:
		var view: PresentView = get_view(view_id)

		if view != null and view.is_active():
			result.append(view_id)

	return result


func get_kind_ids(kind_id: int) -> Array[StringName]:
	var result: Array[StringName] = []

	for view_id in _get_view_ids_copy():
		var view: PresentView = get_view(view_id)

		if view != null and int(view.get_kind()) == kind_id:
			result.append(view_id)

	return result


func get_active_id() -> StringName:
	return _active_id


func get_active_view() -> PresentView:
	if _active_id.is_empty():
		return null

	return get_view(_active_id)


func open_view(
	view_id: StringName,
	data: Dictionary = {}
) -> bool:
	var view: PresentView = get_view(view_id)

	if view == null:
		return false

	return view.open(data)


func close_view(view_id: StringName) -> bool:
	var view: PresentView = get_view(view_id)

	if view == null:
		return false

	return view.close()


func toggle_view(
	view_id: StringName,
	data: Dictionary = {}
) -> bool:
	var view: PresentView = get_view(view_id)

	if view == null:
		return false

	return view.toggle(data)


func pause_view(view_id: StringName) -> bool:
	var view: PresentView = get_view(view_id)

	if view == null:
		return false

	return view.pause()


func resume_view(view_id: StringName) -> bool:
	var view: PresentView = get_view(view_id)

	if view == null:
		return false

	return view.resume()


func close_top() -> bool:
	_clean_open_stack()

	if _open_stack.is_empty():
		return false

	var view_id: StringName = _open_stack.back()

	return close_view(view_id)


func open_kind(kind_id: int) -> bool:
	var success: bool = true

	for view_id in get_kind_ids(kind_id):
		if not open_view(view_id):
			success = false

	return success


func close_kind(kind_id: int) -> bool:
	var success: bool = true
	var view_ids: Array[StringName] = get_kind_ids(kind_id)

	view_ids.reverse()

	for view_id in view_ids:
		var view: PresentView = get_view(view_id)

		if view == null:
			continue

		if view.is_active() and not view.close():
			success = false

	return success


func pause_all() -> bool:
	var success: bool = true

	for view_id in _get_view_ids_copy():
		var view: PresentView = get_view(view_id)

		if view == null:
			continue

		if view.is_open() and not view.pause():
			success = false

	return success


func resume_all() -> bool:
	var success: bool = true

	for view_id in _get_view_ids_copy():
		var view: PresentView = get_view(view_id)

		if view == null:
			continue

		if view.is_paused() and not view.resume():
			success = false

	return success


func close_all() -> bool:
	var success: bool = true
	var closed_ids: Dictionary = {}
	var stack_ids: Array[StringName] = []

	stack_ids.assign(_open_stack)
	stack_ids.reverse()

	for view_id in stack_ids:
		var view: PresentView = get_view(view_id)

		if view == null:
			continue

		closed_ids[view_id] = true

		if view.is_active() and not view.close():
			success = false

	var view_ids: Array[StringName] = _get_view_ids_copy()
	view_ids.reverse()

	for view_id in view_ids:
		if closed_ids.has(view_id):
			continue

		var view: PresentView = get_view(view_id)

		if view == null:
			continue

		if view.is_active() and not view.close():
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


func get_error() -> String:
	return presentation_error


func _open_auto_views() -> bool:
	var success: bool = true

	for view_id in _get_view_ids_copy():
		var view: PresentView = get_view(view_id)

		if view == null:
			continue

		if view.auto_open and not view.open():
			success = false

	return success


func _register_existing_children() -> void:
	for child in get_children():
		if child is PresentView:
			register_view(child)


func _connect_view(view: PresentView) -> void:
	if not view.view_opening.is_connected(_on_view_opening):
		view.view_opening.connect(_on_view_opening)

	if not view.view_opened.is_connected(_on_view_opened):
		view.view_opened.connect(_on_view_opened)

	if not view.view_closing.is_connected(_on_view_closing):
		view.view_closing.connect(_on_view_closing)

	if not view.view_closed.is_connected(_on_view_closed):
		view.view_closed.connect(_on_view_closed)

	if not view.view_paused.is_connected(_on_view_paused):
		view.view_paused.connect(_on_view_paused)

	if not view.view_resumed.is_connected(_on_view_resumed):
		view.view_resumed.connect(_on_view_resumed)

	if not view.view_failed.is_connected(_on_view_failed):
		view.view_failed.connect(_on_view_failed)


func _disconnect_view(view: PresentView) -> void:
	if not is_instance_valid(view):
		return

	if view.view_opening.is_connected(_on_view_opening):
		view.view_opening.disconnect(_on_view_opening)

	if view.view_opened.is_connected(_on_view_opened):
		view.view_opened.disconnect(_on_view_opened)

	if view.view_closing.is_connected(_on_view_closing):
		view.view_closing.disconnect(_on_view_closing)

	if view.view_closed.is_connected(_on_view_closed):
		view.view_closed.disconnect(_on_view_closed)

	if view.view_paused.is_connected(_on_view_paused):
		view.view_paused.disconnect(_on_view_paused)

	if view.view_resumed.is_connected(_on_view_resumed):
		view.view_resumed.disconnect(_on_view_resumed)

	if view.view_failed.is_connected(_on_view_failed):
		view.view_failed.disconnect(_on_view_failed)


func _on_view_opening(view_id: StringName) -> void:
	view_opening.emit(view_id)


func _on_view_opened(view_id: StringName) -> void:
	_push_open(view_id)

	view_opened.emit(view_id)


func _on_view_closing(view_id: StringName) -> void:
	view_closing.emit(view_id)


func _on_view_closed(view_id: StringName) -> void:
	_open_stack.erase(view_id)

	view_closed.emit(view_id)

	_update_active()


func _on_view_paused(view_id: StringName) -> void:
	view_paused.emit(view_id)


func _on_view_resumed(view_id: StringName) -> void:
	_push_open(view_id)

	view_resumed.emit(view_id)


func _on_view_failed(
	view_id: StringName,
	reason: String
) -> void:
	_open_stack.erase(view_id)

	view_failed.emit(view_id, reason)

	_update_active()

	_log_error(
		"View Failed ["
		+ String(view_id)
		+ "]: "
		+ reason
	)


func _push_open(view_id: StringName) -> void:
	_open_stack.erase(view_id)
	_open_stack.append(view_id)

	_update_active()


func _clean_open_stack() -> void:
	var clean_stack: Array[StringName] = []

	for view_id in _open_stack:
		var view: PresentView = get_view(view_id)

		if view != null and view.is_active():
			clean_stack.append(view_id)

	_open_stack = clean_stack


func _update_active() -> void:
	_clean_open_stack()

	var next_id: StringName = &""

	if not _open_stack.is_empty():
		next_id = _open_stack.back()

	if next_id == _active_id:
		return

	_active_id = next_id

	active_changed.emit(_active_id)


func _get_view_ids_copy() -> Array[StringName]:
	var result: Array[StringName] = []

	for view_id in _view_order:
		if _views.has(view_id):
			result.append(view_id)

	return result


func _validate_root() -> bool:
	presentation_error = ""

	if not is_inside_tree():
		presentation_error = "Presentation không nằm trong SceneTree"
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Presentation: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
			% [EXPECTED_NODE_NAME, name]
		)

	return true


func _fail(reason: String) -> bool:
	state = State.FAILED
	presentation_error = reason

	presentation_failed.emit(reason)

	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING

	presentation_stopping.emit()

	if close_on_exit:
		close_all()

	state = State.STOPPED

	presentation_stopped.emit()

	_log("Presentation Stopped")


func _log(message: String) -> void:
	if console_output:
		print("[Presentation] ", message)


func _log_error(message: String) -> void:
	push_error("[Presentation] " + message) 
