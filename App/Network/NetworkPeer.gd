class_name NetworkPeer
extends RefCounted

enum Transport {
	ENET,
	WEBSOCKET
}

var transport: Transport = Transport.ENET
var peer: MultiplayerPeer = null
var last_error: int = OK


func create_server(
	selected_transport: Transport,
	port: int,
	bind_address: String,
	max_clients: int
) -> int:
	close()

	transport = selected_transport

	match transport:
		Transport.ENET:
			var enet_peer := ENetMultiplayerPeer.new()

			enet_peer.set_bind_ip(bind_address)

			last_error = enet_peer.create_server(
				port,
				max_clients
			)

			if last_error == OK:
				peer = enet_peer

		Transport.WEBSOCKET:
			var websocket_peer := WebSocketMultiplayerPeer.new()

			last_error = websocket_peer.create_server(
				port,
				bind_address
			)

			if last_error == OK:
				peer = websocket_peer

		_:
			last_error = ERR_UNAVAILABLE

	return last_error


func create_client(
	selected_transport: Transport,
	address: String,
	port: int
) -> int:
	close()

	transport = selected_transport

	match transport:
		Transport.ENET:
			var enet_peer := ENetMultiplayerPeer.new()

			last_error = enet_peer.create_client(
				address,
				port
			)

			if last_error == OK:
				peer = enet_peer

		Transport.WEBSOCKET:
			var websocket_peer := WebSocketMultiplayerPeer.new()

			last_error = websocket_peer.create_client(
				address
			)

			if last_error == OK:
				peer = websocket_peer

		_:
			last_error = ERR_UNAVAILABLE

	return last_error


func get_peer() -> MultiplayerPeer:
	return peer


func get_error() -> int:
	return last_error


func is_valid() -> bool:
	return is_instance_valid(peer)


func close() -> void:
	if is_instance_valid(peer):
		peer.close()

	peer = null
	last_error = OK 
