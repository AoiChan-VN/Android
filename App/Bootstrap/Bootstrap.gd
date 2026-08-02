class_name Bootstrap
extends Node

signal boot_started
signal boot_completed
signal boot_failed(reason: String)
signal shutdown_started
signal shutdown_completed

enum State {
	IDLE,
	STARTING,
	READY,
	FAILED,
	STOPPING,
	STOPPED
}

const EXPECTED_NODE_NAME: StringName = &"Bootstrap"

@export_group("Startup")
@export var auto_start: bool = true
@export var console_output: bool = true

var state: int = State.IDLE
var boot_error: String = ""


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

	if state == State.FAILED:
		return false

	if state == State.STOPPING or state == State.STOPPED:
		return false

	boot_started.emit()

	if not _validate_root():
		state = State.FAILED
		boot_failed.emit(boot_error)
		_log_error(boot_error)
		return false

	state = State.READY
	boot_completed.emit()
	_log("Bootstrap Ready")

	return true


func _validate_root() -> bool:
	boot_error = ""

	var root_node: Node = self

	if not is_inside_tree():
		boot_error = "Bootstrap không nằm trong SceneTree"
		return false

	if get_tree().current_scene != root_node:
		push_warning("Bootstrap: Node gốc hiện tại không phải Main Scene")

	if name != EXPECTED_NODE_NAME:
		push_warning("Bootstrap: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node." % [EXPECTED_NODE_NAME, name])

	return true


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING
	shutdown_started.emit()

	state = State.STOPPED
	shutdown_completed.emit()
	_log("Bootstrap Stopped")


func _log(message: String) -> void:
	if console_output:
		print("[Bootstrap] ", message)


func _log_error(message: String) -> void:
	push_error("[Bootstrap] " + message)
