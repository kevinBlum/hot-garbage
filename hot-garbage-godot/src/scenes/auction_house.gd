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

const INTERACT_RANGE := 2.5

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

var _role_card: Control = null
var _my_role: Dictionary = {}
var _my_objective: Dictionary = {}
var _ability_used: bool = false

var _local_player: CharacterBody3D = null
var _is_auctioneer: bool = false
var _leave_dialog_open: bool = false

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
	# Back wall (warm, behind stage)
	_add_box(Vector3(0, 3, -10), Vector3(30, 6, 0.2), Color.html("1e1814"))
	# Front wall
	_add_box(Vector3(0, 3, 10), Vector3(30, 6, 0.2), Color.html("1a1a1a"))
	# Left wall (scoreboard side — very subtle green)
	_add_box(Vector3(-15, 3, 0), Vector3(0.2, 6, 20), Color.html("161c16"))
	# Right wall (phase sign side — very subtle cool)
	_add_box(Vector3(15, 3, 0), Vector3(0.2, 6, 20), Color.html("14161e"))
	# Ceiling
	_add_box(Vector3(0, 6.05, 0), Vector3(30, 0.1, 20), Color.html("141414"))

	# Stage platform (back of room, raised 0.5u)
	_add_box(Vector3(0, 0.25, -7), Vector3(14, 0.5, 6), Color.html("3a2a1a"))
	# Podium on stage
	_add_box(Vector3(0, 1.05, -8.5), Vector3(1.5, 1.1, 0.8), Color.html("4a3a2a"))

	# Item pedestal (two-tier: wide base + narrow top)
	_add_box(Vector3(0, 0.25, -1), Vector3(1.6, 0.5, 1.6), Color.html("2a3a4a"))
	_add_box(Vector3(0, 0.75, -1), Vector3(1.0, 0.5, 1.0), Color.html("3a4a5a"))
	# Pedestal display label — floats above tallest item (y ≈ 2.2 clears a 0.65-tall cone)
	_pedestal_label = _make_label3d("WAITING...", Vector3(0, 2.2, -1), 0.06)

	# Scoreboard billboard on left wall — protrudes 0.3 units into room
	_add_box(Vector3(-14.7, 3, 0), Vector3(0.3, 3.4, 8.4), Color.html("0d1a0d"))
	_scoreboard_label = _make_label3d("SCOREBOARD", Vector3(-14.4, 4.0, 0), 0.05)
	_scoreboard_label.rotation_degrees = Vector3(0, 90, 0)

	# Phase sign on right wall — protrudes 0.3 units into room
	_add_box(Vector3(14.7, 4.5, -4), Vector3(0.3, 1.9, 5.4), Color.html("101826"))
	_phase_sign_label = _make_label3d("NEXT UP", Vector3(14.4, 4.5, -4), 0.07)
	_phase_sign_label.rotation_degrees = Vector3(0, -90, 0)

	# Bid timer chalkboard (right wall, lower) — protrudes 0.3 units into room
	_add_box(Vector3(14.7, 2.5, 2), Vector3(0.3, 1.9, 4.4), Color.html("0a1a0a"))
	_timer_label = _make_label3d("", Vector3(14.4, 2.5, 2), 0.1)
	_timer_label.rotation_degrees = Vector3(0, -90, 0)

	# Stage front accent strip (gold tint at leading edge of stage, z≈-4)
	_add_box(Vector3(0, 0.52, -4.0), Vector3(14.0, 0.04, 0.1), Color.html("6a5a3a"))

	# Baseboards along all four walls
	_add_box(Vector3(0, 0.08, -9.9),  Vector3(29.6, 0.16, 0.1),  Color.html("3a2515"))
	_add_box(Vector3(0, 0.08, 9.9),   Vector3(29.6, 0.16, 0.1),  Color.html("3a2515"))
	_add_box(Vector3(-14.9, 0.08, 0), Vector3(0.1,  0.16, 19.6), Color.html("3a2515"))
	_add_box(Vector3(14.9, 0.08, 0),  Vector3(0.1,  0.16, 19.6), Color.html("3a2515"))

	# Floor carpet disc under pedestal (purely visual — no physics)
	var carpet := MeshInstance3D.new()
	var carpet_cyl := CylinderMesh.new()
	carpet_cyl.top_radius = 3.5
	carpet_cyl.bottom_radius = 3.5
	carpet_cyl.height = 0.02
	carpet.mesh = carpet_cyl
	var carpet_mat := StandardMaterial3D.new()
	carpet_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	carpet_mat.albedo_color = Color.html("3a2515")
	carpet.material_override = carpet_mat
	carpet.position = Vector3(0, 0.01, -1)
	add_child(carpet)

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
				shape: int = ThrowablePropScript.Shape.BOX,
				p_is_auction_item: bool = false) -> RigidBody3D:
	var prop: RigidBody3D = RigidBody3D.new()
	prop.set_script(ThrowablePropScript)
	add_child(prop)
	prop.init(pos, size, color, shape, p_is_auction_item)
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

	_role_card = load("res://src/ui/role_card.gd").new()
	_canvas.add_child(_role_card)

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

