extends Control

const _UITheme = preload("res://src/scenes/ui_theme.gd")

var _hud: Control
var _result_label: Label
var _chaos_label: Label
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

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(960, 300)
	vbox.add_theme_constant_override("separation", _UITheme.GAP * 2)
	_UITheme.add_center_container(main).add_child(vbox)

	var header := Label.new()
	header.text = "SOLD"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_section_label(header)
	vbox.add_child(header)

	_result_label = Label.new()
	_result_label.text = "..."
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_UITheme.style_label(_result_label, _UITheme.FS_ARTIFACT, _UITheme.TEXT)
	vbox.add_child(_result_label)

	_chaos_label = Label.new()
	_chaos_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chaos_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_UITheme.style_label(_chaos_label, _UITheme.FS_BODY, _UITheme.GOLD)
	vbox.add_child(_chaos_label)

func on_show_bid_result(result: Dictionary) -> void:
	AudioManager.play_resolve()
	if result.winner == "BANK":
		_result_label.text = "No takers.\nBank paid §%d." % result.price
	else:
		var winner_name: String = NetworkManager.player_names.get(
			_peer_id_for_name(result.winner), result.winner)
		_result_label.text = "%s\nwon for §%d!" % [winner_name, result.price]
	# Refresh HUD now that player state has been updated by GameServer
	_hud.refresh()

func on_show_chaos(chaos: Dictionary) -> void:
	if chaos.is_empty():
		return
	if chaos.get("type", "") == "appraiser":
		_chaos_label.text = "APPRAISER: %s" % chaos.text
	else:
		_chaos_label.text = "EVENT: %s" % chaos.text
		var extra: Dictionary = chaos.get("extra", {})
		if extra.has("victim") and extra.has("lost_name"):
			_chaos_label.text += "\n%s loses \"%s\"!" % [extra.victim, extra.lost_name]

func _peer_id_for_name(player_name: String) -> int:
	for pid in NetworkManager.player_names:
		if NetworkManager.player_names[pid] == player_name:
			return pid
	return -1

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
