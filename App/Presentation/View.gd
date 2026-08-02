class_name PresentView
extends CanvasLayer

signal view_opening(view_id: StringName)
signal view_opened(view_id: StringName)
signal view_closing(view_id: StringName)
signal view_closed(view_id: StringName)
signal view_paused(view_id: StringName)
signal view_resumed(view_id: StringName)
signal view_failed(view_id: StringName, reason: String)

enum Kind {
	UI,
	UX,
	HUD,
	DIALOG,
	DEBUG,
	CUSTOM
}

enum State {
	CLOSED,
	OPENING,
	OPEN,
	PAUSED,
	CLOSING,
	FAILED
}

@export_group("View")
@export var view_id: StringName = &""
@export var kind: Kind = Kind.UI
@export var auto_open: bool = false
@export var close_on_cancel: bool = false
@export var order: int = 0
@export var console_output: bool = true

var state: State = State.CLOSED
var view_error: String = ""

var _payload: Dictionary = {}


func _enter_tree() -> void:
	state = State.CLOSED


func _ready() -> void:
	layer = order
	visible = false
	set_process_unhandled_input(false)


func _unhandled_input(event: InputEvent) -> void:
	if state != State.OPEN:
		return

	if not close_on_cancel:
		return

	if event.is_action_pressed(&"ui_cancel"):
		if close():
			get_viewport().set_input_as_handled()


func open(data: Dictionary = {}) -> bool:
	if state == State.OPEN:
		return true

	if state == State.PAUSED:
		return resume()

	if state == State.OPENING or state == State.CLOSING:
		return false

	if state == State.FAILED:
		state = State.CLOSED
		view_error = ""

	if not _validate_view():
		return _fail(view_error)

	state = State.OPENING
	_payload = data.duplicate(true)

	view_opening.emit(view_id)

	visible = true

	if not _on_view_open(_payload):
		visible = false

		if view_error.is_empty():
			view_error = "View không thể mở"

		return _fail(view_error)

	state = State.OPEN

	set_process_unhandled_input(close_on_cancel)

	view_opened.emit(view_id)

	_log("View Opened")

	return true


func close() -> bool:
	if state == State.CLOSED:
		return true

	if state == State.OPENING or state == State.CLOSING:
		return false

	if state == State.FAILED:
		visible = false
		state = State.CLOSED
		_payload.clear()
		return true

	if state != State.OPEN and state != State.PAUSED:
		return false

	state = State.CLOSING

	view_closing.emit(view_id)

	if not _on_view_close():
		state = State.OPEN
		return false

	visible = false
	set_process_unhandled_input(false)

	state = State.CLOSED
	_payload.clear()

	view_closed.emit(view_id)

	_log("View Closed")

	return true


func toggle(data: Dictionary = {}) -> bool:
	if state == State.OPEN or state == State.PAUSED:
		return close()

	return open(data)


func pause() -> bool:
	if state != State.OPEN:
		return false

	if not _on_view_pause():
		return false

	state = State.PAUSED

	set_process_unhandled_input(false)

	view_paused.emit(view_id)

	_log("View Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	if not _on_view_resume():
		return false

	state = State.OPEN

	set_process_unhandled_input(close_on_cancel)

	view_resumed.emit(view_id)

	_log("View Resumed")

	return true


func set_order(value: int) -> void:
	order = value
	layer = value


func get_view_id() -> StringName:
	return view_id


func get_kind() -> Kind:
	return kind


func get_state() -> State:
	return state


func get_error() -> String:
	return view_error


func get_payload() -> Dictionary:
	return _payload.duplicate(true)


func is_open() -> bool:
	return state == State.OPEN


func is_paused() -> bool:
	return state == State.PAUSED


func is_closed() -> bool:
	return state == State.CLOSED


func is_failed() -> bool:
	return state == State.FAILED


func is_active() -> bool:
	return state == State.OPEN or state == State.PAUSED


func _validate_view() -> bool:
	view_error = ""

	if not is_inside_tree():
		view_error = "View không nằm trong SceneTree"
		return false

	if view_id.is_empty():
		view_error = "View ID không được để trống"
		return false

	return true


func _on_view_open(_data: Dictionary) -> bool:
	return true


func _on_view_close() -> bool:
	return true


func _on_view_pause() -> bool:
	return true


func _on_view_resume() -> bool:
	return true


func _fail(reason: String) -> bool:
	state = State.FAILED
	view_error = reason

	set_process_unhandled_input(false)

	view_failed.emit(view_id, reason)

	_log_error(reason)

	return false


func _log(message: String) -> void:
	if console_output:
		print("[View:", view_id, "] ", message)


func _log_error(message: String) -> void:
	push_error("[View:%s] %s" % [view_id, message]) 
