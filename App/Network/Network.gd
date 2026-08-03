class_name Network
extends Node

signal network_started
signal network_ready
signal network_paused
signal network_resumed
signal network_stopping
signal network_stopped
signal network_failed(reason: String)

signal server_started
signal server_stopped

signal connection_started
signal connected_to_server
signal connection_failed
signal server_disconnected

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)

enum State {
	IDLE,
	STARTING,
	READY,
	LISTENING,
	CONNECTING,
	CONNECTED,
	PAUSED,
	STOPPING,
	STOPPED,
	FAILED
}

enum AutoMode {
	DISABLED,
	SERVER,
	CLIENT
}

const EXPECTED_NODE_NAME: StringName = &"Network"

@export_group("Network")
@export var auto_start: bool = true
@export var auto_connect: bool = false
@export var auto_mode: AutoMode = AutoMode.DISABLED
@export var transport: NetworkPeer.Transport = NetworkPeer.Transport.ENET
@export var address: String = "127.0.0.1"
@export var bind_address: String = "*"
@export_range(1, 65535, 1) var port: int = 9000
@export_range(1, 4095, 1) var max_clients: int = 32
@export var console_output: bool = true
@export var stop_on_exit: bool = true

@export_group("Validation")
@export var validate_root: bool = true
@export var validate_port: bool = true

var state: State = State.IDLE
var network_error: String = ""

var _multiplayer_api: MultiplayerAPI
var _network_peer: NetworkPeer
var _mode: AutoMode = AutoMode.DISABLED


func _enter_tree() -> void:
	state = State.STARTING

	_multiplayer_api = MultiplayerAPI.create_default_interface()

	get_tree().set_multiplayer(
		_multiplayer_api,
		get_path()
	)

	_connect_multiplayer_signals()


func _ready() -> void:
	if auto_start:
		start()

	if auto_connect:
		_auto_connect()


func _exit_tree() -> void:
	_shutdown()


func start() -> bool:
	if state == State.READY:
		return true

	if state == State.LISTENING:
		return true

	if state == State.CONNECTING:
		return true

	if state == State.CONNECTED:
		return true

	if state == State.PAUSED:
		return resume()

	if state == State.STOPPING:
		return false

	if state == State.FAILED or state == State.STOPPED:
		state = State.IDLE
		network_error = ""

	if validate_root and not _validate_root():
		return _fail(network_error)

	if validate_port and not _validate_port():
		return _fail(network_error)

	state = State.STARTING

	network_started.emit()

	state = State.READY

	network_ready.emit()

	_log("Network Ready")

	return true


func start_server() -> bool:
	if not start():
		return false

	if state == State.LISTENING:
		return true

	if state == State.CONNECTING or state == State.CONNECTED:
		stop_connection()

		if not start():
			return false

	var network_peer := NetworkPeer.new()

	var result: int = network_peer.create_server(
		transport,
		port,
		bind_address,
		max_clients
	)

	if result != OK:
		return _fail(
			"Không thể khởi động Network Server: "
			+ error_string(result)
		)

	_network_peer = network_peer

	_multiplayer_api.multiplayer_peer = (
		_network_peer.get_peer()
	)

	_mode = AutoMode.SERVER
	state = State.LISTENING

	server_started.emit()

	_log(
		"Server Listening: "
		+ bind_address
		+ ":"
		+ str(port)
	)

	return true


func start_client() -> bool:
	if not start():
		return false

	if state == State.CONNECTED:
		return true

	if state == State.LISTENING:
		stop_connection()

		if not start():
			return false

	var network_peer := NetworkPeer.new()

	var result: int

	if transport == NetworkPeer.Transport.WEBSOCKET:
		result = network_peer.create_client(
			transport,
			address,
			port
		)
	else:
		result = network_peer.create_client(
			transport,
			address,
			port
		)

	if result != OK:
		return _fail(
			"Không thể khởi động Network Client: "
			+ error_string(result)
		)

	_network_peer = network_peer

	_multiplayer_api.multiplayer_peer = (
		_network_peer.get_peer()
	)

	_mode = AutoMode.CLIENT
	state = State.CONNECTING

	connection_started.emit()

	_log(
		"Client Connecting: "
		+ address
		+ ":"
		+ str(port)
	)

	return true


func pause() -> bool:
	if state != State.READY \
	and state != State.LISTENING \
	and state != State.CONNECTING \
	and state != State.CONNECTED:
		return false

	state = State.PAUSED

	network_paused.emit()

	_log("Network Paused")

	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false

	match _mode:
		AutoMode.SERVER:
			state = State.LISTENING

		AutoMode.CLIENT:
			if _multiplayer_api.is_server():
				state = State.CONNECTED
			elif _multiplayer_api.multiplayer_peer != null:
				state = State.CONNECTING
			else:
				state = State.READY

		_:
			state = State.READY

	network_resumed.emit()

	_log("Network Resumed")

	return true


func stop_connection() -> bool:
	if _multiplayer_api == null:
		return false

	_multiplayer_api.multiplayer_peer = (
		OfflineMultiplayerPeer.new()
	)

	if _network_peer != null:
		_network_peer.close()

	_network_peer = null
	_mode = AutoMode.DISABLED

	server_stopped.emit()

	state = State.READY

	_log("Network Connection Stopped")

	return true


func stop() -> bool:
	if state == State.STOPPED:
		return true

	if state == State.IDLE:
		return false

	_shutdown()

	return state == State.STOPPED


