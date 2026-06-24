extends Control

const _UITheme = preload("res://src/scenes/ui_theme.gd")

var _player_list: VBoxContainer
var _start_btn: Button
var _status_label: Label
var _timer_spin: SpinBox

func _ready() -> void:
	_build_ui()
	NetworkManager.player_registered.connect(_on_player_changed)
	NetworkManager.player_disconnected.connect(_on_player_changed)
	_refresh_player_list()

func _build_ui() -> void:
	_UITheme.add_bg(self)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(420, 420)
	vbox.add_theme_constant_override("separation", _UITheme.GAP * 2)
	add_child(vbox)

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

		_start_btn = Button.new()
		_start_btn.text = "START GAME"
		_start_btn.pressed.connect(_on_start_pressed)
		_UITheme.style_button(_start_btn)
		vbox.add_child(_start_btn)

func _refresh_player_list() -> void:
	for child in _player_list.get_children():
		child.queue_free()
	for peer_id in NetworkManager.player_names:
		var lbl := Label.new()
		lbl.text = "• %s" % NetworkManager.player_names[peer_id]
		_UITheme.style_label(lbl, _UITheme.FS_BODY, _UITheme.TEXT)
		_player_list.add_child(lbl)
	var count := NetworkManager.player_names.size()
	if NetworkManager.is_host():
		_status_label.text = "%d player(s) connected" % count

func _on_player_changed(_a = null, _b = null) -> void:
	_refresh_player_list()

func _on_start_pressed() -> void:
	var player_ids: Array = []
	for peer_id in NetworkManager.player_names:
		player_ids.append(NetworkManager.player_names[peer_id])
	var duration: int = 45
	if _timer_spin != null:
		duration = int(_timer_spin.value)
	GameServer.start_game(player_ids, duration)
