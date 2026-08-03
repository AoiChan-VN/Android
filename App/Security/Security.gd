class_name Security
extends Node

signal security_started
signal security_ready
signal security_paused
signal security_resumed
signal security_stopping
signal security_stopped
signal security_failed(reason: String)

signal key_registered(key_id: StringName)
signal key_removed(key_id: StringName)
signal keys_cleared

signal key_generated(
	key_id: StringName,
	size: int
)

enum State {
	IDLE,
	STARTING,
	READY,
	PAUSED,
	STOPPING,
	STOPPED,
	FAILED
}

const EXPECTED_NODE_NAME: StringName = &"Security"
const DEFAULT_RSA_SIZE: int = 4096
const DEFAULT_HASH_TYPE: HashingContext.HashType = HashingContext.HASH_SHA256
const HASH_CHUNK_SIZE: int = 1024 * 1024

@export_group("Security")
@export var auto_start: bool = true
@export var clear_keys_on_stop: bool = false
@export var console_output: bool = true

@export_group("Cryptography")
@export var default_hash: HashingContext.HashType = HashingContext.HASH_SHA256
@export_range(2048, 16384, 1024) var default_rsa_size: int = DEFAULT_RSA_SIZE

@export_group("Validation")
@export var validate_root: bool = true

var state: State = State.IDLE
var security_error: String = ""

var _crypto: Crypto = Crypto.new()
var _keys: Dictionary = {}


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

	if state == State.PAUSED:
		return resume()

	if state == State.STOPPING:
		return false

	if state == State.FAILED or state == State.STOPPED:
		state = State.IDLE
		security_error = ""

	if validate_root and not _validate_root():
		return _fail(security_error)

	state = State.STARTING

	security_started.emit()

	if _crypto == null:
		_crypto = Crypto.new()

	state = State.READY

	security_ready.emit()

	_log("Security Ready")

	return true