func _check_interact() -> void:
	if _ability_used or _my_role.is_empty():
		return
	var role_id: String = _my_role.get("id", "")
	var requires_target: bool = _my_role.get("requiresTarget", false)

	if requires_target:
		var nearest_name: String = ""
		var nearest_dist: float = INTERACT_RANGE
		var my_pos: Vector3 = _local_player.position if _local_player else Vector3.ZERO
		for p_name: String in _remote_players:
			var dist: float = my_pos.distance_to((_remote_players[p_name] as Node3D).position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_name = p_name
		if nearest_name.is_empty():
			return
		NetworkTransport.send_ability_activate(role_id, nearest_name)
	else:
		NetworkTransport.send_ability_activate(role_id, "")

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_check_interact()
		return
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			_show_leave_dialog()

func _show_leave_dialog() -> void:
	if _leave_dialog_open:
		return
	_leave_dialog_open = true
	var dlg := ConfirmationDialog.new()
	dlg.title = "Leave Game"
	dlg.dialog_text = "Leave game and return to main menu?"
	dlg.confirmed.connect(func():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		NetworkManager.disconnect_from_game()
		get_tree().change_scene_to_file("res://src/scenes/main_menu.tscn"))
	dlg.canceled.connect(func():
		_leave_dialog_open = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()

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

func _on_role_assigned(role: Dictionary, objective: Dictionary) -> void:
	_my_role = role
	_my_objective = objective
	_ability_used = false
	if _role_card:
		_role_card.show_assigned(role, objective)
		get_tree().create_timer(5.0).timeout.connect(func(): _role_card._start_fade())

func _on_ability_result(data: Dictionary) -> void:
	var actor: String = data.get("actorName", "")
	if actor == NetworkManager.local_name:
		_ability_used = true
	var target_node: Node3D = null
	if actor == NetworkManager.local_name:
		target_node = _local_player
	elif _remote_players.has(actor):
		target_node = _remote_players[actor]
	if target_node == null:
		return
	var lbl := Label3D.new()
	lbl.text = data.get("abilityType", "").to_upper().replace("_", " ")
	lbl.pixel_size = 0.05
	lbl.no_depth_test = true
	lbl.modulate = Color.html("C9A227")
	lbl.position = target_node.position + Vector3(0, 2.5, 0)
	add_child(lbl)
	get_tree().create_timer(2.5).timeout.connect(func(): lbl.queue_free())

func _connect_player_signals() -> void:
	NetworkManager.player_registered.connect(_on_player_registered)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.player_moved.connect(_on_player_moved)
	NetworkManager.role_assigned.connect(_on_role_assigned)
	NetworkManager.ability_result.connect(_on_ability_result)
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

func _category_shape(cat: String) -> Dictionary:
	match cat:
		"antiquities": return {"shape": ThrowablePropScript.Shape.CONE,    "size": Vector3(0.22, 0.65, 0.22), "pos": Vector3(0, 1.325, -1)}
		"curios":      return {"shape": ThrowablePropScript.Shape.SPHERE,  "size": Vector3(0.32, 0.32, 0.32), "pos": Vector3(0, 1.32, -1)}
		"relics":      return {"shape": ThrowablePropScript.Shape.CAPSULE, "size": Vector3(0.18, 0.60, 0.18), "pos": Vector3(0, 1.30, -1)}
		"forgeries":   return {"shape": ThrowablePropScript.Shape.BOX,     "size": Vector3(0.50, 0.50, 0.50), "pos": Vector3(0, 1.25, -1)}
		"junk":        return {"shape": ThrowablePropScript.Shape.BOX,     "size": Vector3(0.65, 0.30, 0.45), "pos": Vector3(0, 1.15, -1)}
		_:             return {"shape": ThrowablePropScript.Shape.SPHERE,  "size": Vector3(0.38, 0.38, 0.38), "pos": Vector3(0, 1.38, -1)}

func on_start_pitch(artifact: Dictionary, _pitch_duration: int, round: int = 1, total_rounds: int = 5) -> void:
	_current_artifact = artifact
	_phase_sign_label.text = "PITCH PHASE\nROUND %d/%d" % [round, total_rounds]
	if _hud:
		_hud.set_round(round, total_rounds)
	var cat: String = artifact.get("category", "unknown")
	var cat_color: Color = _UITheme.cat_color(cat)

	# Recreate auction item with category-specific shape and position
	if _auction_item != null:
		_auction_item.queue_free()
		_auction_item = null
	var shape_info := _category_shape(cat)
	_auction_item = _make_prop(shape_info.pos, shape_info.size, cat_color, shape_info.shape, true)

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
