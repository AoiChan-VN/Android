extends Camera3D
class_name BlockInteraction

# Khoảng cách tối đa mà người chơi có thể tương tác với Block (tính bằng mét)
const INTERACTION_DISTANCE: float = 5.0

@export var world_manager: Node3D = null

func _unhandled_input(event: InputEvent) -> void:
	if world_manager == null:
		return
		
	# Phân tách hành vi tương tác trên UI Mobile thông qua cử chỉ chạm màn hình nhanh (Tap)
	if event is InputEventScreenTouch and event.pressed:
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		var half_width: float = viewport_size.x / 2.0
		
		# Chỉ kích hoạt tương tác nếu người dùng tap vào nửa phải màn hình (tránh trùng vùng Joystick trái)
		if event.position.x >= half_width:
			# Mặc định trên thiết bị di động: Tap nhanh tương đương với hành động Phá Block
			# Nếu bạn có nút bấm đặt block riêng trên UI, bạn sẽ gọi trực tiếp hàm execute_place_block()
			execute_destroy_block()

# Hàm xử lý logic bắn tia vật lý và phá hủy Block
func execute_destroy_block() -> void:
	var hit_result: Dictionary = _perform_raycast()
	if hit_result.is_empty():
		return
		
	var hit_position: Vector3 = hit_result["position"]
	var normal: Vector3 = hit_result["normal"]
	
	# Lùi tọa độ vào sâu trong khối Voxel một khoảng nhỏ để tìm chính xác Block bị trúng tia
	var target_block_pos: Vector3 = hit_position - (normal * 0.1)
	var block_global_coord: Vector3i = Vector3i(
		floori(target_block_pos.x),
		floori(target_block_pos.y),
		floori(target_block_pos.z)
	)
	
	_modify_world_block(block_global_coord, BlockRegistry.BlockType.AIR)

# Hàm xử lý logic bắn tia vật lý và đặt một Block mới lên bề mặt
func execute_place_block(block_type_to_place: int) -> void:
	if block_type_to_place == BlockRegistry.BlockType.AIR:
		return
		
	var hit_result: Dictionary = _perform_raycast()
	if hit_result.is_empty():
		return
		
	var hit_position: Vector3 = hit_result["position"]
	var normal: Vector3 = hit_result["normal"]
	
	# Tiến tọa độ ra phía ngoài bề mặt va chạm dựa trên Vector pháp tuyến để tìm vị trí trống đặt Block
	var target_block_pos: Vector3 = hit_position + (normal * 0.1)
	var block_global_coord: Vector3i = Vector3i(
		floori(target_block_pos.x),
		floori(target_block_pos.y),
		floori(target_block_pos.z)
	)
	
	# Ngăn chặn việc đặt block đè lên chính vị trí của người chơi
	if _is_colliding_with_player(block_global_coord):
		return
		
	_modify_world_block(block_global_coord, block_type_to_place)

# Khởi tạo ma trận không gian vật lý để thực hiện Ray Casting theo thời gian thực
func _perform_raycast() -> Dictionary:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space_state == null:
		return {}
		
	var origin: Vector3 = global_position
	var end: Vector3 = origin - global_transform.basis.z * INTERACTION_DISTANCE
	
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, end)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	
	# Loại trừ chính thực thể người chơi khỏi danh sách va chạm của tia bắn ra
	var parent_player: CharacterBody3D = get_parent() as CharacterBody3D
	if parent_player != null:
		query.exclude = [parent_player.get_rid()]
		
	return space_state.intersect_ray(query)

# Truy vấn vị trí Chunk, cập nhật mảng dữ liệu thô và dựng lại Mesh hình học tương ứng
func _modify_world_block(global_coord: Vector3i, new_block_id: int) -> void:
	var chunk_width: int = WorldManager.CHUNK_WIDTH
	var chunk_height: int = WorldManager.CHUNK_HEIGHT
	
	if global_coord.y < 0 or global_coord.y >= chunk_height:
		return
		
	var chunk_x: int = floori(float(global_coord.x) / float(chunk_width))
	var chunk_z: int = floori(float(global_coord.z) / float(chunk_width))
	var target_chunk_pos: Vector2i = Vector2i(chunk_x, chunk_z)
	
	# Định vị Node Chunk mục tiêu trong danh sách quản lý của World Manager
	var target_chunk: Chunk = world_manager._active_chunks.get(target_chunk_pos) as Chunk
	if target_chunk == null:
		return
		
	# Chuyển đổi tọa độ toàn cục sang tọa độ cục bộ bên trong mảng 3 chiều của Chunk
	var local_x: int = global_coord.x - (chunk_x * chunk_width)
	var local_z: int = global_coord.z - (chunk_z * chunk_width)
	
	if target_chunk.is_inside_chunk(local_x, global_coord.y, local_z):
		target_chunk._blocks[local_x][global_coord.y][local_z] = new_block_id
		# Tái cấu trúc lại mô hình lưới đa giác phẳng và hộp va chạm vật lý cho Chunk
		target_chunk.update_mesh(world_manager.terrain_material)
		
		# Tối ưu hóa Mobile: Kiểm tra nếu block sửa đổi nằm ở biên Chunk -> Dựng lại cả Chunk lân cận tránh lỗi thủng lỗ đồ họa
		_update_neighbor_chunk_if_needed(local_x, local_z, target_chunk_pos)

func _update_neighbor_chunk_if_needed(local_x: int, local_z: int, current_chunk_pos: Vector2i) -> void:
	var chunk_width: int = WorldManager.CHUNK_WIDTH
	var neighbor_positions: Array[Vector2i] = []
	
	if local_x == 0:
		neighbor_positions.append(current_chunk_pos + Vector2i(-1, 0))
	elif local_x == chunk_width - 1:
		neighbor_positions.append(current_chunk_pos + Vector2i(1, 0))
		
	if local_z == 0:
		neighbor_positions.append(current_chunk_pos + Vector2i(0, -1))
	elif local_z == chunk_width - 1:
		neighbor_positions.append(current_chunk_pos + Vector2i(0, 1))
		
	for n_pos in neighbor_positions:
		var n_chunk: Chunk = world_manager._active_chunks.get(n_pos) as Chunk
		if n_chunk != null:
			n_chunk.update_mesh(world_manager.terrain_material)

# Kiểm tra xem tọa độ đặt block mới có trùng với bounding box của người chơi không
func _is_colliding_with_player(target_coord: Vector3i) -> bool:
	var parent_player: CharacterBody3D = get_parent() as CharacterBody3D
	if parent_player == null:
		return false
		
	var p_pos: Vector3 = parent_player.global_position
	# Giả lập hộp va chạm của nhân vật cao 2 block rộng 0.6 block (Cylinder radius 0.3)
	var p_min_x: int = floori(p_pos.x - 0.3)
	var p_max_x: int = floori(p_pos.x + 0.3)
	var p_min_z: int = floori(p_pos.z - 0.3)
	var p_max_z: int = floori(p_pos.z + 0.3)
	var p_min_y: int = floori(p_pos.y)
	var p_max_y: int = floori(p_pos.y + 1.8)
	
	return (target_coord.x >= p_min_x and target_coord.x <= p_max_x) and \
		   (target_coord.z >= p_min_z and target_coord.z <= p_max_z) and \
		   (target_coord.y >= p_min_y and target_coord.y <= p_max_y)
 