func pause() -> bool:
	if state != State.READY:
		return false

	state = State.PAUSED

	security_paused.emit()

	_log("Security Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	state = State.READY

	security_resumed.emit()

	_log("Security Resumed")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func hash_bytes(
	data: PackedByteArray,
	hash_type: HashingContext.HashType = DEFAULT_HASH_TYPE
) -> PackedByteArray:
	if not _is_operational():
		return PackedByteArray()

	var context := HashingContext.new()

	var error: Error = context.start(hash_type)

	if error != OK:
		_set_error(
			"Không thể khởi tạo HashingContext: "
			+ error_string(error)
		)
		return PackedByteArray()

	error = context.update(data)

	if error != OK:
		_set_error(
			"Không thể cập nhật HashingContext: "
			+ error_string(error)
		)
		return PackedByteArray()

	return context.finish()


func hash_text(
	text: String,
	hash_type: HashingContext.HashType = DEFAULT_HASH_TYPE
) -> PackedByteArray:
	return hash_bytes(
		text.to_utf8_buffer(),
		hash_type
	)


func hash_file(
	path: String,
	hash_type: HashingContext.HashType = DEFAULT_HASH_TYPE
) -> PackedByteArray:
	if not _is_operational():
		return PackedByteArray()

	if path.is_empty():
		_set_error("Hash File Path không được để trống")
		return PackedByteArray()

	if not FileAccess.file_exists(path):
		_set_error(
			"File không tồn tại: "
			+ path
		)
		return PackedByteArray()

	var file := FileAccess.open(
		path,
		FileAccess.READ
	)

	if file == null:
		_set_error(
			"Không thể mở File để Hash: "
			+ path
		)
		return PackedByteArray()

	var context := HashingContext.new()

	var error: Error = context.start(hash_type)

	if error != OK:
		file.close()

		_set_error(
			"Không thể khởi tạo HashingContext: "
			+ error_string(error)
		)

		return PackedByteArray()

	while file.get_position() < file.get_length():
		var remaining: int = (
			file.get_length()
			- file.get_position()
		)

		var chunk_size: int = min(
			remaining,
			HASH_CHUNK_SIZE
		)

		error = context.update(
			file.get_buffer(chunk_size)
		)

		if error != OK:
			file.close()

			_set_error(
				"Không thể cập nhật HashingContext: "
				+ error_string(error)
			)

			return PackedByteArray()

	file.close()

	return context.finish()


func hmac_bytes(
	key: PackedByteArray,
	data: PackedByteArray,
	hash_type: HashingContext.HashType = DEFAULT_HASH_TYPE
) -> PackedByteArray:
	if not _is_operational():
		return PackedByteArray()

	return _crypto.hmac_digest(
		hash_type,
		key,
		data
	)


func hmac_text(
	key: PackedByteArray,
	text: String,
	hash_type: HashingContext.HashType = DEFAULT_HASH_TYPE
) -> PackedByteArray:
	return hmac_bytes(
		key,
		text.to_utf8_buffer(),
		hash_type
	)


func generate_random_bytes(
	size: int
) -> PackedByteArray:
	if not _is_operational():
		return PackedByteArray()

	if size <= 0:
		_set_error(
			"Random Byte Size phải lớn hơn 0"
		)
		return PackedByteArray()

	return _crypto.generate_random_bytes(
		size
	)


func generate_random_hex(
	size: int
) -> String:
	var data: PackedByteArray = generate_random_bytes(
		size
	)

	if data.is_empty():
		return ""

	return data.hex_encode()


func constant_time_compare(
	trusted: PackedByteArray,
	received: PackedByteArray
) -> bool:
	if not _is_operational():
		return false

	return _crypto.constant_time_compare(
		trusted,
		received
	)


func generate_rsa_key(
	key_id: StringName,
	size: int = DEFAULT_RSA_SIZE,
	replace_existing: bool = false
) -> CryptoKey:
	if not _is_operational():
		return null

	if key_id.is_empty():
		_set_error(
			"Key ID không được để trống"
		)
		return null

	if size < 2048:
		_set_error(
			"RSA Key Size phải từ 2048 bit trở lên"
		)
		return null

	if _keys.has(key_id) and not replace_existing:
		_set_error(
			"Key ID đã tồn tại: "
			+ String(key_id)
		)
		return null

	var key: CryptoKey = _crypto.generate_rsa(
		size
	)

	if key == null:
		_set_error(
			"Không thể tạo RSA Key: "
			+ String(key_id)
		)
		return null

	_keys[key_id] = key

	key_generated.emit(
		key_id,
		size
	)

	key_registered.emit(
		key_id
	)

	_log(
		"RSA Key Generated: "
		+ String(key_id)
	)

	return key


func register_key(
	key_id: StringName,
	key: CryptoKey,
	replace_existing: bool = false
) -> bool:
	if not _is_operational():
		return false

	if key_id.is_empty():
		_set_error(
			"Key ID không được để trống"
		)
		return false

	if key == null:
		_set_error(
			"CryptoKey không hợp lệ"
		)
		return false

	if _keys.has(key_id) and not replace_existing:
		_set_error(
			"Key ID đã tồn tại: "
			+ String(key_id)
		)
		return false

	_keys[key_id] = key

	key_registered.emit(
		key_id
	)

	_log(
		"Key Registered: "
		+ String(key_id)
	)

	return true


func get_key(
	key_id: StringName
) -> CryptoKey:
	if not _keys.has(key_id):
		return null

	var key: CryptoKey = _keys[key_id]

	if key == null:
		_keys.erase(key_id)
		return null

	return key


func has_key(
	key_id: StringName
) -> bool:
	return get_key(key_id) != null


func remove_key(
	key_id: StringName
) -> bool:
	if not _keys.has(key_id):
		return false

	_keys.erase(key_id)

	key_removed.emit(
		key_id
	)

	_log(
		"Key Removed: "
		+ String(key_id)
	)

	return true


func get_key_count() -> int:
	return _keys.size()


func get_key_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for key_id in _keys.keys():
		result.append(
			StringName(
				str(key_id)
			)
		)

	return result


func sign_bytes(
	key_id: StringName,
	data: PackedByteArray,
	hash_type: HashingContext.HashType = DEFAULT_HASH_TYPE
) -> PackedByteArray:
	var key: CryptoKey = get_key(
		key_id
	)

	if key == null:
		_set_error(
			"Không tìm thấy CryptoKey: "
			+ String(key_id)
		)
		return PackedByteArray()

	var digest: PackedByteArray = hash_bytes(
		data,
		hash_type
	)

	if digest.is_empty():
		return PackedByteArray()

	return _crypto.sign(
		hash_type,
		digest,
		key
	)


func verify_bytes(
	key_id: StringName,
	data: PackedByteArray,
	signature: PackedByteArray,
	hash_type: HashingContext.HashType = DEFAULT_HASH_TYPE
) -> bool:
	var key: CryptoKey = get_key(
		key_id
	)

	if key == null:
		_set_error(
			"Không tìm thấy CryptoKey: "
			+ String(key_id)
		)
		return false

	if signature.is_empty():
		return false

	var digest: PackedByteArray = hash_bytes(
		data,
		hash_type
	)

	if digest.is_empty():
		return false

	return _crypto.verify(
		hash_type,
		digest,
		signature,
		key
	)


func encrypt_bytes(
	key_id: StringName,
	data: PackedByteArray
) -> PackedByteArray:
	var key: CryptoKey = get_key(
		key_id
	)

	if key == null:
		_set_error(
			"Không tìm thấy CryptoKey: "
			+ String(key_id)
		)
		return PackedByteArray()

	if data.is_empty():
		return PackedByteArray()

	return _crypto.encrypt(
		key,
		data
	)


func decrypt_bytes(
	key_id: StringName,
	data: PackedByteArray
) -> PackedByteArray:
	var key: CryptoKey = get_key(
		key_id
	)

	if key == null:
		_set_error(
			"Không tìm thấy CryptoKey: "
			+ String(key_id)
		)
		return PackedByteArray()

	if data.is_empty():
		return PackedByteArray()

	return _crypto.decrypt(
		key,
		data
	)


func generate_certificate(
	key_id: StringName,
	issuer_name: String,
	not_before: String = "20140101000000",
	not_after: String = "20340101000000"
) -> X509Certificate:
	var key: CryptoKey = get_key(
		key_id
	)

	if key == null:
		_set_error(
			"Không tìm thấy CryptoKey: "
			+ String(key_id)
		)
		return null

	if issuer_name.is_empty():
		_set_error(
			"Certificate Issuer Name không được để trống"
		)
		return null

	return _crypto.generate_self_signed_certificate(
		key,
		issuer_name,
		not_before,
		not_after
	)


func clear_keys() -> void:
	_keys.clear()

	keys_cleared.emit()

	_log("Security Keys Cleared")


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
	return security_error


func get_default_hash() -> HashingContext.HashType:
	return default_hash


func get_default_rsa_size() -> int:
	return default_rsa_size


func _is_operational() -> bool:
	return (
		state == State.READY
		or state == State.PAUSED
	)


func _validate_root() -> bool:
	security_error = ""

	if not is_inside_tree():
		security_error = (
			"Security không nằm trong SceneTree"
		)
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Security: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
			% [
				EXPECTED_NODE_NAME,
				name
			]
		)

	return true


func _set_error(
	message: String
) -> void:
	security_error = message
	_log_error(message)


func _fail(
	reason: String
) -> bool:
	state = State.FAILED
	security_error = reason

	security_failed.emit(
		reason
	)

	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING

	security_stopping.emit()

	if clear_keys_on_stop:
		clear_keys()

	state = State.STOPPED

	security_stopped.emit()

	_log("Security Stopped")


func _log(
	message: String
) -> void:
	if console_output:
		print(
			"[Security] ",
			message
		)


func _log_error(
	message: String
) -> void:
	push_error(
		"[Security] "
		+ message
) 
