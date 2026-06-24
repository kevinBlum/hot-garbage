extends Node

const _GameEngineClass = preload("res://src/logic/game_engine.gd")
var _engine = null
var _artifact_data: Dictionary = {}
var _current_round: int = 0
var _current_turn_idx: int = 0  # index into _order for this round
var _order: Array = []
var _pending_force_resolve: bool = false

func _ready() -> void:
	if not NetworkManager.is_host():
		return
	NetworkManager.bid_received.connect(_on_bid_received)
	var file := FileAccess.open("res://data/artifacts.json", FileAccess.READ)
	_artifact_data = JSON.parse_string(file.get_as_text())

func start_game(player_ids: Array) -> void:
	if not NetworkManager.is_host():
		return
	_engine = _GameEngineClass.new(
		{"seed": randi(), "player_ids": player_ids},
		_artifact_data
	)
	_order = _engine.get_order()
	_current_round = 1
	_current_turn_idx = 0
	_begin_turn()

func _begin_turn() -> void:
	if _current_round > _engine.get_rounds():
		_end_game()
		return

	var auctioneer_id: String = _order[_current_turn_idx]
	var auctioneer_peer_id: int = _peer_id_for_player(auctioneer_id)

	# Route each remote peer to the correct scene
	for peer_id in NetworkManager.get_peer_ids():
		var scene := "res://src/scenes/auctioneer_view.tscn" \
			if peer_id == auctioneer_peer_id \
			else "res://src/scenes/bidder_view.tscn"
		NetworkManager.rpc_advance_scene_to_peer(peer_id, scene)

	# Route host's own display
	var host_scene := "res://src/scenes/auctioneer_view.tscn" \
		if auctioneer_peer_id == 1 \
		else "res://src/scenes/bidder_view.tscn"
	get_tree().change_scene_to_file(host_scene)

	await get_tree().create_timer(0.5).timeout

	var public_artifact: Dictionary = _engine.start_auction(auctioneer_id)
	var full_artifact: Dictionary = _engine.get_auctioneer_artifact()

	# Send full artifact (with value) only to the auctioneer.
	# _recv_reveal_to_auctioneer lacks call_local, so if the host IS the
	# auctioneer (peer_id == 1) the RPC won't fire locally — handle directly.
	if auctioneer_peer_id == 1:
		get_tree().get_root().propagate_call("on_auctioneer_reveal", [full_artifact], true)
	else:
		NetworkManager.rpc_reveal_to_auctioneer(auctioneer_peer_id, full_artifact)

	# Send public artifact (no value) to everyone — call_local means host client also receives
	NetworkManager.rpc_start_bidding(public_artifact)

func _on_bid_received(peer_id: int, amount: int) -> void:
	if _engine == null:
		return
	var player_id: String = _player_id_for_peer(peer_id)
	_engine.submit_bid(player_id, amount)
	if _engine.all_bids_received():
		_resolve_current_auction()

# Host can force-resolve (escape hatch for dropped clients)
func force_resolve() -> void:
	if _engine == null or not NetworkManager.is_host():
		return
	_resolve_current_auction()

func _resolve_current_auction() -> void:
	if _pending_force_resolve:
		return
	_pending_force_resolve = true
	NetworkManager.rpc_advance_scene("res://src/scenes/bid_reveal.tscn")
	await get_tree().create_timer(0.3).timeout
	var result: Dictionary = _engine.resolve_auction()
	# Strip value from broadcast result — it's transmitted to all peers
	var public_result := result.duplicate()
	if public_result.has("artifact"):
		var pub_artifact: Dictionary = (public_result["artifact"] as Dictionary).duplicate()
		pub_artifact.erase("value")
		public_result["artifact"] = pub_artifact
	var chaos: Dictionary = _engine.maybe_chaos(result)
	NetworkManager.rpc_show_bid_result(public_result)
	NetworkManager.rpc_show_chaos(chaos)
	# Advance turn pointer
	_current_turn_idx += 1
	if _current_turn_idx >= _order.size():
		_current_turn_idx = 0
		_current_round += 1
	# Small delay so players can read the result before moving on
	await get_tree().create_timer(3.0).timeout
	_pending_force_resolve = false
	_begin_turn()

func _end_game() -> void:
	var ranking: Array = _engine.get_final_scores()
	NetworkManager.rpc_show_final_scores(ranking)
	await get_tree().create_timer(1.0).timeout
	NetworkManager.rpc_advance_scene("res://src/scenes/final_scores.tscn")

# --- Peer ↔ Player ID mapping ---
# player_ids in the engine are strings matching NetworkManager.player_names values.
# Map by position: _order[i] corresponds to sorted peer_ids[i].

func _peer_id_for_player(player_id: String) -> int:
	for peer_id in NetworkManager.player_names:
		if NetworkManager.player_names[peer_id] == player_id:
			return peer_id
	return 1  # fallback to host

func _player_id_for_peer(peer_id: int) -> String:
	return NetworkManager.player_names.get(peer_id, "unknown")
