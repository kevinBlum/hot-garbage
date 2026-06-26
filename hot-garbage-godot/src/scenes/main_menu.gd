extends Control

const _UITheme = preload("res://src/scenes/ui_theme.gd")

var _name_field: LineEdit
var _room_field: LineEdit
var _password_field: LineEdit
var _status_label: Label
var _hint_label: Label
var _action_btn: Button
var _host_tab: Button
var _join_tab: Button
var _mode: String = "host"  # "host" or "join"
var _dialog_open: bool = false

func _ready() -> void:
	_build_ui()
	NetworkManager.room_joined.connect(_on_room_joined)
	NetworkManager.error_received.connect(_on_error)
	NetworkManager.connection_failed.connect(_on_connection_failed)

func _build_ui() -> void:
	_UITheme.add_bg(self)

	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(960, 520)
	hbox.add_theme_constant_override("separation", 0)
	_UITheme.add_center_container(self).add_child(hbox)

	# --- Left: branding ---
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
	meta.text = "2–8 players · ~45 min"
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(meta, _UITheme.FS_LABEL, _UITheme.DIM)
	left.add_child(meta)

	# --- Separator ---
	var sep := VSeparator.new()
	_UITheme.style_vseparator(sep)
	hbox.add_child(sep)

	# --- Right: form ---
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

	var room_lbl := Label.new()
	room_lbl.text = "ROOM NAME"
	_UITheme.style_section_label(room_lbl)
	right.add_child(room_lbl)

	_room_field = LineEdit.new()
	_room_field.placeholder_text = "e.g. kevins-garbage"
	_UITheme.style_line_edit(_room_field)
	right.add_child(_room_field)

	var pw_lbl := Label.new()
	pw_lbl.text = "PASSWORD"
	_UITheme.style_section_label(pw_lbl)
	right.add_child(pw_lbl)

	_password_field = LineEdit.new()
	_password_field.placeholder_text = "Room password"
	_password_field.secret = true
	_UITheme.style_line_edit(_password_field)
	right.add_child(_password_field)

	# Host / Join tab row
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 0)
	right.add_child(tab_row)

	_host_tab = Button.new()
	_host_tab.text = "HOST"
	_host_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_tab.pressed.connect(_set_mode.bind("host"))
	_UITheme.style_button(_host_tab)
	tab_row.add_child(_host_tab)

	_join_tab = Button.new()
	_join_tab.text = "JOIN"
	_join_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_tab.pressed.connect(_set_mode.bind("join"))
	_UITheme.style_ghost_button(_join_tab)
	tab_row.add_child(_join_tab)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_UITheme.style_label(_hint_label, _UITheme.FS_LABEL, _UITheme.DIM)
	right.add_child(_hint_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, _UITheme.GAP)
	right.add_child(spacer)

	_action_btn = Button.new()
	_action_btn.pressed.connect(_on_action_pressed)
	_UITheme.style_button(_action_btn)
	right.add_child(_action_btn)

	var settings_btn := Button.new()
	settings_btn.text = "SETTINGS"
	settings_btn.pressed.connect(_on_settings_pressed)
	_UITheme.style_ghost_button(settings_btn)
	right.add_child(settings_btn)

	if OS.is_debug_build():
		var dev_btn := Button.new()
		dev_btn.text = "QUICK PLAY (DEV)"
		dev_btn.pressed.connect(_on_dev_play_pressed)
		_UITheme.style_ghost_button(dev_btn)
		dev_btn.add_theme_color_override("font_color", Color.html("E67E22"))
		right.add_child(dev_btn)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(_status_label, _UITheme.FS_BODY, _UITheme.DIM)
	right.add_child(_status_label)

	_set_mode("host")

func _validate() -> bool:
	if _name_field.text.strip_edges().is_empty():
		_status_label.text = "Enter your name."
		return false
	if _room_field.text.strip_edges().is_empty():
		_status_label.text = "Enter a room name."
		return false
	return true

func _set_mode(m: String) -> void:
	_mode = m
	if m == "host":
		_UITheme.style_button(_host_tab)
		_UITheme.style_ghost_button(_join_tab)
		_hint_label.text = "You'll create the room and start the game."
		_action_btn.text = "CREATE ROOM"
	else:
		_UITheme.style_ghost_button(_host_tab)
		_UITheme.style_button(_join_tab)
		_hint_label.text = "Enter the room name and password your host shared."
		_action_btn.text = "JOIN ROOM"
	_status_label.text = ""

func _on_action_pressed() -> void:
	AudioManager.play_ui()
	if not _validate():
		return
	if _mode == "host":
		_status_label.text = "Creating room..."
		NetworkManager.create_room(
			_room_field.text.strip_edges(),
			_password_field.text,
			_name_field.text.strip_edges()
		)
	else:
		_status_label.text = "Joining room..."
		NetworkManager.join_room(
			_room_field.text.strip_edges(),
			_password_field.text,
			_name_field.text.strip_edges()
		)

func _on_room_joined(_room_name: String, _is_host: bool) -> void:
	get_tree().change_scene_to_file("res://src/scenes/lobby.tscn")

func _on_error(code: String, _message: String) -> void:
	var friendly := {
		"NAME_TAKEN": "That room name is taken. Try another.",
		"ROOM_NOT_FOUND": "Room not found. Check the name.",
		"WRONG_PASSWORD": "Wrong password.",
		"NAME_IN_USE": "That player name is already in use in this room.",
		"ROOM_FULL": "Room is full.",
		"GAME_IN_PROGRESS": "A game is in progress in that room.",
	}
	_status_label.text = friendly.get(code, "Error: %s" % code)

func _on_connection_failed() -> void:
	_status_label.text = "Could not connect to server."

func _on_dev_play_pressed() -> void:
	NetworkManager.local_name = "DevPlayer"
	NetworkManager.player_names = ["DevPlayer"]
	get_tree().change_scene_to_file("res://src/scenes/auction_house.tscn")

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
