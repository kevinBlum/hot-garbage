extends Control

const _UITheme = preload("res://src/scenes/ui_theme.gd")

var _hud: Control
var _score_vbox: VBoxContainer
var _waiting_label: Label

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

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	main.add_child(scroll)

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

	_waiting_label = Label.new()
	_waiting_label.name = "WaitingLabel"
	_waiting_label.text = "Calculating scores..."
	_waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(_waiting_label, _UITheme.FS_BODY, _UITheme.DIM)
	outer.add_child(_waiting_label)

	_score_vbox = VBoxContainer.new()
	_score_vbox.add_theme_constant_override("separation", _UITheme.GAP)
	outer.add_child(_score_vbox)

func on_show_final_scores(ranking: Array) -> void:
	# Remove waiting label
	if _waiting_label != null:
		_waiting_label.queue_free()
		_waiting_label = null

	var medals: Array = ["#1", "#2", "#3", "#4", "#5", "#6", "#7", "#8"]

	for i in range(ranking.size()):
		var p: Dictionary = ranking[i]
		var medal: String = medals[i] if i < medals.size() else "#%d" % (i + 1)

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
			var set_str: String = ("  SET x%.1f" % b.get("multiplier", 1.0)) if completed else ""
			var line := Label.new()
			line.text = "  %s: %d items, §%d raw → §%d%s" % [
				cat.capitalize(), b.get("count", 0), b.get("raw", 0), b.get("scored", 0), set_str
			]
			_UITheme.style_label(line, _UITheme.FS_LABEL, _UITheme.cat_color(cat) if completed else _UITheme.DIM)
			_score_vbox.add_child(line)
