extends Node3D

const _UITheme = preload("res://src/scenes/ui_theme.gd")
const LocalPlayerScene = preload("res://src/characters/local_player.tscn")
const RemotePlayerScene = preload("res://src/characters/remote_player.tscn")
const ThrowablePropScript = preload("res://src/props/throwable_prop.gd")
const HUDOverlayScript = preload("res://src/ui/hud_overlay.gd")
const AuctioneerOverlayScript = preload("res://src/ui/auctioneer_overlay.gd")
const BidPanelScript = preload("res://src/ui/bid_panel.gd")
const BidRevealScript = preload("res://src/ui/bid_reveal_overlay.gd")
const ChaosCardScript = preload("res://src/ui/chaos_card.gd")
const FinalScoresScript = preload("res://src/ui/final_scores_overlay.gd")

# player_name → RemotePlayer node
var _remote_players: Dictionary = {}

# In-world label refs — updated per phase
var _phase_sign_label: Label3D
var _pedestal_label: Label3D
var _timer_label: Label3D
var _scoreboard_label: Label3D

# Phase timer for bid countdown
var _bid_time_left: float = 0.0
var _bid_counting: bool = false

# CanvasLayer populated in later tasks
var _canvas: CanvasLayer
var _hud: Control = null
var _auctioneer_overlay: Control = null
var _bid_panel: Control = null
var _bid_reveal: Control = null
var _chaos_card: Control = null
var _final_scores: Control = null

var _local_player: CharacterBody3D = null
var _is_auctioneer: bool = false

var _auction_item = null
var _current_artifact: Dictionary = {}

func _ready() -> void:
	_ensure_input_map()
	_build_room()
	_spawn_props()
	_setup_canvas()
	_setup_lighting()
	_spawn_local_player()
	_connect_player_signals()

func _build_room() -> void:
	# Floor
	_add_box(Vector3(0, -0.05, 0), Vector3(30, 0.1, 20), Color.html("2a2a2a"))
	# Back wall
	_add_box(Vector3(0, 3, -10), Vector3(30, 6, 0.2), Color.html("1e1e1e"))
	# Front wall
	_add_box(Vector3(0, 3, 10), Vector3(30, 6, 0.2), Color.html("1e1e1e"))
	# Left wall (scoreboard side)
	_add_box(Vector3(-15, 3, 0), Vector3(0.2, 6, 20), Color.html("1e1e1e"))
	# Right wall (phase sign side)
	_add_box(Vector3(15, 3, 0), Vector3(0.2, 6, 20), Color.html("1e1e1e"))
	# Ceiling
	_add_box(Vector3(0, 6.05, 0), Vector3(30, 0.1, 20), Color.html("141414"))

	# Stage platform (back of room, raised 0.5u)
	_add_box(Vector3(0, 0.25, -7), Vector3(14, 0.5, 6), Color.html("3a2a1a"))
	# Podium on stage
	_add_box(Vector3(0, 1.05, -8.5), Vector3(1.5, 1.1, 0.8), Color.html("4a3a2a"))

	# Item pedestal (center of room)
	_add_box(Vector3(0, 0.5, -1), Vector3(1.2, 1.0, 1.2), Color.html("2a3a4a"))
	# Pedestal display label
	_pedestal_label = _make_label3d("WAITING...", Vector3(0, 1.15, -1), 0.06)

	# Scoreboard billboard on left wall
	_add_box(Vector3(-14.8, 3, 0), Vector3(0.1, 3, 8), Color.html("111a11"))
	_scoreboard_label = _make_label3d("SCOREBOARD", Vector3(-14.6, 4.0, 0), 0.05)
	_scoreboard_label.rotation_degrees = Vector3(0, 90, 0)

	# Phase sign on right wall
	_add_box(Vector3(14.8, 4.5, -4), Vector3(0.1, 1.5, 5), Color.html("1a1a11"))
	_phase_sign_label = _make_label3d("NEXT UP", Vector3(14.6, 4.5, -4), 0.07)
	_phase_sign_label.rotation_degrees = Vector3(0, -90, 0)

	# Bid timer chalkboard (right wall, lower)
	_add_box(Vector3(14.8, 2.5, 2), Vector3(0.1, 1.5, 4), Color.html("0a1a0a"))
	_timer_label = _make_label3d("", Vector3(14.6, 2.5, 2), 0.1)
	_timer_label.rotation_degrees = Vector3(0, -90, 0)

	# Spawn point marker (invisible static body — actual spawn positions)
	_add_spawn_points()

