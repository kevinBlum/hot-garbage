extends Node3D

const _UITheme = preload("res://src/scenes/ui_theme.gd")
const LocalPlayerScene = preload("res://src/characters/local_player.tscn")

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

var _local_player: CharacterBody3D = null

func _ready() -> void:
	_ensure_input_map()
	_build_room()
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

func _setup_canvas() -> void:
	_canvas = CanvasLayer.new()
	add_child(_canvas)

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
	# TODO: filled in Task 5
	pass

# --- Phase message stubs (filled in Tasks 6–11) ---

func on_auctioneer_reveal(_artifact: Dictionary, _pitch_duration: int) -> void:
	pass

func on_start_pitch(_artifact: Dictionary, _pitch_duration: int, _round: int = 1, _total_rounds: int = 5) -> void:
	_phase_sign_label.text = "PITCH PHASE"

func on_auctioneer_name(_name: String) -> void:
	pass

func on_open_bidding() -> void:
	_phase_sign_label.text = "BIDDING OPEN"

func on_show_bid_result(_result: Dictionary) -> void:
	_phase_sign_label.text = "SOLD"

func on_show_chaos(_chaos: Dictionary) -> void:
	pass

func on_show_final_scores(_ranking: Array) -> void:
	_phase_sign_label.text = "GRAND REVEAL"
