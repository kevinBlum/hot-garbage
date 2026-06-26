extends Control

const _UITheme = preload("res://src/scenes/ui_theme.gd")

var _player_list: VBoxContainer
var _start_btn: Button
var _status_label: Label
var _timer_spin: SpinBox

func _ready() -> void:
	_build_ui()
	NetworkManager.player_registered.connect(func(_n): _refresh_player_list())
	NetworkManager.player_disconnected.connect(func(_n): _refresh_player_list())
	_refresh_player_list()

func _build_ui() -> void:
	_UITheme.add_bg(self)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(640, 520)
	vbox.add_theme_constant_override("separation", _UITheme.GAP * 2)
	_UITheme.add_center_container(self).add_child(vbox)

	var title := Label.new()
	title.text = "LOBBY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(title, _UITheme.FS_ARTIFACT, _UITheme.GOLD)
	vbox.add_child(title)

	var players_lbl := Label.new()
	players_lbl.text = "PLAYERS"
	_UITheme.style_section_label(players_lbl)
	vbox.add_child(players_lbl)

	_player_list = VBoxContainer.new()
	_player_list.add_theme_constant_override("separation", _UITheme.GAP)
	vbox.add_child(_player_list)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(_status_label, _UITheme.FS_BODY, _UITheme.DIM)
	vbox.add_child(_status_label)

	if NetworkManager.is_host():
		var timer_lbl := Label.new()
		timer_lbl.text = "PITCH TIMER"
		_UITheme.style_section_label(timer_lbl)
		vbox.add_child(timer_lbl)

		_timer_spin = SpinBox.new()
		_timer_spin.min_value = 20
		_timer_spin.max_value = 120
		_timer_spin.step = 5
		_timer_spin.value = 45
		_timer_spin.suffix = " sec"
		_timer_spin.add_theme_font_override("font", _UITheme.mono())
		_timer_spin.add_theme_font_size_override("font_size", _UITheme.FS_BODY)
		_UITheme.style_line_edit(_timer_spin.get_line_edit())
		vbox.add_child(_timer_spin)

		if NetworkManager.server_restarted:
			var restart_lbl := Label.new()
			restart_lbl.text = "Server restarted — start a new game."
			_UITheme.style_label(restart_lbl, _UITheme.FS_BODY, Color(1, 0.6, 0.2))
			restart_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vbox.add_child(restart_lbl)

		_start_btn = Button.new()
		_start_btn.text = "START GAME"
		_start_btn.pressed.connect(_on_start_pressed)
		_UITheme.style_button(_start_btn)
		vbox.add_child(_start_btn)

	var leave_btn := Button.new()
	leave_btn.text = "LEAVE LOBBY"
	leave_btn.pressed.connect(_on_leave_pressed)
	_UITheme.style_ghost_button(leave_btn)
	vbox.add_child(leave_btn)

func _refresh_player_list() -> void:
	for child in _player_list.get_children():
		child.queue_free()
	for name in NetworkManager.player_names:
		var lbl := Label.new()
		lbl.text = "• %s" % name
		_UITheme.style_label(lbl, _UITheme.FS_BODY, _UITheme.TEXT)
		_player_list.add_child(lbl)
	var count := NetworkManager.player_names.size()
	if NetworkManager.is_host():
		_status_label.text = "%d player(s) connected" % count

func _on_start_pressed() -> void:
	AudioManager.play_ui()
	var duration: int = 45
	if _timer_spin != null:
		duration = int(_timer_spin.value)
	NetworkManager.start_game(duration)

func _on_leave_pressed() -> void:
	AudioManager.play_ui()
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://src/scenes/main_menu.tscn")