func _spawn_props() -> void:
	# Chairs (6) — left side of room
	var chair_positions: Array[Vector3] = [
		Vector3(-8, 0, 0), Vector3(-6, 0, 0), Vector3(-4, 0, 0),
		Vector3(-8, 0, 2), Vector3(-6, 0, 2), Vector3(-4, 0, 2),
	]
	for pos in chair_positions:
		_make_prop(pos, Vector3(0.7, 1.2, 0.7), Color.html("5a3a2a"))

	# Crates (4) — right side
	var crate_positions: Array[Vector3] = [
		Vector3(6, 0, 0), Vector3(8, 0, 0),
		Vector3(6, 0, 2), Vector3(8, 0, 2),
	]
	for pos in crate_positions:
		_make_prop(pos, Vector3(0.9, 0.9, 0.9), Color.html("4a3a1a"))

	# Trinkets (8) — scattered
	var trinket_positions: Array[Vector3] = [
		Vector3(-10, 0, -3), Vector3(-10, 0, -1), Vector3(10, 0, -3), Vector3(10, 0, -1),
		Vector3(-3, 0, -3), Vector3(3, 0, -3), Vector3(-5, 0, 1), Vector3(5, 0, 1),
	]
	for pos in trinket_positions:
		_make_prop(pos, Vector3(0.3, 0.3, 0.3), Color.html("6a6a9a"), ThrowablePropScript.Shape.SPHERE)

func _make_prop(pos: Vector3, size: Vector3, color: Color,
				shape: int = ThrowablePropScript.Shape.BOX) -> RigidBody3D:
	var prop: RigidBody3D = RigidBody3D.new()
	prop.set_script(ThrowablePropScript)
	add_child(prop)
	prop.init(pos, size, color, shape)
	return prop

func _add_box(pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	add_child(body)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mesh.material_override = mat
	body.add_child(mesh)

func _make_label3d(text: String, pos: Vector3, pixel_size: float) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.pixel_size = pixel_size
	lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lbl.double_sided = true
	lbl.no_depth_test = true
	lbl.modulate = Color.WHITE
	lbl.position = pos
	add_child(lbl)
	return lbl

func _add_spawn_points() -> void:
	# 8 spawn positions around the center area
	const SPAWNS: Array[Vector3] = [
		Vector3(-4, 0, 4), Vector3(-2, 0, 4), Vector3(0, 0, 4), Vector3(2, 0, 4),
		Vector3(4, 0, 4), Vector3(-3, 0, 6), Vector3(0, 0, 6), Vector3(3, 0, 6),
	]
	for i in range(SPAWNS.size()):
		var marker := Marker3D.new()
		marker.name = "Spawn%d" % i
		marker.position = SPAWNS[i]
		add_child(marker)

func _process(delta: float) -> void:
	if _bid_counting:
		_bid_time_left -= delta
		if _bid_time_left < 0.0:
			_bid_time_left = 0.0
			_bid_counting = false
		var secs: int = int(ceil(_bid_time_left))
		_timer_label.text = "%d" % secs if secs > 0 else ""
		if _hud:
			_hud.set_countdown(_bid_time_left)

func _setup_canvas() -> void:
	_canvas = CanvasLayer.new()
	add_child(_canvas)

	_hud = HUDOverlayScript.new()
	_canvas.add_child(_hud)

	_auctioneer_overlay = AuctioneerOverlayScript.new()
	_canvas.add_child(_auctioneer_overlay)

	_bid_panel = BidPanelScript.new()
	_canvas.add_child(_bid_panel)

	_bid_reveal = BidRevealScript.new()
	_canvas.add_child(_bid_reveal)

	_chaos_card = ChaosCardScript.new()
	_canvas.add_child(_chaos_card)

	_final_scores = FinalScoresScript.new()
	_canvas.add_child(_final_scores)

func _setup_lighting() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.html("080808")
	env.ambient_light_color = Color.html("ffffff")
	env.ambient_light_energy = 0.3
	env_node.environment = env
	add_child(env_node)

	# Overhead fill light
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-60, 20, 0)
	fill.light_energy = 0.8
	fill.light_color = Color.html("ffe8c0")
	add_child(fill)

	# Cool rim
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-30, -160, 0)
	rim.light_energy = 0.4
	rim.light_color = Color.html("c0d8ff")
	add_child(rim)

	# Spot on pedestal
	var spot := SpotLight3D.new()
	spot.position = Vector3(0, 5.5, -1)
	spot.rotation_degrees = Vector3(-90, 0, 0)
	spot.light_energy = 1.5
	spot.spot_angle = 20.0
	spot.spot_range = 8.0
	add_child(spot)

func _spawn_local_player() -> void:
	_local_player = LocalPlayerScene.instantiate()
	add_child(_local_player)
	# Place at spawn index based on player order
	var idx: int = NetworkManager.player_names.find(NetworkManager.local_name)
	idx = max(idx, 0)
	var spawn := get_node_or_null("Spawn%d" % idx)
	if spawn:
		_local_player.position = spawn.position
	else:
		_local_player.position = Vector3(0, 0, 5)
	# Capture mouse for camera look
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

static func _ensure_input_map() -> void:
	const ACTIONS: Dictionary = {
		"move_forward": KEY_W,
		"move_back":    KEY_S,
		"move_left":    KEY_A,
		"move_right":   KEY_D,
		"jump":         KEY_SPACE,
		"sprint":       KEY_SHIFT,
		"interact":     KEY_E,
	}
	for action in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = ACTIONS[action]
		InputMap.action_add_event(action, ev)

