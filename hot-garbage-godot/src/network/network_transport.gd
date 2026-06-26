extends Node

func send_bid(amount: int) -> void:
	NetworkManager._send({ "type": "submit_bid", "amount": amount })

func send_position(pos: Vector3, ry: float, anim: String) -> void:
	NetworkManager._send({
		"type": "player_move",
		"x": pos.x, "y": pos.y, "z": pos.z,
		"ry": ry, "anim": anim,
	})

func send_open_early() -> void:
	NetworkManager._send({ "type": "open_early" })

func send_force_resolve() -> void:
	NetworkManager._send({ "type": "force_resolve" })

func send_start_game(pitch_duration: int) -> void:
	NetworkManager._send({ "type": "start_game", "pitchDuration": pitch_duration })

func send_delete_room() -> void:
	NetworkManager._send({ "type": "delete_room" })

func send_ability_activate(ability_type: String, target_name: String = "") -> void:
	NetworkManager._send({ "type": "ability_activate", "abilityType": ability_type, "targetName": target_name })
