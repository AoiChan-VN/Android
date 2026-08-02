class_name Core
extends Node

signal core_started
signal core_ready
signal core_failed(reason: String)
signal core_stopped

enum State {
	IDLE,
	STARTING,
	READY,
	FAILED,
	STOPPING,
	STOPPED
}

const EXPECTED_NODE_NAME: StringName = &"Core"
const EXPECTED_ENGINE_MAJOR: int = 4
const EXPECTED_ENGINE_MINOR: int = 7
const EXPECTED_ENGINE_PATCH: int = 1
const EXPECTED_RENDERING_METHOD: StringName = &"gl_compatibility"

@export_group("Core")
@export var auto_start: bool = true
@export var console_output: bool = true

@export_group("Validation")
@export var validate_engine: bool = true
@export var validate_renderer: bool = true

var state: int = State.IDLE
var core_error: String = ""
var engine_version: Dictionary = {}
var rendering_method: String = ""


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

	core_started.emit()

	if not _validate_root():
		return _fail(core_error)

	if validate_engine and not _validate_engine():
		return _fail(core_error)

	if validate_renderer and not _validate_renderer():
		return _fail(core_error)

	state = State.READY
	core_ready.emit()
	_log("Core Ready")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func is_ready() -> bool:
	return state == State.READY


func is_failed() -> bool:
	return state == State.FAILED


func get_state() -> int:
	return state


func get_engine_version() -> Dictionary:
	return engine_version.duplicate()


func get_rendering_method() -> String:
	return rendering_method


func _validate_root() -> bool:
	core_error = ""

	if not is_inside_tree():
		core_error = "Core không nằm trong SceneTree"
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Core: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
			% [EXPECTED_NODE_NAME, name]
		)

	return true


func _validate_engine() -> bool:
	engine_version = Engine.get_version_info()

	var major: int = int(engine_version.get("major", -1))
	var minor: int = int(engine_version.get("minor", -1))
	var patch: int = int(engine_version.get("patch", -1))

	if major != EXPECTED_ENGINE_MAJOR:
		core_error = "Core: Godot Engine Major Version không tương thích"
		return false

	if minor != EXPECTED_ENGINE_MINOR:
		core_error = "Core: Godot Engine Minor Version không tương thích"
		return false

	if patch != EXPECTED_ENGINE_PATCH:
		core_error = "Core: Godot Engine Patch Version không tương thích"
		return false

	return true


func _validate_renderer() -> bool:
	rendering_method = RenderingServer.get_current_rendering_method()

	if rendering_method != EXPECTED_RENDERING_METHOD:
		core_error = "Core: Rendering Method không tương thích"
		return false

	return true


func _fail(reason: String) -> bool:
	state = State.FAILED
	core_error = reason
	core_failed.emit(reason)
	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING
	_log("Core Stopping")

	state = State.STOPPED
	core_stopped.emit()
	_log("Core Stopped")


func _log(message: String) -> void:
	if console_output:
		print("[Core] ", message)


func _log_error(message: String) -> void:
	push_error("[Core] " + message) 
