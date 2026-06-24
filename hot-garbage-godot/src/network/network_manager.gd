extends Node

signal player_registered(peer_id: int, player_name: String)
signal player_disconnected(peer_id: int)
signal connection_failed()
signal server_disconnected()
signal bid_received(peer_id: int, amount: int)

const PORT := 7777
const MAX_PEERS := 8

var player_names: Dictionary = {}
var _local_name: String = ""

# --- Transport ---

func host(player_name: String) -> void:
	_local_name = player_name
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PEERS)
	assert(err == OK, "Failed to create server: %d" % err)
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	player_names[1] = player_name

func join(ip: String, player_name: String) -> void:
	_local_name = player_name
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	assert(err == OK, "Failed to connect: %d" % err)
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func disconnect_from_game() -> void:
	multiplayer.multiplayer_peer = null
	player_names.clear()

func is_host() -> bool:
	return multiplayer.is_server()

func get_peer_ids() -> Array:
	return multiplayer.get_peers()

# --- Peer lifecycle ---

func _on_peer_connected(_peer_id: int) -> void:
	pass

func _on_peer_disconnected(peer_id: int) -> void:
	player_names.erase(peer_id)
	player_disconnected.emit(peer_id)

func _on_connected_to_server() -> void:
	_register_self.rpc_id(1, _local_name)

func _on_connection_failed() -> void:
	connection_failed.emit()

func _on_server_disconnected() -> void:
	server_disconnected.emit()

# --- Registration ---

@rpc("any_peer", "reliable")
func _register_self(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	player_names[sender_id] = player_name
	_sync_player_joined.rpc(sender_id, player_name)
	for id in player_names:
		if id != sender_id:
			_sync_player_joined.rpc_id(sender_id, id, player_names[id])

@rpc("authority", "reliable", "call_local")
func _sync_player_joined(peer_id: int, player_name: String) -> void:
	player_names[peer_id] = player_name
	player_registered.emit(peer_id, player_name)

# --- Auction RPCs ---

# Send full artifact (with value) + pitch duration to auctioneer only
func rpc_reveal_to_auctioneer(auctioneer_peer_id: int, artifact: Dictionary, pitch_duration: int) -> void:
	_recv_reveal_to_auctioneer.rpc_id(auctioneer_peer_id, artifact, pitch_duration)

@rpc("authority", "reliable")
func _recv_reveal_to_auctioneer(artifact: Dictionary, pitch_duration: int) -> void:
	get_tree().get_root().propagate_call("on_auctioneer_reveal", [artifact, pitch_duration], true)

# Broadcast public artifact (no value) + pitch duration to all peers (bidders)
func rpc_start_pitch(artifact: Dictionary, pitch_duration: int) -> void:
	_recv_start_pitch.rpc(artifact, pitch_duration)

@rpc("authority", "reliable", "call_local")
func _recv_start_pitch(artifact: Dictionary, pitch_duration: int) -> void:
	get_tree().get_root().propagate_call("on_start_pitch", [artifact, pitch_duration], true)

# Open bidding — broadcast to all peers
func rpc_open_bidding() -> void:
	_recv_open_bidding.rpc()

@rpc("authority", "reliable", "call_local")
func _recv_open_bidding() -> void:
	get_tree().get_root().propagate_call("on_open_bidding", [], true)

# Auctioneer requests early open — sent from client to host
func send_open_early() -> void:
	if is_host():
		GameServer.open_bidding_from_peer(1)
	else:
		_recv_open_early.rpc_id(1)

@rpc("any_peer", "reliable")
func _recv_open_early() -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	GameServer.open_bidding_from_peer(sender_id)

# Broadcast auction result
func rpc_show_bid_result(result: Dictionary) -> void:
	_recv_show_bid_result.rpc(result)

@rpc("authority", "reliable", "call_local")
func _recv_show_bid_result(result: Dictionary) -> void:
	get_tree().get_root().propagate_call("on_show_bid_result", [result], true)

# Broadcast chaos event
func rpc_show_chaos(chaos: Dictionary) -> void:
	_recv_show_chaos.rpc(chaos)

@rpc("authority", "reliable", "call_local")
func _recv_show_chaos(chaos: Dictionary) -> void:
	get_tree().get_root().propagate_call("on_show_chaos", [chaos], true)

# Broadcast final scores
func rpc_show_final_scores(ranking: Array) -> void:
	_recv_show_final_scores.rpc(ranking)

@rpc("authority", "reliable", "call_local")
func _recv_show_final_scores(ranking: Array) -> void:
	get_tree().get_root().propagate_call("on_show_final_scores", [ranking], true)

# Host drives all scene transitions
func rpc_advance_scene(scene_path: String) -> void:
	_recv_advance_scene.rpc(scene_path)

@rpc("authority", "reliable", "call_local")
func _recv_advance_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

func rpc_advance_scene_to_peer(peer_id: int, scene_path: String) -> void:
	_recv_advance_scene.rpc_id(peer_id, scene_path)

# Sync authoritative player state to a specific client
func rpc_sync_player_state(target_peer: int, cash: int, artifacts: Array) -> void:
	_recv_sync_player_state.rpc_id(target_peer, cash, artifacts)

@rpc("authority", "reliable")
func _recv_sync_player_state(cash: int, artifacts: Array) -> void:
	GameServer.receive_player_state(cash, artifacts)

# --- Bid submission (client -> host) ---

func submit_bid(amount: int) -> void:
	if is_host():
		bid_received.emit(multiplayer.get_unique_id(), amount)
	else:
		_recv_bid.rpc_id(1, amount)

@rpc("any_peer", "reliable")
func _recv_bid(amount: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	bid_received.emit(sender_id, amount)
