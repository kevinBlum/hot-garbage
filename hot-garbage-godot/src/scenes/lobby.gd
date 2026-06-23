extends Control

var _player_list: VBoxContainer
var _start_btn: Button
var _status_label: Label

func _ready() -> void:
	_build_ui()
	NetworkManager.player_registered.connect(_on_player_changed)
	NetworkManager.player_disconnected.connect(_on_player_changed)
	_refresh_player_list()

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(400, 400)
	add_child(vbox)

	var title := Label.new()
	title.text = "Lobby"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_player_list = VBoxContainer.new()
	vbox.add_child(_player_list)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status_label)

	if NetworkManager.is_host():
		_start_btn = Button.new()
		_start_btn.text = "Start Game"
		_start_btn.pressed.connect(_on_start_pressed)
		vbox.add_child(_start_btn)

func _refresh_player_list() -> void:
	for child in _player_list.get_children():
		child.queue_free()
	for peer_id in NetworkManager.player_names:
		var lbl := Label.new()
		lbl.text = "• %s" % NetworkManager.player_names[peer_id]
		_player_list.add_child(lbl)
	var count := NetworkManager.player_names.size()
	if NetworkManager.is_host():
		_status_label.text = "%d player(s) — need 4 to start (or start anyway for testing)" % count

func _on_player_changed(_a = null, _b = null) -> void:
	_refresh_player_list()

func _on_start_pressed() -> void:
	var player_ids: Array = []
	for peer_id in NetworkManager.player_names:
		player_ids.append(NetworkManager.player_names[peer_id])
	GameServer.start_game(player_ids)
	# GameServer will drive scene transitions from here
