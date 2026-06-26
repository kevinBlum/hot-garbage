extends Node

signal room_joined(room_name: String, is_host: bool)
signal player_registered(player_name: String)
signal player_disconnected(player_name: String)
signal connection_failed()
signal server_disconnected()
signal error_received(code: String, message: String)
signal bid_count_updated(received: int, total: int)
signal player_moved(player_name: String, x: float, y: float, z: float, ry: float, anim: String)

const SERVER_URL := "ws://hot-garbage-prod-alb-1121244951.us-east-1.elb.amazonaws.com"
# const SERVER_URL := "ws://localhost:3000"

const SCENE_PATHS := {
	"lobby":         "res://src/scenes/lobby.tscn",
	"auction_house": "res://src/scenes/auction_house.tscn",
}

var player_names: Array[String] = []
var local_name: String = ""
var room_name: String = ""
var server_restarted: bool = false
var _is_host: bool = false
var _ws: WebSocketPeer = null
var _pending_send: Dictionary = {}

func _process(_delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		_process_pending()
		# One packet per frame so deferred scene changes (advance_scene) complete
		# before subsequent messages (auctioneer_reveal, start_pitch) are dispatched.
		if _ws.get_available_packet_count() > 0:
			var raw := _ws.get_packet().get_string_from_utf8()
			var msg = JSON.parse_string(raw)
			if msg is Dictionary:
				_dispatch(msg)
	elif state == WebSocketPeer.STATE_CLOSED:
		var code := _ws.get_close_code()
		_ws = null
		if code == -1:
			connection_failed.emit()
		else:
			server_disconnected.emit()

func create_room(p_room_name: String, password: String, player_name: String) -> void:
	local_name = player_name
	_connect_and_send({
		"type": "create_room",
		"roomName": p_room_name.to_lower(),
		"password": password,
		"playerName": player_name,
	})

func join_room(p_room_name: String, password: String, player_name: String) -> void:
	local_name = player_name
	_connect_and_send({
		"type": "join_room",
		"roomName": p_room_name.to_lower(),
		"password": password,
		"playerName": player_name,
	})

func start_game(pitch_duration: int) -> void:
	_send({ "type": "start_game", "pitchDuration": pitch_duration })

func send_open_early() -> void:
	_send({ "type": "open_early" })

func submit_bid(amount: int) -> void:
	_send({ "type": "submit_bid", "amount": amount })

func send_force_resolve() -> void:
	_send({ "type": "force_resolve" })

func disconnect_from_game() -> void:
	if _ws != null:
		_ws.close()
		_ws = null
	_pending_send = {}
	player_names.clear()
	local_name = ""
	room_name = ""
	_is_host = false

func is_host() -> bool:
	return _is_host

func _connect_and_send(msg: Dictionary) -> void:
	_ws = WebSocketPeer.new()
	var err := _ws.connect_to_url(SERVER_URL)
	if err != OK:
		_ws = null
		connection_failed.emit()
		return
	_pending_send = msg

func _process_pending() -> void:
	if _pending_send.is_empty():
		return
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(_pending_send))
		_pending_send = {}

func _send(msg: Dictionary) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_ws.send_text(JSON.stringify(msg))

func _dispatch(msg: Dictionary) -> void:
	match msg.get("type", ""):
		"room_joined":
			room_name = msg.get("roomName", "")
			_is_host = msg.get("isHost", false)
			server_restarted = msg.get("serverRestarted", false)
			player_names = Array(msg.get("players", []), TYPE_STRING, "", null)
			room_joined.emit(room_name, _is_host)
		"player_joined":
			player_names = Array(msg.get("players", []), TYPE_STRING, "", null)
			var pname: String = msg.get("playerName", "")
			player_registered.emit(pname)
		"player_left":
			player_names = Array(msg.get("players", []), TYPE_STRING, "", null)
			var pname: String = msg.get("playerName", "")
			player_disconnected.emit(pname)
		"error":
			error_received.emit(msg.get("code", ""), msg.get("message", ""))
		"server_disconnected":
			server_disconnected.emit()
		"advance_scene":
			var scene_key: String = msg.get("scene", "")
			if SCENE_PATHS.has(scene_key):
				get_tree().change_scene_to_file(SCENE_PATHS[scene_key])
		"auctioneer_reveal":
			get_tree().get_root().propagate_call("on_auctioneer_reveal",
				[msg.get("artifact", {}), msg.get("pitchDuration", 45)], true)
		"start_pitch":
			get_tree().get_root().propagate_call("on_start_pitch",
				[msg.get("artifact", {}), msg.get("pitchDuration", 45),
				 msg.get("round", 1), msg.get("totalRounds", 5)], true)
			if msg.has("auctioneerName"):
				get_tree().get_root().propagate_call("on_auctioneer_name",
					[msg.get("auctioneerName", "")], true)
		"player_move":
			player_moved.emit(
				msg.get("playerName", ""),
				float(msg.get("x", 0.0)), float(msg.get("y", 0.0)), float(msg.get("z", 0.0)),
				float(msg.get("ry", 0.0)),
				msg.get("anim", "idle"))
		"open_bidding":
			get_tree().get_root().propagate_call("on_open_bidding",
				[msg.get("bidTimeout", 30.0)], true)
		"bid_result":
			get_tree().get_root().propagate_call("on_show_bid_result", [msg], true)
		"chaos":
			get_tree().get_root().propagate_call("on_show_chaos", [msg], true)
		"sync_player_state":
			GameServer.receive_player_state(msg.get("cash", 0), msg.get("artifacts", []))
		"final_scores":
			get_tree().get_root().propagate_call("on_show_final_scores",
				[msg.get("ranking", [])], true)
		"bid_count":
			bid_count_updated.emit(msg.get("received", 0), msg.get("total", 0))
