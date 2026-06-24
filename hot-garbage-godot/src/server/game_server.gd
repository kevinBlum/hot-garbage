extends Node

const _GameEngineClass = preload("res://src/logic/game_engine.gd")

var _engine = null
var _artifact_data: Dictionary = {}
var _current_round: int = 0
var _current_turn_idx: int = 0
var _order: Array = []
var _pending_force_resolve: bool = false
var _pitch_duration: int = 45
var _bidding_open: bool = false
var _current_auctioneer_id: String = ""
var _current_auctioneer_peer_id: int = 0

# Exposed for HUD — player_id (String name) -> value
var player_cash: Dictionary = {}
var player_artifacts: Dictionary = {}

func _ready() -> void:
	if not NetworkManager.is_host():
		return
	NetworkManager.bid_received.connect(_on_bid_received)
	var file := FileAccess.open("res://data/artifacts.json", FileAccess.READ)
	_artifact_data = JSON.parse_string(file.get_as_text())

func start_game(player_ids: Array, pitch_duration: int = 45) -> void:
	if not NetworkManager.is_host():
		return
	_pitch_duration = pitch_duration
	_engine = _GameEngineClass.new(
		{"seed": randi(), "player_ids": player_ids},
		_artifact_data
	)
	_order = _engine.get_order()
	_current_round = 1
	_current_turn_idx = 0
	player_cash = {}
	player_artifacts = {}
	for id in player_ids:
		player_cash[id] = 1000
		player_artifacts[id] = []
	_begin_turn()

func _begin_turn() -> void:
	if _current_round > _engine.get_rounds():
		_end_game()
		return

	_current_auctioneer_id = _order[_current_turn_idx]
	_current_auctioneer_peer_id = _peer_id_for_player(_current_auctioneer_id)
	_bidding_open = false

	# Route each remote peer to the correct scene
	for peer_id in NetworkManager.get_peer_ids():
		var scene: String = "res://src/scenes/auctioneer_view.tscn" \
			if peer_id == _current_auctioneer_peer_id \
			else "res://src/scenes/bidder_view.tscn"
		NetworkManager.rpc_advance_scene_to_peer(peer_id, scene)

	# Route host's own display
	var host_scene: String = "res://src/scenes/auctioneer_view.tscn" \
		if _current_auctioneer_peer_id == 1 \
		else "res://src/scenes/bidder_view.tscn"
	get_tree().change_scene_to_file(host_scene)

	await get_tree().create_timer(0.5).timeout

	var public_artifact: Dictionary = _engine.start_auction(_current_auctioneer_id)
	var full_artifact: Dictionary = _engine.get_auctioneer_artifact()

	# Send full artifact (with value + pitch duration) only to the auctioneer
	if _current_auctioneer_peer_id == 1:
		get_tree().get_root().propagate_call("on_auctioneer_reveal", [full_artifact, _pitch_duration], true)
	else:
		NetworkManager.rpc_reveal_to_auctioneer(_current_auctioneer_peer_id, full_artifact, _pitch_duration)

	# Broadcast public artifact (no value) + pitch duration to all peers
	NetworkManager.rpc_start_pitch(public_artifact, _pitch_duration)

	# Authoritative pitch timer — opens bidding when it expires
	await get_tree().create_timer(float(_pitch_duration)).timeout
	if not _bidding_open:
		_open_bidding()

func _open_bidding() -> void:
	if _bidding_open:
		return
	_bidding_open = true
	NetworkManager.rpc_open_bidding()

# Called by NetworkManager when it receives an open_early RPC from a peer
func open_bidding_from_peer(peer_id: int) -> void:
	if not NetworkManager.is_host():
		return
	if peer_id != _current_auctioneer_peer_id:
		return
	_open_bidding()

func _on_bid_received(peer_id: int, amount: int) -> void:
	if _engine == null or not _bidding_open:
		return
	var player_id: String = _player_id_for_peer(peer_id)
	_engine.submit_bid(player_id, amount)
	if _engine.all_bids_received():
		_resolve_current_auction()

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

	# Update tracked player state
	var winner: String = result.winner
	var price: int = result.price
	if winner != "BANK":
		var owned: Dictionary = result.artifact.duplicate()
		owned.erase("value")
		player_artifacts[winner].append(owned)
		player_cash[winner] = player_cash.get(winner, 0) - price
	player_cash[_current_auctioneer_id] = player_cash.get(_current_auctioneer_id, 0) + price

	# Strip value from broadcast result
	var public_result := result.duplicate()
	if public_result.has("artifact"):
		var pub_artifact: Dictionary = (public_result["artifact"] as Dictionary).duplicate()
		pub_artifact.erase("value")
		public_result["artifact"] = pub_artifact

	var chaos: Dictionary = _engine.maybe_chaos(result)
	NetworkManager.rpc_show_bid_result(public_result)
	NetworkManager.rpc_show_chaos(chaos)

	_current_turn_idx += 1
	if _current_turn_idx >= _order.size():
		_current_turn_idx = 0
		_current_round += 1

	await get_tree().create_timer(3.0).timeout
	_pending_force_resolve = false
	_begin_turn()

func _end_game() -> void:
	var ranking: Array = _engine.get_final_scores()
	NetworkManager.rpc_advance_scene("res://src/scenes/final_scores.tscn")
	await get_tree().create_timer(0.5).timeout
	NetworkManager.rpc_show_final_scores(ranking)

func _peer_id_for_player(player_id: String) -> int:
	for peer_id in NetworkManager.player_names:
		if NetworkManager.player_names[peer_id] == player_id:
			return peer_id
	return 1

func _player_id_for_peer(peer_id: int) -> String:
	return NetworkManager.player_names.get(peer_id, "unknown")
