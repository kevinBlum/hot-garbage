extends Control

const _UITheme = preload("res://src/scenes/ui_theme.gd")

var _header: Label
var _result_label: Label

func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	modulate.a = 0.0

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(700, 200)
	vbox.add_theme_constant_override("separation", _UITheme.GAP * 2)
	_UITheme.add_center_container(self).add_child(vbox)

	_header = Label.new()
	_header.text = "SOLD"
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(_header, 64, _UITheme.GOLD)
	vbox.add_child(_header)

	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_UITheme.style_label(_result_label, _UITheme.FS_ARTIFACT, _UITheme.TEXT)
	vbox.add_child(_result_label)

func show_result(result: Dictionary) -> void:
	if result.get("winner", "") == "BANK":
		_header.text = "NO SALE"
		_result_label.text = "No takers.\nBank paid §%d." % result.get("price", 0)
	else:
		_header.text = "SOLD"
		_result_label.text = "%s\nwon for §%d!" % [result.get("winner", ""), result.get("price", 0)]
	visible = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.3)
	tw.tween_interval(2.5)
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func(): visible = false)
	AudioManager.play_resolve()
