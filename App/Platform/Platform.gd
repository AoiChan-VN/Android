class_name Platform
extends Node

signal platform_started
signal platform_ready
signal platform_failed(reason: String)
signal platform_stopped
signal platform_changed

enum State {
	IDLE,
	STARTING,
	READY,
	FAILED,
	STOPPING,
	STOPPED
}

enum PlatformType {
	UNKNOWN,
	MOBILE,
	DESKTOP,
	WEB,
	SERVER
}

const EXPECTED_NODE_NAME: StringName = &"Platform"

@export_group("Platform")
@export var auto_start: bool = true
@export var console_output: bool = true

@export_group("Detection")
@export var detect_os: bool = true
@export var detect_display: bool = true
@export var detect_renderer: bool = true
@export var detect_hardware: bool = true

var state: State = State.IDLE
var platform_error: String = ""

var platform_type: PlatformType = PlatformType.UNKNOWN

var os_name: String = ""
var os_distribution: String = ""
var processor_name: String = ""

var display_server: String = ""
var rendering_method: String = ""

var screen_count: int = 0
var primary_screen: int = 0
var screen_size: Vector2i = Vector2i.ZERO
var screen_scale: float = 1.0
var screen_dpi: int = 0
var screen_refresh_rate: float = -1.0
var screen_orientation: DisplayServer.ScreenOrientation = DisplayServer.SCREEN_LANDSCAPE

var is_mobile: bool = false
var is_desktop: bool = false
var is_web: bool = false
var is_server: bool = false
var is_headless: bool = false


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

	platform_started.emit()

	if not _validate_root():
		return _fail(platform_error)

	if detect_os:
		_detect_os()

	if detect_display:
		_detect_display()

	if detect_renderer:
		_detect_renderer()

	if detect_hardware:
		_detect_hardware()

	_detect_platform_type()

	state = State.READY

	platform_ready.emit()
	platform_changed.emit()

	_log("Platform Ready")
	_log_platform()

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func refresh() -> bool:
	if state != State.READY:
		return false

	if detect_os:
		_detect_os()

	if detect_display:
		_detect_display()

	if detect_renderer:
		_detect_renderer()

	if detect_hardware:
		_detect_hardware()

	_detect_platform_type()

	platform_changed.emit()

	_log("Platform Refreshed")

	return true


func get_platform_type() -> PlatformType:
	return platform_type


func get_platform_type_name() -> String:
	match platform_type:
		PlatformType.MOBILE:
			return "Mobile"
		PlatformType.DESKTOP:
			return "Desktop"
		PlatformType.WEB:
			return "Web"
		PlatformType.SERVER:
			return "Server"
		PlatformType.UNKNOWN:
			return "Unknown"

	return "Unknown"


func get_os_name() -> String:
	return os_name


func get_os_distribution() -> String:
	return os_distribution


func get_processor_name() -> String:
	return processor_name


func get_display_server() -> String:
	return display_server


func get_rendering_method() -> String:
	return rendering_method


func get_screen_count() -> int:
	return screen_count


func get_primary_screen() -> int:
	return primary_screen


func get_screen_size() -> Vector2i:
	return screen_size


func get_screen_scale() -> float:
	return screen_scale


func get_screen_dpi() -> int:
	return screen_dpi


func get_screen_refresh_rate() -> float:
	return screen_refresh_rate


func get_screen_orientation() -> DisplayServer.ScreenOrientation:
	return screen_orientation


func is_mobile_platform() -> bool:
	return is_mobile


func is_desktop_platform() -> bool:
	return is_desktop


func is_web_platform() -> bool:
	return is_web


func is_server_platform() -> bool:
	return is_server


func is_headless_platform() -> bool:
	return is_headless


func is_ready() -> bool:
	return state == State.READY


func is_failed() -> bool:
	return state == State.FAILED


func is_stopped() -> bool:
	return state == State.STOPPED


func get_state() -> State:
	return state


func get_platform_error() -> String:
	return platform_error


func _detect_os() -> void:
	os_name = OS.get_name()
	os_distribution = OS.get_distribution_name()


func _detect_display() -> void:
	display_server = DisplayServer.get_name()

	if display_server == "headless":
		is_headless = true
		screen_count = 0
		primary_screen = 0
		screen_size = Vector2i.ZERO
		screen_scale = 1.0
		screen_dpi = 0
		screen_refresh_rate = -1.0
		screen_orientation = DisplayServer.SCREEN_LANDSCAPE
		return

	is_headless = false

	screen_count = DisplayServer.get_screen_count()
	primary_screen = DisplayServer.get_primary_screen()

	screen_size = DisplayServer.screen_get_size(DisplayServer.SCREEN_PRIMARY)
	screen_scale = DisplayServer.screen_get_scale(DisplayServer.SCREEN_PRIMARY)
	screen_dpi = DisplayServer.screen_get_dpi(DisplayServer.SCREEN_PRIMARY)
	screen_refresh_rate = DisplayServer.screen_get_refresh_rate(DisplayServer.SCREEN_PRIMARY)
	screen_orientation = DisplayServer.screen_get_orientation(DisplayServer.SCREEN_PRIMARY)


func _detect_renderer() -> void:
	rendering_method = RenderingServer.get_current_rendering_method()


func _detect_hardware() -> void:
	processor_name = OS.get_processor_name()


func _detect_platform_type() -> void:
	is_mobile = false
	is_desktop = false
	is_web = false
	is_server = false

	if is_headless:
		is_server = true
		platform_type = PlatformType.SERVER
		return

	match os_name:
		"Android", "iOS":
			is_mobile = true
			platform_type = PlatformType.MOBILE

		"Windows", "Linux", "macOS":
			is_desktop = true
			platform_type = PlatformType.DESKTOP

		"Web":
			is_web = true
			platform_type = PlatformType.WEB

		_:
			platform_type = PlatformType.UNKNOWN


func _validate_root() -> bool:
	platform_error = ""

	if not is_inside_tree():
		platform_error = "Platform không nằm trong SceneTree"
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Platform: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
			% [EXPECTED_NODE_NAME, name]
		)

	return true


func _fail(reason: String) -> bool:
	state = State.FAILED
	platform_error = reason

	platform_failed.emit(reason)
	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING

	_log("Platform Stopping")

	state = State.STOPPED

	platform_stopped.emit()

	_log("Platform Stopped")


func _log_platform() -> void:
	if not console_output:
		return

	print("[Platform] Type: ", get_platform_type_name())
	print("[Platform] OS: ", os_name)
	print("[Platform] Distribution: ", os_distribution)
	print("[Platform] Display: ", display_server)
	print("[Platform] Renderer: ", rendering_method)
	print("[Platform] Processor: ", processor_name)
	print("[Platform] Screen Count: ", screen_count)
	print("[Platform] Screen Size: ", screen_size)
	print("[Platform] Screen Scale: ", screen_scale)
	print("[Platform] Screen DPI: ", screen_dpi)
	print("[Platform] Refresh Rate: ", screen_refresh_rate)


func _log(message: String) -> void:
	if console_output:
		print("[Platform] ", message)


func _log_error(message: String) -> void:
	push_error("[Platform] " + message) 
