extends CharacterBody3D
class_name PlayerController

# Các thông số vật lý cấu hình chuẩn cho chuyển động
const SPEED: float = 4.5
const JUMP_VELOCITY: float = 6.0
const MOUSE_SENSITIVITY: float = 0.2

@onready var camera: Camera3D = $Camera3D

# Lấy giá trị trọng lực mặc định từ cấu hình hệ thống của dự án
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Biến lưu trữ trạng thái cảm ứng di động
var _left_touch_index: int = -1
var _right_touch_index: int = -1
var _joystick_center: Vector2 = Vector2.ZERO
var _joystick_vector: Vector2 = Vector2.ZERO
var _camera_rotation: Vector2 = Vector2.ZERO

# Bán kính hoạt động tối đa của Joystick ảo (tính bằng pixel)
var _joystick_max_length: float = 100.0

func _ready() -> void:
	if camera == null:
		push_error("[PlayerController] Lỗi: Chưa tìm thấy Node Camera3D con.")
		return
	
	# Khởi tạo góc xoay ban đầu dựa trên trạng thái camera hiện tại
	_camera_rotation.x = rotation.y
	_camera_rotation.y = camera.rotation.x

func _unhandled_input(event: InputEvent) -> void:
	# Xử lý các sự kiện chạm và vuốt trên màn hình cảm ứng di động
	if event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)

func _physics_process(delta: float) -> void:
	# 1. Xử lý trọng lực hệ thống
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		if velocity.y < 0:
			velocity.y = 0.0

	# 2. Tính toán hướng di chuyển dựa trên dữ liệu Vector của Joystick ảo
	var direction: Vector3 = Vector3.ZERO
	if _joystick_vector.length_squared() > 0.001:
		var forward: Vector3 = -global_transform.basis.z
		var right: Vector3 = global_transform.basis.x
		# Triệt tiêu trục Y để tránh nhân vật bay lên/cắm xuống đất khi di chuyển
		forward.y = 0.0
		right.y = 0.0
		forward = forward.normalized()
		right = right.normalized()
		
		var move_dir: Vector2 = _joystick_vector.normalized()
		direction = (right * move_dir.x + forward * move_dir.y).normalized()

	# 3. Áp dụng vận tốc di chuyển vào hệ thống Physics Body
	if direction != Vector3.ZERO:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)

	# Thực hiện di chuyển vật lý và tự động tính toán va chạm góc nghiêng (Slopes)
	move_and_slide()

# Phân tách tọa độ chạm màn hình để kích hoạt điều khiển
func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var half_width: float = viewport_size.x / 2.0
	
	if event.pressed:
		# Nửa trái màn hình khởi tạo vùng điều khiển Joystick di chuyển
		if event.position.x < half_width and _left_touch_index == -1:
			_left_touch_index = event.index
			_joystick_center = event.position
			_joystick_vector = Vector2.ZERO
		# Nửa phải màn hình dùng để kích hoạt xoay góc nhìn Camera
		elif event.position.x >= half_width and _right_touch_index == -1:
			_right_touch_index = event.index
	else:
		# Giải phóng các chỉ mục touch khi người dùng nhấc tay khỏi màn hình
		if event.index == _left_touch_index:
			_left_touch_index = -1
			_joystick_vector = Vector2.ZERO
		elif event.index == _right_touch_index:
			_right_touch_index = -1

# Xử lý hành vi kéo/vuốt ngón tay
func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if event.index == _left_touch_index:
		# Tính toán biên độ dịch chuyển của ngón tay so với tâm Joystick ban đầu
		var drag_vector: Vector2 = event.position - _joystick_center
		if drag_vector.length() > _joystick_max_length:
			_joystick_vector = drag_vector.normalized()
		else:
			_joystick_vector = drag_vector / _joystick_max_length
			
	elif event.index == _right_touch_index:
		# Xử lý xoay góc nhìn Camera từ dữ liệu vuốt của ngón tay phải
		var relative_motion: Vector2 = event.relative * MOUSE_SENSITIVITY * 0.05
		
		_camera_rotation.x -= relative_motion.x
		# Giới hạn góc nhìn ngước lên/cúi xuống trong khoảng gần 90 độ để tránh lật Camera
		_camera_rotation.y = clampf(_camera_rotation.y - relative_motion.y, deg_to_rad(-89.0), deg_to_rad(89.0))
		
		# Áp dụng góc xoay trực tiếp vào Body (xoay ngang) và Camera con (xoay dọc)
		rotation.y = _camera_rotation.x
		camera.rotation.x = _camera_rotation.y

# Hàm kích hoạt lệnh nhảy cao từ UI (Sẽ được gọi khi nhấn nút Jump chuyên dụng trên UI Mobile)
func trigger_jump() -> void:
	if is_on_floor():
		velocity.y = JUMP_VELOCITY
 
