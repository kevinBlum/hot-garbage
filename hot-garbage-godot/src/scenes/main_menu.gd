extends Control

const _UITheme = preload("res://src/scenes/ui_theme.gd")

var _name_field: LineEdit
var _ip_field: LineEdit
var _status_label: Label

func _ready() -> void:
	_build_ui()
	NetworkManager.player_registered.connect(_on_registered)
	NetworkManager.connection_failed.connect(_on_connection_failed)

func _build_ui() -> void:
	_UITheme.add_bg(self)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(640, 480)
	vbox.add_theme_constant_override("separation", _UITheme.GAP * 2)
	add_child(vbox)

	var title := Label.new()
	title.text = "HOT GARBAGE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(title, _UITheme.FS_ARTIFACT, _UITheme.GOLD)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "a game of bluffing, bidding, and bad provenance"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(subtitle, _UITheme.FS_LABEL, _UITheme.DIM)
	vbox.add_child(subtitle)

	_name_field = LineEdit.new()
	_name_field.placeholder_text = "Your name"
	_UITheme.style_line_edit(_name_field)
	vbox.add_child(_name_field)

	_ip_field = LineEdit.new()
	_ip_field.placeholder_text = "Host IP (leave blank to host)"
	_UITheme.style_line_edit(_ip_field)
	vbox.add_child(_ip_field)

	var host_btn := Button.new()
	host_btn.text = "HOST GAME"
	host_btn.pressed.connect(_on_host_pressed)
	_UITheme.style_button(host_btn)
	vbox.add_child(host_btn)

	var join_btn := Button.new()
	join_btn.text = "JOIN GAME"
	join_btn.pressed.connect(_on_join_pressed)
	_UITheme.style_ghost_button(join_btn)
	vbox.add_child(join_btn)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(_status_label, _UITheme.FS_BODY, _UITheme.DIM)
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
	if not NetworkManager.is_host():
		NetworkManager.player_registered.disconnect(_on_registered)
		get_tree().change_scene_to_file("res://src/scenes/lobby.tscn")

func _on_connection_failed() -> void:
	_status_label.text = "Connection failed."
