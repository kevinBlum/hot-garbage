extends Control

const _UITheme = preload("res://src/scenes/ui_theme.gd")

var _score_vbox: VBoxContainer

func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_UITheme.add_bg(self)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", _UITheme.GAP * 2)
	outer.offset_left   = _UITheme.PAD * 2
	outer.offset_top    = _UITheme.PAD * 2
	outer.offset_right  = -_UITheme.PAD * 2
	outer.offset_bottom = -_UITheme.PAD * 2
	outer.custom_minimum_size = Vector2(960, 0)
	scroll.add_child(outer)

	var title := Label.new()
	title.text = "GRAND REVEAL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(title, _UITheme.FS_ARTIFACT, _UITheme.GOLD)
	outer.add_child(title)

	_score_vbox = VBoxContainer.new()
	_score_vbox.add_theme_constant_override("separation", _UITheme.GAP)
	outer.add_child(_score_vbox)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", _UITheme.GAP)
	outer.add_child(btn_row)

	if NetworkManager.is_host():
		var play_again := Button.new()
		play_again.text = "PLAY AGAIN"
		play_again.pressed.connect(_on_play_again)
		_UITheme.style_button(play_again)
		btn_row.add_child(play_again)

	var leave_btn := Button.new()
	leave_btn.text = "LEAVE"
	leave_btn.pressed.connect(_on_leave)
	_UITheme.style_ghost_button(leave_btn)
	btn_row.add_child(leave_btn)

func show_scores(ranking: Array) -> void:
	visible = true
	for child in _score_vbox.get_children():
		child.queue_free()

	const MEDALS: Array[String] = ["#1", "#2", "#3", "#4", "#5", "#6", "#7", "#8"]

	for i in range(ranking.size()):
		var p: Dictionary = ranking[i]
		var medal: String = MEDALS[i] if i < MEDALS.size() else "#%d" % (i + 1)

		var sep := HSeparator.new()
		_score_vbox.add_child(sep)

		var header := Label.new()
		header.text = "%s  %s — %d pts  (§%d cash)" % [medal, p.id, p.total, p.cash]
		_UITheme.style_label(header, _UITheme.FS_BODY, _UITheme.TEXT)
		header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_score_vbox.add_child(header)

		var breakdown: Dictionary = p.get("breakdown", {})
		for cat in breakdown:
			var b: Dictionary = breakdown[cat]
			var completed: bool = b.get("completed", false)
			var set_str: String = ("  SET ×%.1f" % b.get("multiplier", 1.0)) if completed else ""
			var line := Label.new()
			line.text = "  %s: %d items, §%d raw → §%d%s" % [
				cat.capitalize(), b.get("count", 0), b.get("raw", 0), b.get("scored", 0), set_str
			]
			_UITheme.style_label(line, _UITheme.FS_LABEL,
				_UITheme.cat_color(cat) if completed else _UITheme.DIM)
			_score_vbox.add_child(line)

		# Role + objective reveal
		var role_data: Dictionary = p.get("role", {})
		if not role_data.is_empty():
			var role_lbl := Label.new()
			var used_str: String = " (used)" if p.get("abilityUsed", false) else " (never used)"
			role_lbl.text = "  ROLE: %s%s" % [role_data.get("name", "?"), used_str]
			_UITheme.style_label(role_lbl, _UITheme.FS_LABEL, _UITheme.GOLD)
			_score_vbox.add_child(role_lbl)

			var obj_complete: bool = p.get("objectiveComplete", false)
			var obj_bonus: int = p.get("objectiveBonus", 0)
			var obj_result: String = ("COMPLETE +§%d" % obj_bonus) if obj_complete else "INCOMPLETE"
			var obj_lbl := Label.new()
			obj_lbl.text = "  OBJECTIVE: \"%s\" — %s" % [p.get("objectiveItemName", "?"), obj_result]
			_UITheme.style_label(obj_lbl, _UITheme.FS_LABEL,
				_UITheme.GOLD if obj_complete else _UITheme.DIM)
			_score_vbox.add_child(obj_lbl)

		# Auctioneer precision breakdown
		var precision: Array = p.get("precisionHistory", [])
		if not precision.is_empty():
			var avg: float = 0.0
			for m: float in precision:
				avg += m
			avg /= float(precision.size())
			var prec_lbl := Label.new()
			prec_lbl.text = "  AUCTIONEER: avg %.2f× precision over %d round(s)" % [avg, precision.size()]
			_UITheme.style_label(prec_lbl, _UITheme.FS_LABEL, _UITheme.DIM)
			_score_vbox.add_child(prec_lbl)

func _on_play_again() -> void:
	NetworkTransport.send_delete_room()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://src/scenes/main_menu.tscn")

func _on_leave() -> void:
	NetworkManager.disconnect_from_game()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://src/scenes/main_menu.tscn")
