extends Node3D

const PALETTE: PackedStringArray = [
	"#E74C3C", "#3498DB", "#2ECC71", "#F39C12",
	"#9B59B6", "#1ABC9C", "#E67E22", "#EC407A",
]

var _mesh: MeshInstance3D
var _name_label: Label3D
var _crown_mesh: MeshInstance3D

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

	# Crown
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

func apply_move(x: float, y: float, z: float, ry: float, _anim: String) -> void:
	_target_pos = Vector3(x, y, z)
	_target_ry = ry

func _physics_process(_delta: float) -> void:
	global_position = global_position.lerp(_target_pos, 0.25)
	rotation.y = lerp_angle(rotation.y, _target_ry, 0.25)

func set_crown_visible(v: bool) -> void:
	_crown_mesh.visible = v
