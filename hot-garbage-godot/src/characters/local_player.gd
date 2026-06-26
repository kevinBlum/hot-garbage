extends CharacterBody3D

const SPEED        := 5.0
const SPRINT_MULT  := 1.8
const JUMP_VEL     := 5.0
const GRAVITY      := 9.8
const SEND_INTERVAL := 0.1   # 10 Hz

var _camera_arm: SpringArm3D
var _camera: Camera3D
var _mesh: MeshInstance3D
var _name_label: Label3D
var _crown_mesh: MeshInstance3D
var _hand_anchor: Node3D
var _grab_area: Area3D

var _held_object: RigidBody3D = null
var _send_timer: float = 0.0
var _player_name: String = ""
var _color: Color = Color.WHITE
var _scene_root: Node3D
var _camera_yaw: float = 0.0
var _camera_pitch: float = deg_to_rad(-20.0)

const PALETTE: PackedStringArray = [
	"#E74C3C", "#3498DB", "#2ECC71", "#F39C12",
	"#9B59B6", "#1ABC9C", "#E67E22", "#EC407A",
]

func _ready() -> void:
	_player_name = NetworkManager.local_name
	var idx: int = NetworkManager.player_names.find(_player_name)
	_color = Color.html(PALETTE[idx % PALETTE.size()])
	_build_nodes()
	_scene_root = get_parent() as Node3D

func _build_nodes() -> void:
	# Collision capsule
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	# Body mesh (capsule placeholder)
	_mesh = MeshInstance3D.new()
	var cap_mesh := CapsuleMesh.new()
	cap_mesh.radius = 0.4
	cap_mesh.height = 1.8
	_mesh.mesh = cap_mesh
	_mesh.position = Vector3(0, 0.9, 0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = _color
	_mesh.material_override = mat
	add_child(_mesh)

	# Hand anchor (right hand position for held objects)
	_hand_anchor = Node3D.new()
	_hand_anchor.position = Vector3(0.5, 0.9, -0.7)
	add_child(_hand_anchor)

	# Crown mesh (hidden; shown when this player is auctioneer)
	_crown_mesh = MeshInstance3D.new()
	var crown_box := BoxMesh.new()
	crown_box.size = Vector3(0.6, 0.2, 0.6)
	_crown_mesh.mesh = crown_box
	_crown_mesh.position = Vector3(0, 2.0, 0)
	var crown_mat := StandardMaterial3D.new()
	crown_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	crown_mat.albedo_color = Color.html("C9A227")
	_crown_mesh.material_override = crown_mat
	_crown_mesh.visible = false
	add_child(_crown_mesh)

	# Name label
	_name_label = Label3D.new()
	_name_label.text = _player_name
	_name_label.pixel_size = 0.012
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	_name_label.position = Vector3(0, 2.3, 0)
	add_child(_name_label)

	# Camera spring arm (third-person)
	_camera_arm = SpringArm3D.new()
	_camera_arm.position = Vector3(0, 1.6, 0)
	_camera_arm.spring_length = 4.0
	add_child(_camera_arm)

	_camera = Camera3D.new()
	_camera_arm.add_child(_camera)

	# Grab detection area (sphere in front of player)
	_grab_area = Area3D.new()
	var grab_col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.5
	grab_col.shape = sphere
	_grab_area.add_child(grab_col)
	_grab_area.position = Vector3(0, 0.9, -1.0)
	add_child(_grab_area)

func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# WASD input relative to camera yaw only (world-aligned, ignores player facing)
	var input := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_back")
	)
	var yaw_basis := Basis(Vector3.UP, _camera_yaw)
	# yaw_basis.z points in +Z (backward); adding input.y gives -Z when W pressed
	var dir := (yaw_basis.x * input.x + yaw_basis.z * input.y).normalized()
	dir.y = 0.0

	var speed := SPEED * (SPRINT_MULT if Input.is_action_pressed("sprint") else 1.0)
	if dir.length() > 0.0:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		rotation.y = atan2(-dir.x, -dir.z)
	else:
		velocity.x = move_toward(velocity.x, 0, speed * 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0, speed * 6.0 * delta)

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VEL

	move_and_slide()

	# Interact (grab / throw)
	if Input.is_action_just_pressed("interact"):
		if _held_object:
			_throw()
		else:
			_try_grab()

	# Network position send at 10 Hz
	_send_timer += delta
	if _send_timer >= SEND_INTERVAL:
		_send_timer = 0.0
		var anim := "idle"
		if _held_object:
			anim = "hold"
		elif velocity.length() > 0.5:
			anim = "run"
		NetworkTransport.send_position(global_position, rotation.y, anim)

	# Camera rotation applied LAST — after rotation.y is set — so the parent's
	# rotation is already settled when we write global_rotation this frame
	var mouse_delta := Input.get_last_mouse_velocity() * 0.0002
	_camera_yaw -= mouse_delta.x
	_camera_pitch = clamp(_camera_pitch - mouse_delta.y, -1.2, 0.3)
	_camera_arm.global_rotation = Vector3(_camera_pitch, _camera_yaw, 0.0)

func _try_grab() -> void:
	var bodies := _grab_area.get_overlapping_bodies()
	var nearest: RigidBody3D = null
	var nearest_dist := INF
	for body in bodies:
		if body is RigidBody3D and body.is_in_group("interactable"):
			var d := global_position.distance_to(body.global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest = body
	if nearest:
		_held_object = nearest
		nearest.freeze = true
		nearest.reparent(_hand_anchor, true)
		nearest.position = Vector3.ZERO

func _throw() -> void:
	if not _held_object:
		return
	var obj := _held_object
	_held_object = null
	obj.reparent(_scene_root, true)
	obj.freeze = false
	var throw_dir := -_camera_arm.global_basis.z.normalized()
	obj.linear_velocity = throw_dir * 12.0 + Vector3(0, 4.0, 0)

func set_crown_visible(v: bool) -> void:
	_crown_mesh.visible = v
