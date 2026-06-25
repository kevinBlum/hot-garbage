extends Node

# Client-side display state only.
# All game logic runs on the Node.js server.
# Populated by NetworkManager when sync_player_state messages arrive.

var player_cash: Dictionary = {}
var player_artifacts: Dictionary = {}

func receive_player_state(cash: int, artifacts: Array) -> void:
	var own_id: String = NetworkManager.local_name
	if own_id.is_empty():
		return
	player_cash[own_id] = cash
	player_artifacts[own_id] = artifacts
	get_tree().call_group("hud_nodes", "refresh")
