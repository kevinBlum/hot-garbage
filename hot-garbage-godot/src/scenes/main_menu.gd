extends Control

const _UITheme = preload("res://src/scenes/ui_theme.gd")

var _name_field: LineEdit
var _ip_field: LineEdit
var _status_label: Label
var _dialog_open: bool = false

func _ready() -> void:
	_build_ui()
	NetworkManager.player_registered.connect(_on_registered)
	NetworkManager.connection_failed.connect(_on_connection_failed)

func _build_ui() -> void:
	_UITheme.add_bg(self)

	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(960, 520)
	hbox.add_theme_constant_override("separation", 0)
	_UITheme.add_center_container(self).add_child(hbox)

	# --- Left panel: branding ---
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", _UITheme.GAP * 2)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(left)

	var title := Label.new()
	title.text = "HOT GARBAGE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(title, _UITheme.FS_ARTIFACT, _UITheme.GOLD)
	left.add_child(title)

	var tagline := Label.new()
	tagline.text = "a game of bluffing, bidding,\nand bad provenance"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(tagline, _UITheme.FS_LABEL, _UITheme.DIM)
	left.add_child(tagline)

	var meta := Label.new()
	meta.text = "2–6 players · ~45 min"
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(meta, _UITheme.FS_LABEL, _UITheme.DIM)
	left.add_child(meta)

	# --- Separator ---
	var sep := VSeparator.new()
	_UITheme.style_vseparator(sep)
	hbox.add_child(sep)

	# --- Right panel: form ---
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", _UITheme.GAP)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(right)

	var name_lbl := Label.new()
	name_lbl.text = "PLAYER NAME"
	_UITheme.style_section_label(name_lbl)
	right.add_child(name_lbl)

	_name_field = LineEdit.new()
	_name_field.placeholder_text = "Your name"
	_UITheme.style_line_edit(_name_field)
	right.add_child(_name_field)

	var ip_lbl := Label.new()
	ip_lbl.text = "HOST IP"
	_UITheme.style_section_label(ip_lbl)
	right.add_child(ip_lbl)

	_ip_field = LineEdit.new()
	_ip_field.placeholder_text = "Leave blank to host"
	_UITheme.style_line_edit(_ip_field)
	right.add_child(_ip_field)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, _UITheme.GAP)
	right.add_child(spacer)

	var host_btn := Button.new()
	host_btn.text = "HOST GAME"
	host_btn.pressed.connect(_on_host_pressed)
	_UITheme.style_button(host_btn)
	right.add_child(host_btn)

	var join_btn := Button.new()
	join_btn.text = "JOIN GAME"
	join_btn.pressed.connect(_on_join_pressed)
	_UITheme.style_ghost_button(join_btn)
	right.add_child(join_btn)

	var settings_btn := Button.new()
	settings_btn.text = "SETTINGS"
	settings_btn.pressed.connect(_on_settings_pressed)
	_UITheme.style_ghost_button(settings_btn)
	right.add_child(settings_btn)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(_status_label, _UITheme.FS_BODY, _UITheme.DIM)
	right.add_child(_status_label)

func _on_host_pressed() -> void:
	AudioManager.play_ui()
	var name := _name_field.text.strip_edges()
	if name.is_empty():
		_status_label.text = "Enter your name first."
		return
	_status_label.text = "Hosting..."
	NetworkManager.host(name)
	if NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.disconnect(_on_connection_failed)
	get_tree().change_scene_to_file("res://src/scenes/lobby.tscn")

func _on_join_pressed() -> void:
	AudioManager.play_ui()
	var name := _name_field.text.strip_edges()
	var ip := _ip_field.text.strip_edges()
	if name.is_empty():
		_status_label.text = "Enter your name first."
		return
	if ip.is_empty():
		ip = "127.0.0.1"
	_status_label.text = "Connecting to %s..." % ip
	if NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.disconnect(_on_connection_failed)
	NetworkManager.join(ip, name)

func _on_registered(_peer_id: int, _name: String) -> void:
	if not NetworkManager.is_host():
		NetworkManager.player_registered.disconnect(_on_registered)
		get_tree().change_scene_to_file("res://src/scenes/lobby.tscn")

func _on_settings_pressed() -> void:
	AudioManager.play_ui()
	get_tree().change_scene_to_file("res://src/scenes/settings.tscn")

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_show_quit_dialog()

func _show_quit_dialog() -> void:
	if _dialog_open:
		return
	_dialog_open = true
	var dlg := ConfirmationDialog.new()
	dlg.title = "Quit"
	dlg.dialog_text = "Quit Hot Garbage?"
	dlg.confirmed.connect(func(): get_tree().quit())
	dlg.canceled.connect(func():
		_dialog_open = false
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()

func _on_connection_failed() -> void:
	_status_label.text = "Connection failed."