func _connect_player_signals() -> void:
	NetworkManager.player_registered.connect(_on_player_registered)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.player_moved.connect(_on_player_moved)
	# Spawn RemotePlayers for players already in the room
	for p_name in NetworkManager.player_names:
		if p_name != NetworkManager.local_name:
			_spawn_remote_player(p_name)

func _on_player_registered(p_name: String) -> void:
	if p_name != NetworkManager.local_name and not _remote_players.has(p_name):
		_spawn_remote_player(p_name)

func _on_player_disconnected(p_name: String) -> void:
	if _remote_players.has(p_name):
		_remote_players[p_name].queue_free()
		_remote_players.erase(p_name)

func _on_player_moved(p_name: String, x: float, y: float, z: float, ry: float, anim: String) -> void:
	if not _remote_players.has(p_name):
		_spawn_remote_player(p_name)
	_remote_players[p_name].apply_move(x, y, z, ry, anim)

func _spawn_remote_player(p_name: String) -> void:
	var rp: Node3D = RemotePlayerScene.instantiate()
	rp.init(p_name)
	add_child(rp)
	# Tentative start position
	rp.position = Vector3(0, 0, 5)
	_remote_players[p_name] = rp

# --- Phase message stubs (filled in Tasks 6–11) ---

func on_auctioneer_reveal(artifact: Dictionary, _pitch_duration: int) -> void:
	if _is_auctioneer and _auctioneer_overlay:
		_auctioneer_overlay.show_reveal(artifact)

func on_start_pitch(artifact: Dictionary, _pitch_duration: int, round: int = 1, total_rounds: int = 5) -> void:
	_current_artifact = artifact
	_phase_sign_label.text = "PITCH PHASE\nROUND %d/%d" % [round, total_rounds]
	if _hud:
		_hud.set_round(round, total_rounds)
	var cat: String = artifact.get("category", "unknown")
	var cat_color: Color = _UITheme.cat_color(cat)

	# Spawn or reset auction item on pedestal
	if _auction_item == null:
		_auction_item = _make_prop(Vector3(0, 1.2, -1), Vector3(0.4, 0.4, 0.4), cat_color, ThrowablePropScript.Shape.BOX)
	else:
		_auction_item.set_color(cat_color)
		_auction_item.reset_to_home()

	_auction_item.set_interactable(true)
	_pedestal_label.text = "%s\n[%s]" % [artifact.get("name", ""), cat.to_upper()]

func on_auctioneer_name(p_name: String) -> void:
	_is_auctioneer = (NetworkManager.local_name == p_name)
	if _local_player:
		_local_player.set_crown_visible(_is_auctioneer)
	for name in _remote_players:
		_remote_players[name].set_crown_visible(name == p_name)

func on_open_bidding(bid_timeout: float = 30.0) -> void:
	_phase_sign_label.text = "BIDDING OPEN"
	_bid_time_left = bid_timeout
	_bid_counting = true
	if _hud:
		_hud.start_bid_countdown(bid_timeout)
	if _auction_item:
		_auction_item.set_interactable(false)
		_auction_item.lock_to_pedestal()
	if _bid_panel and not _is_auctioneer:
		var own_cash: int = GameServer.player_cash.get(NetworkManager.local_name, 0)
		_bid_panel.open_for_bidding(_current_artifact, bid_timeout, own_cash)

func on_show_bid_result(result: Dictionary) -> void:
	_phase_sign_label.text = "SOLD"
	_bid_counting = false
	_timer_label.text = ""
	if _hud:
		_hud.stop_bid_countdown()
		_hud.update_cash(GameServer.player_cash.get(NetworkManager.local_name, 0))
	if _auctioneer_overlay:
		_auctioneer_overlay.hide_reveal()
	if _bid_panel:
		_bid_panel.close()
	if _bid_reveal:
		_bid_reveal.show_result(result)
	_burst_winner(result.get("winner", ""))

func on_show_chaos(chaos: Dictionary) -> void:
	if chaos.is_empty():
		return
	if _chaos_card:
		_chaos_card.show_chaos(chaos)

func _burst_winner(winner_name: String) -> void:
	var target: Node3D = null
	if winner_name == NetworkManager.local_name:
		target = _local_player
	elif _remote_players.has(winner_name):
		target = _remote_players[winner_name]
	if target == null:
		return
	var particles := CPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 40
	particles.lifetime = 1.5
	particles.initial_velocity_min = 3.0
	particles.initial_velocity_max = 6.0
	particles.color = Color.html("C9A227")
	particles.position = target.position + Vector3(0, 1.5, 0)
	add_child(particles)
	get_tree().create_timer(2.0).timeout.connect(func(): particles.queue_free())

func on_show_final_scores(ranking: Array) -> void:
	_phase_sign_label.text = "GRAND REVEAL"
	if _final_scores:
		_final_scores.show_scores(ranking)
