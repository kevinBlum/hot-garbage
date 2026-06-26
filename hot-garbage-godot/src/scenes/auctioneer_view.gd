extends Control

const _UITheme = preload("res://src/scenes/ui_theme.gd")

var _hud: Control
var _role_label: Label
var _name_label: Label
var _cat_label: Label
var _flavor_label: Label
var _value_label: Label
var _countdown_label: Label
var _open_early_btn: Button
var _bid_status_label: Label
var _force_btn: Button

var _pitch_seconds_left: float = 0.0
var _counting: bool = false
var _player_vbox: VBoxContainer
var _dialog_open: bool = false

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	_UITheme.add_bg(self)

	const HUDScript = preload("res://src/scenes/hud.gd")
	_hud = HUDScript.new()
	add_child(_hud)

	var main := Control.new()
	main.set_anchors_preset(Control.PRESET_FULL_RECT)
	main.offset_left = _UITheme.HUD_WIDTH
	add_child(main)

	var hbox := _UITheme.make_content_hbox(main)

	# Left column (artifact + action stacked)
	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_stretch_ratio = 2.5
	left_col.add_theme_constant_override("separation", _UITheme.GAP)
	hbox.add_child(left_col)

	# Artifact card
	var artifact_card := _UITheme.make_card()
	left_col.add_child(artifact_card)

	var artifact_vbox := VBoxContainer.new()
	artifact_vbox.add_theme_constant_override("separation", _UITheme.GAP)
	artifact_card.add_child(artifact_vbox)

	_role_label = Label.new()
	_role_label.text = "YOU ARE THE AUCTIONEER"
	_role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_section_label(_role_label)
	artifact_vbox.add_child(_role_label)

	_name_label = Label.new()
	_name_label.text = "..."
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_UITheme.style_label(_name_label, _UITheme.FS_ARTIFACT, _UITheme.TEXT)
	artifact_vbox.add_child(_name_label)

	_cat_label = Label.new()
	_cat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(_cat_label, _UITheme.FS_LABEL, _UITheme.DIM)
	artifact_vbox.add_child(_cat_label)

	_value_label = Label.new()
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(_value_label, _UITheme.FS_VALUE, _UITheme.GOLD)
	artifact_vbox.add_child(_value_label)

	_flavor_label = Label.new()
	_flavor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flavor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_UITheme.style_label(_flavor_label, _UITheme.FS_BODY, _UITheme.DIM)
	artifact_vbox.add_child(_flavor_label)

	# Action card
	var action_card := _UITheme.make_card()
	left_col.add_child(action_card)

	var action_vbox := VBoxContainer.new()
	action_vbox.add_theme_constant_override("separation", _UITheme.GAP)
	action_card.add_child(action_vbox)

	_countdown_label = Label.new()
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(_countdown_label, _UITheme.FS_TIMER, _UITheme.TEXT)
	action_vbox.add_child(_countdown_label)

	_bid_status_label = Label.new()
	_bid_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bid_status_label.visible = false
	_UITheme.style_label(_bid_status_label, _UITheme.FS_BODY, _UITheme.DIM)
	action_vbox.add_child(_bid_status_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", _UITheme.GAP)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_vbox.add_child(btn_row)

	_open_early_btn = Button.new()
	_open_early_btn.text = "OPEN EARLY"
	_open_early_btn.pressed.connect(_on_open_early_pressed)
	_UITheme.style_ghost_button(_open_early_btn)
	_open_early_btn.visible = false
	btn_row.add_child(_open_early_btn)

	if NetworkManager.is_host():
		_force_btn = Button.new()
		_force_btn.text = "FORCE RESOLVE"
		_force_btn.pressed.connect(func():
			AudioManager.play_ui()
			NetworkManager.send_force_resolve())
		_UITheme.style_ghost_button(_force_btn)
		_force_btn.visible = false
		btn_row.add_child(_force_btn)

	# Right column (player panel)
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_stretch_ratio = 1.0
	hbox.add_child(right_col)

	var player_card := _UITheme.make_card()
	right_col.add_child(player_card)

	var player_inner := VBoxContainer.new()
	player_inner.add_theme_constant_override("separation", _UITheme.GAP)
	player_card.add_child(player_inner)

	var players_lbl := Label.new()
	players_lbl.text = "PLAYERS"
	_UITheme.style_section_label(players_lbl)
	player_inner.add_child(players_lbl)

	_player_vbox = VBoxContainer.new()
	_player_vbox.add_theme_constant_override("separation", 4)
	player_inner.add_child(_player_vbox)

	_refresh_players()

func _refresh_players() -> void:
	for child in _player_vbox.get_children():
		child.queue_free()
	for name in NetworkManager.player_names:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", _UITheme.GAP)
		_player_vbox.add_child(row)
		var is_me: bool = name == NetworkManager.local_name
		var name_lbl := Label.new()
		name_lbl.text = name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_UITheme.style_label(name_lbl, _UITheme.FS_BODY,
			_UITheme.GOLD if is_me else _UITheme.TEXT)
		row.add_child(name_lbl)
		var cash: int = GameServer.player_cash.get(name, -1)
		var cash_lbl := Label.new()
		cash_lbl.text = "§%d" % cash if cash >= 0 else "—"
		_UITheme.style_label(cash_lbl, _UITheme.FS_BODY, _UITheme.DIM)
		row.add_child(cash_lbl)

func on_auctioneer_reveal(artifact: Dictionary, pitch_duration: int) -> void:
	_refresh_players()
	_name_label.text = artifact.name
	var cat: String = artifact.get("category", "")
	_cat_label.text = cat.to_upper()
	_cat_label.add_theme_color_override("font_color", _UITheme.cat_color(cat))
	_flavor_label.text = '"%s"' % artifact.get("flavor", "")
	_value_label.text = "TRUE VALUE: §%d" % artifact.value

	_pitch_seconds_left = float(pitch_duration)
	_counting = true
	_countdown_label.visible = true
	_update_countdown_display()

	_open_early_btn.visible = true
	_open_early_btn.disabled = false
	_bid_status_label.visible = false

	if not NetworkManager.bid_count_updated.is_connected(_on_bid_count_update):
		NetworkManager.bid_count_updated.connect(_on_bid_count_update)

func on_open_bidding(_bid_timeout: float = 30.0) -> void:
	AudioManager.play_open()
	_counting = false
	_countdown_label.text = "BIDDING OPEN"
	_open_early_btn.visible = false
	_bid_status_label.visible = true
	_bid_status_label.text = "Bids received: 0 / ?"
	if _force_btn != null:
		_force_btn.visible = true

func _on_bid_count_update(received: int, total: int) -> void:
	_bid_status_label.text = "Bids received: %d / %d" % [received, total]

func _on_open_early_pressed() -> void:
	AudioManager.play_ui()
	_open_early_btn.disabled = true
	NetworkManager.send_open_early()

func _process(delta: float) -> void:
	if not _counting:
		return
	_pitch_seconds_left -= delta
	if _pitch_seconds_left < 0.0:
		_pitch_seconds_left = 0.0
		_counting = false
	_update_countdown_display()

func _update_countdown_display() -> void:
	var secs: int = int(ceil(_pitch_seconds_left))
	var mins: int = secs / 60
	var s: int = secs % 60
	_countdown_label.text = "%d:%02d" % [mins, s]

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_show_leave_dialog()

func _show_leave_dialog() -> void:
	if _dialog_open:
		return
	_dialog_open = true
	var dlg := ConfirmationDialog.new()
	dlg.title = "Leave"
	dlg.dialog_text = "Leave game and return to menu?"
	dlg.confirmed.connect(func():
		NetworkManager.disconnect_from_game()
		get_tree().change_scene_to_file("res://src/scenes/main_menu.tscn"))
	dlg.canceled.connect(func():
		_dialog_open = false
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()
