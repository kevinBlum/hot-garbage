extends RigidBody3D

const _UITheme = preload("res://src/scenes/ui_theme.gd")

enum Shape { BOX, CAPSULE, SPHERE }

var _home_pos: Vector3 = Vector3.ZERO
var _is_auction_item: bool = false
var _mesh_instance: MeshInstance3D = null

func init(pos: Vector3, size: Vector3, color: Color, shape: int = Shape.BOX, p_is_auction_item: bool = false) -> void:
	_home_pos = pos
	_is_auction_item = p_is_auction_item
	position = pos
	add_to_group("interactable")

	var col := CollisionShape3D.new()
	match shape:
		Shape.BOX:
			var box := BoxShape3D.new()
			box.size = size
			col.shape = box
		Shape.CAPSULE:
			var cap := CapsuleShape3D.new()
			cap.radius = size.x
			cap.height = size.y
			col.shape = cap
		Shape.SPHERE:
			var sphere := SphereShape3D.new()
			sphere.radius = size.x
			col.shape = sphere
	add_child(col)

	var mesh := MeshInstance3D.new()
	match shape:
		Shape.BOX:
			var box_mesh := BoxMesh.new()
			box_mesh.size = size
			mesh.mesh = box_mesh
		Shape.CAPSULE:
			var cap_mesh := CapsuleMesh.new()
			cap_mesh.radius = size.x
			cap_mesh.height = size.y
			mesh.mesh = cap_mesh
		Shape.SPHERE:
			var sphere_mesh := SphereMesh.new()
			sphere_mesh.radius = size.x
			sphere_mesh.height = size.x * 2
			mesh.mesh = sphere_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mesh.material_override = mat
	add_child(mesh)
	_mesh_instance = mesh

func set_color(c: Color) -> void:
	if _mesh_instance == null:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = c
	_mesh_instance.material_override = mat

func reset_to_home() -> void:
	freeze = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	position = _home_pos
	rotation = Vector3.ZERO

func lock_to_pedestal() -> void:
	freeze = true
	position = _home_pos
	rotation = Vector3.ZERO

func set_interactable(v: bool) -> void:
	if v:
		add_to_group("interactable")
	else:
		remove_from_group("interactable")
