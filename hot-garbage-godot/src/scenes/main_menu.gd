extends Control

var _name_field: LineEdit
var _ip_field: LineEdit
var _status_label: Label

func _ready() -> void:
	_build_ui()
	NetworkManager.player_registered.connect(_on_registered)
	NetworkManager.connection_failed.connect(_on_connection_failed)

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(400, 300)
	add_child(vbox)

	var title := Label.new()
	title.text = "HOT GARBAGE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_name_field = LineEdit.new()
	_name_field.placeholder_text = "Your name"
	vbox.add_child(_name_field)

	_ip_field = LineEdit.new()
	_ip_field.placeholder_text = "Host IP (leave blank to host)"
	vbox.add_child(_ip_field)

	var host_btn := Button.new()
	host_btn.text = "Host Game"
	host_btn.pressed.connect(_on_host_pressed)
	vbox.add_child(host_btn)

	var join_btn := Button.new()
	join_btn.text = "Join Game"
	join_btn.pressed.connect(_on_join_pressed)
	vbox.add_child(join_btn)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status_label)

func _on_host_pressed() -> void:
	var name := _name_field.text.strip_edges()
	if name.is_empty():
		_status_label.text = "Enter your name first."
		return
	_status_label.text = "Hosting..."
	NetworkManager.host(name)
	get_tree().change_scene_to_file("res://src/scenes/lobby.tscn")

func _on_join_pressed() -> void:
	var name := _name_field.text.strip_edges()
	var ip := _ip_field.text.strip_edges()
	if name.is_empty():
		_status_label.text = "Enter your name first."
		return
	if ip.is_empty():
		ip = "127.0.0.1"
	_status_label.text = "Connecting to %s..." % ip
	NetworkManager.join(ip, name)

func _on_registered(_peer_id: int, _name: String) -> void:
	# Only the local client fires this on a successful join
	if not NetworkManager.is_host():
		get_tree().change_scene_to_file("res://src/scenes/lobby.tscn")

func _on_connection_failed() -> void:
	_status_label.text = "Connection failed."
