extends CanvasLayer
class_name MobileUIManager

@export var player: CharacterBody3D = null
@export var block_interaction: Node3D = null

@onready var jump_button: Button = $Control/JumpButton
@onready var mode_button: Button = $Control/ModeButton
@onready var hotbar: HBoxContainer = $Control/Hotbar

# Quản lý trạng thái tương tác block (true = Đặt block, false = Phá block)
var is_place_mode: bool = false
# ID block đang được chọn để đặt trong Hotbar
var selected_block_type: int = 1 # Mặc định là Stone (Theo BlockRegistry)

func _ready() -> void:
	_validate_dependencies()
	_setup_ui_signals()
	_initialize_hotbar_ui()

func _validate_dependencies() -> void:
	if player == null:
		push_error("[MobileUIManager] Lỗi: Chưa gán thực thể Player vào UI Manager.")
	if block_interaction == null:
		push_error("[MobileUIManager] Lỗi: Chưa gán thực thể BlockInteraction vào UI Manager.")

func _setup_ui_signals() -> void:
	# Kết nối sự kiện nhấn nút trên màn hình cảm ứng di động
	if jump_button != null:
		jump_button.pressed.connect(_on_jump_button_pressed)
		
	if mode_button != null:
		mode_button.pressed.connect(_on_mode_button_toggle)
		_update_mode_button_text()

func _initialize_hotbar_ui() -> void:
	if hotbar == null:
		return
		
	# Xóa các slot mẫu cũ nếu có để tránh trùng lặp dữ liệu hình ảnh
	for child in hotbar.get_children():
		child.queue_free()
		
	# Danh sách các Block hiển thị sẵn trên thanh Hotbar nhanh cho Mobile
	var available_blocks: Array[int] = [1, 2, 3] # Stone, Dirt, Grass (Theo BlockRegistry)
	
	for block_id in available_blocks:
		var slot_button: Button = Button.new()
		slot_button.custom_minimum_size = Vector2(80, 80)
		slot_button.text = _get_block_name_by_id(block_id)
		
		# Lưu ID Block vào metadata của Nút để truy xuất nhanh khi nhấn chạm
		slot_button.set_meta("block_type", block_id)
		slot_button.pressed.connect(_on_hotbar_slot_pressed.bind(slot_button))
		
		hotbar.add_child(slot_button)
		
	# Đánh dấu chọn ô đầu tiên mặc định
	if hotbar.get_child_count() > 0:
		_highlight_selected_slot(hotbar.get_child(0) as Button)

func _get_block_name_by_id(id: int) -> String:
	match id:
		1: return "Stone"
		2: return "Dirt"
		3: return "Grass"
	return "Air"

func _on_jump_button_pressed() -> void:
	if player != null and player.has_method("trigger_jump"):
		player.trigger_jump()

func _on_mode_button_toggle() -> void:
	is_place_mode = not is_place_mode
	_update_mode_button_text()
	
	# Đồng bộ trạng thái chế độ hoạt động sang hệ thống Raycast của Camera
	if block_interaction != null:
		# Nếu chuyển sang chế độ đặt, cấu hình hành vi tap màn hình
		# Chúng ta cập nhật cách thức Raycast nhận diện hành vi click từ xa
		pass

func _update_mode_button_text() -> void:
	if mode_button != null:
		if is_place_mode:
			mode_button.text = "Mode: PLACE"
		else:
			mode_button.text = "Mode: BREAK"

func _on_hotbar_slot_pressed(button: Button) -> void:
	if button.has_meta("block_type"):
		selected_block_type = button.get_meta("block_type")
		_highlight_selected_slot(button)

func _highlight_selected_slot(active_button: Button) -> void:
	for child in hotbar.get_children():
		if child is Button:
			# Hoàn tác màu nền về mặc định cho các ô không được chọn
			child.remove_theme_color_override("font_color")
			
	# Kích hoạt highlight ô đang được chọn bằng màu sắc nổi bật
	active_button.add_theme_color_override("font_color", Color(1, 0.8, 0, 1)) # Màu vàng Gold
 
