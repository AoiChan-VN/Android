extends StaticBody3D
class_name Chunk

# Kích thước tiêu chuẩn của một Chunk tối ưu cho Mobile
const CHUNK_WIDTH: int = 16
const CHUNK_HEIGHT: int = 64

# Ma trận 3 chiều lưu trữ ID của Block [x][y][z]
var _blocks: Array = []
var chunk_position: Vector2i = Vector2i.ZERO

@onready var mesh_instance: MeshInstance3D = MeshInstance3D.new()

# Các hướng kiểm tra mặt lân cận tương ứng với Vector3i
var _directions: Array = [
	{"vector": Vector3i.UP, "vertices": [Vector3(0,1,0), Vector3(1,1,0), Vector3(1,1,1), Vector3(0,1,1)], "normal": Vector3.UP},
	{"vector": Vector3i.DOWN, "vertices": [Vector3(0,0,1), Vector3(1,0,1), Vector3(1,0,0), Vector3(0,0,0)], "normal": Vector3.DOWN},
	{"vector": Vector3i.LEFT, "vertices": [Vector3(0,0,0), Vector3(0,0,1), Vector3(0,1,1), Vector3(0,1,0)], "normal": Vector3.LEFT},
	{"vector": Vector3i.RIGHT, "vertices": [Vector3(1,0,1), Vector3(1,0,0), Vector3(1,1,0), Vector3(1,1,1)], "normal": Vector3.RIGHT},
	{"vector": Vector3i.FORWARD, "vertices": [Vector3(1,0,0), Vector3(0,0,0), Vector3(0,1,0), Vector3(1,1,0)], "normal": Vector3.FORWARD},
	{"vector": Vector3i.BACK, "vertices": [Vector3(0,0,1), Vector3(1,0,1), Vector3(1,1,1), Vector3(0,1,1)], "normal": Vector3.BACK}
]

func _ready() -> void:
	add_child(mesh_instance)
	_initialize_empty_chunk()

func _initialize_empty_chunk() -> void:
	_blocks.clear()
	_blocks.resize(CHUNK_WIDTH)
	for x in range(CHUNK_WIDTH):
		_blocks[x] = []
		_blocks[x].resize(CHUNK_HEIGHT)
		for y in range(CHUNK_HEIGHT):
			_blocks[x][y] = []
			_blocks[x][y].resize(CHUNK_WIDTH)
			_blocks[x][y].fill(BlockRegistry.BlockType.AIR)

# Thiết lập mảng dữ liệu thô cho Chunk (Được gọi từ World Generator)
func set_blocks_data(data: Array) -> void:
	if data.size() == CHUNK_WIDTH and data[0].size() == CHUNK_HEIGHT:
		_blocks = data

# Kiểm tra tọa độ cục bộ có nằm trong giới hạn mảng dữ liệu của Chunk không
func is_inside_chunk(x: int, y: int, z: int) -> bool:
	return x >= 0 and x < CHUNK_WIDTH and y >= 0 and y < CHUNK_HEIGHT and z >= 0 and z < CHUNK_WIDTH

# Lấy ID Block tại tọa độ cụ thể
func get_block(x: int, y: int, z: int) -> int:
	if not is_inside_chunk(x, y, z):
		return BlockRegistry.BlockType.AIR
	return _blocks[x][y][z]

# Thuật toán tối ưu hóa lưới đa giác (Face Culling / Hidden Face Removal)
func update_mesh(material: Material) -> void:
	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Định kích thước ô trên Texture Atlas (Ví dụ Atlas kích thước 4x4 block)
	var atlas_size: float = 4.0
	var uv_step: float = 1.0 / atlas_size

	for x in range(CHUNK_WIDTH):
		for y in range(CHUNK_HEIGHT):
			for z in range(CHUNK_WIDTH):
				var block_id: int = _blocks[x][y][z]
				if block_id == BlockRegistry.BlockType.AIR:
					continue
				
				var current_pos: Vector3 = Vector3(x, y, z)
				
				# Quét 6 hướng xung quanh khối Block hiện tại
				for dir in _directions:
					var target_dir: Vector3i = dir["vector"]
					var nx: int = x + target_dir.x
					var ny: int = y + target_dir.y
					var nz: int = z + target_dir.z
					
					# Nếu block lân cận rỗng hoặc nằm ngoài rìa Chunk hiện tại -> Vẽ mặt đó
					var should_render_face: bool = false
					if not is_inside_chunk(nx, ny, nz):
						should_render_face = true
					else:
						var neighbor_id: int = _blocks[nx][ny][nz]
						should_render_face = not BlockRegistry.is_block_solid(neighbor_id)
						
					if should_render_face:
						var face_uv_offset: Vector2i = BlockRegistry.get_block_texture_uv(block_id, target_dir)
						var u_start: float = float(face_uv_offset.x) * uv_step
						var v_start: float = float(face_uv_offset.y) * uv_step
						
						# Thứ tự UV chuẩn cho một đa giác phẳng hình vuông
						var uvs: Array = [
							Vector2(u_start, v_start),
							Vector2(u_start + uv_step, v_start),
							Vector2(u_start + uv_step, v_start + uv_step),
							Vector2(u_start, v_start + uv_step)
						]
						
						var face_vertices: Array = dir["vertices"]
						var normal: Vector3 = dir["normal"]
						
						# Thiết lập chỉ mục đỉnh để vẽ hai hình tam giác tạo nên một mặt phẳng vuông
						var indices: Array = [0, 1, 2, 0, 2, 3]
						
						for index in indices:
							surface_tool.set_normal(normal)
							surface_tool.set_uv(uvs[index])
							surface_tool.add_vertex(current_pos + face_vertices[index])
							
	surface_tool.index()
	var array_mesh: ArrayMesh = surface_tool.commit()
	mesh_instance.mesh = array_mesh
	
	if material != null:
		mesh_instance.material_override = material
		
	_update_collision_shape(array_mesh)

# Khởi tạo dữ liệu va chạm (Physics Collision) động dựa trên cấu trúc Mesh đã tối ưu
func _update_collision_shape(mesh: ArrayMesh) -> void:
	# Giải phóng CollisionShape cũ nếu có để tránh tràn bộ nhớ
	for child in get_children():
		if child is CollisionShape3D:
			child.queue_free()
			
	if mesh.get_surface_count() == 0:
		return
		
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.shape = mesh.create_trimesh_shape()
	add_child(collision_shape)
 
