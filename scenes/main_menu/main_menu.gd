extends Control

signal play_pressed
signal shop_pressed
signal inventory_pressed
signal admin_triggered

@export var play_button: Button
@export var shop_button: Button
@export var inventory_button: Button
@export var logo_rect: TextureRect

var _logo_tap_count: int = 0
var _last_tap_time: float = 0.0

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	shop_button.pressed.connect(_on_shop_pressed)
	inventory_button.pressed.connect(_on_inventory_pressed)
	logo_rect.gui_input.connect(_on_logo_gui_input)

func _on_play_pressed() -> void:
	play_pressed.emit()

func _on_shop_pressed() -> void:
	shop_pressed.emit()

func _on_inventory_pressed() -> void:
	inventory_pressed.emit()

func _on_logo_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - _last_tap_time > 0.5:
			_logo_tap_count = 0
		_last_tap_time = current_time
		_logo_tap_count += 1
		if _logo_tap_count >= 5:
			_logo_tap_count = 0
			admin_triggered.emit()
