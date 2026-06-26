extends Control

const _UITheme = preload("res://src/scenes/ui_theme.gd")

var _text_label: Label

func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	custom_minimum_size = Vector2(320, 200)
	offset_left = -340
	offset_right = 0

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _UITheme.make_panel(_UITheme.SURFACE, _UITheme.GOLD))
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", _UITheme.GAP)
	panel.add_child(vbox)

	var header := Label.new()
	header.text = "CHAOS!"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(header, _UITheme.FS_ARTIFACT, _UITheme.GOLD)
	vbox.add_child(header)

	_text_label = Label.new()
	_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_UITheme.style_label(_text_label, _UITheme.FS_BODY, _UITheme.TEXT)
	vbox.add_child(_text_label)

func show_chaos(chaos: Dictionary) -> void:
	var kind: String = chaos.get("type", "")
	var text: String = chaos.get("text", "")
	if kind == "appraiser":
		_text_label.text = "APPRAISER:\n%s" % text
	else:
		_text_label.text = "EVENT:\n%s" % text
		var extra: Dictionary = chaos.get("extra", {})
		if extra.has("victim") and extra.has("lostName"):
			_text_label.text += "\n%s loses \"%s\"!" % [extra.victim, extra.lostName]

	visible = true
	position.x = 340  # start off-screen right
	var tw := create_tween()
	tw.tween_property(self, "position:x", 0.0, 0.3)
	tw.tween_interval(3.5)
	tw.tween_property(self, "position:x", 340.0, 0.3)
	tw.tween_callback(func(): visible = false)