func get_state() -> State:
	return state


func get_error() -> String:
	return network_error


func get_transport() -> NetworkPeer.Transport:
	return transport


func get_mode() -> AutoMode:
	return _mode


func get_unique_id() -> int:
	if _multiplayer_api == null:
		return 1

	return _multiplayer_api.get_unique_id()


func is_server() -> bool:
	if _multiplayer_api == null:
		return false

	return _multiplayer_api.is_server()


func is_client() -> bool:
	return (
		_mode == AutoMode.CLIENT
		and not is_server()
	)


func is_connected() -> bool:
	return state == State.CONNECTED


func is_connecting() -> bool:
	return state == State.CONNECTING


func is_listening() -> bool:
	return state == State.LISTENING


func is_paused() -> bool:
	return state == State.PAUSED


func get_peer_count() -> int:
	if _multiplayer_api == null:
		return 0

	return _multiplayer_api.get_peers().size()


func get_peer_ids() -> PackedInt32Array:
	if _multiplayer_api == null:
		return PackedInt32Array()

	return _multiplayer_api.get_peers()


func has_peer(peer_id: int) -> bool:
	return get_peer_ids().has(peer_id)


func get_peer_address(peer_id: int) -> String:
	if _network_peer == null:
		return ""

	var peer: MultiplayerPeer = (
		_network_peer.get_peer()
	)

	if peer == null:
		return ""

	if peer is WebSocketMultiplayerPeer:
		return (
			peer as WebSocketMultiplayerPeer
		).get_peer_address(peer_id)

	return ""


func disconnect_peer(peer_id: int) -> bool:
	if _multiplayer_api == null:
		return false

	if not has_peer(peer_id):
		return false

	if _multiplayer_api.is_server():
		_multiplayer_api.disconnect_peer(peer_id)

	return true


func _auto_connect() -> void:
	match auto_mode:
		AutoMode.SERVER:
			start_server()

		AutoMode.CLIENT:
			start_client()

		AutoMode.DISABLED:
			return


func _connect_multiplayer_signals() -> void:
	if _multiplayer_api == null:
		return

	if not _multiplayer_api.peer_connected.is_connected(
		_on_peer_connected
	):
		_multiplayer_api.peer_connected.connect(
			_on_peer_connected
		)

	if not _multiplayer_api.peer_disconnected.is_connected(
		_on_peer_disconnected
	):
		_multiplayer_api.peer_disconnected.connect(
			_on_peer_disconnected
		)

	if not _multiplayer_api.connected_to_server.is_connected(
		_on_connected_to_server
	):
		_multiplayer_api.connected_to_server.connect(
			_on_connected_to_server
		)

	if not _multiplayer_api.connection_failed.is_connected(
		_on_connection_failed
	):
		_multiplayer_api.connection_failed.connect(
			_on_connection_failed
		)

	if not _multiplayer_api.server_disconnected.is_connected(
		_on_server_disconnected
	):
		_multiplayer_api.server_disconnected.connect(
			_on_server_disconnected
		)


func _on_peer_connected(
	peer_id: int
) -> void:
	peer_connected.emit(peer_id)

	if _mode == AutoMode.SERVER:
		_log(
			"Peer Connected: "
			+ str(peer_id)
		)


func _on_peer_disconnected(
	peer_id: int
) -> void:
	peer_disconnected.emit(peer_id)

	_log(
		"Peer Disconnected: "
		+ str(peer_id)
	)


func _on_connected_to_server() -> void:
	state = State.CONNECTED

	connected_to_server.emit()

	_log("Connected To Server")


func _on_connection_failed() -> void:
	state = State.FAILED
	network_error = "Network Client Connection Failed"

	connection_failed.emit()
	network_failed.emit(network_error)

	_log_error(network_error)


func _on_server_disconnected() -> void:
	state = State.READY

	server_disconnected.emit()

	_log("Server Disconnected")


func _validate_root() -> bool:
	network_error = ""

	if not is_inside_tree():
		network_error = (
			"Network không nằm trong SceneTree"
		)
		return false

	if name != EXPECTED_NODE_NAME:
		push_warning(
			"Network: Tên Node gốc đã thay đổi từ '%s' thành '%s'. Hệ thống vẫn hoạt động vì không phụ thuộc vào tên Node."
			% [
				EXPECTED_NODE_NAME,
				name
			]
		)

	return true


func _validate_port() -> bool:
	network_error = ""

	if port < 1 or port > 65535:
		network_error = (
			"Network Port không hợp lệ: "
			+ str(port)
		)
		return false

	if max_clients < 1 or max_clients > 4095:
		network_error = (
			"Max Clients không hợp lệ: "
			+ str(max_clients)
		)
		return false

	return true


func _fail(
	reason: String
) -> bool:
	state = State.FAILED
	network_error = reason

	network_failed.emit(reason)

	_log_error(reason)

	return false


func _shutdown() -> void:
	if state == State.STOPPED:
		return

	if state == State.IDLE:
		return

	state = State.STOPPING

	network_stopping.emit()

	if stop_on_exit:
		stop_connection()

	state = State.STOPPED

	network_stopped.emit()

	_log("Network Stopped")


func _log(
	message: String
) -> void:
	if console_output:
		print(
			"[Network] ",
			message
		)


func _log_error(
	message: String
) -> void:
	push_error(
		"[Network] "
		+ message
) 
