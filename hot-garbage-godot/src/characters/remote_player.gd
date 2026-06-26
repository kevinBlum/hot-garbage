extends Node3D

const PALETTE: PackedStringArray = [
	"#E74C3C", "#3498DB", "#2ECC71", "#F39C12",
	"#9B59B6", "#1ABC9C", "#E67E22", "#EC407A",
]

var _mesh: MeshInstance3D
var _name_label: Label3D
var _crown_mesh: Node3D

var _target_pos: Vector3 = Vector3.ZERO
var _target_ry: float = 0.0
var _player_name: String = ""

func init(p_name: String) -> void:
	_player_name = p_name

func _ready() -> void:
	var idx: int = NetworkManager.player_names.find(_player_name)
	var color := Color.html(PALETTE[idx % PALETTE.size()])

	# Body mesh
	_mesh = MeshInstance3D.new()
	var cap_mesh := CapsuleMesh.new()
	cap_mesh.radius = 0.4
	cap_mesh.height = 1.8
	_mesh.mesh = cap_mesh
	_mesh.position = Vector3(0, 0.9, 0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	_mesh.material_override = mat
	add_child(_mesh)

	# Crown (hidden; shown when this player is auctioneer)
	_crown_mesh = Node3D.new()
	_crown_mesh.visible = false
	add_child(_crown_mesh)

	var gold_mat := StandardMaterial3D.new()
	gold_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gold_mat.albedo_color = Color.html("C9A227")

	var band := MeshInstance3D.new()
	var band_cyl := CylinderMesh.new()
	band_cyl.top_radius = 0.3
	band_cyl.bottom_radius = 0.3
	band_cyl.height = 0.1
	band.mesh = band_cyl
	band.material_override = gold_mat
	band.position = Vector3(0, 1.95, 0)
	_crown_mesh.add_child(band)

	for i in 5:
		var angle := i * TAU / 5.0
		var spike_h := 0.28 if i % 2 == 0 else 0.18
		var spike := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.065
		cone.height = spike_h
		spike.mesh = cone
		spike.material_override = gold_mat
		spike.position = Vector3(sin(angle) * 0.25, 2.0 + spike_h * 0.5, cos(angle) * 0.25)
		_crown_mesh.add_child(spike)

	# Eyes (show facing direction)
	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = Color.html("1a1a1a")
	for side in [-1, 1]:
		var eye := MeshInstance3D.new()
		var eye_sphere := SphereMesh.new()
		eye_sphere.radius = 0.07
		eye_sphere.height = 0.14
		eye.mesh = eye_sphere
		eye.material_override = eye_mat
		eye.position = Vector3(side * 0.15, 1.55, -0.37)
		add_child(eye)

	# Name label
	_name_label = Label3D.new()
	_name_label.text = _player_name
	_name_label.pixel_size = 0.012
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	_name_label.position = Vector3(0, 2.3, 0)
	add_child(_name_label)

func apply_move(x: float, y: float, z: float, ry: float, _anim: String) -> void:
	_target_pos = Vector3(x, y, z)
	_target_ry = ry

func _physics_process(_delta: float) -> void:
	global_position = global_position.lerp(_target_pos, 0.25)
	rotation.y = lerp_angle(rotation.y, _target_ry, 0.25)

func set_crown_visible(v: bool) -> void:
	_crown_mesh.visible = v
