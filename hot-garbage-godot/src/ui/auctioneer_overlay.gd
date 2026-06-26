extends Control

const _UITheme = preload("res://src/scenes/ui_theme.gd")

var _value_label: Label
var _cat_label: Label

func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	custom_minimum_size = Vector2(0, 80)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	var style := _UITheme.make_panel(_UITheme.SURFACE, _UITheme.GOLD)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	_value_label = Label.new()
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(_value_label, _UITheme.FS_VALUE, _UITheme.GOLD)
	vbox.add_child(_value_label)

	_cat_label = Label.new()
	_cat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(_cat_label, _UITheme.FS_LABEL, _UITheme.DIM)
	vbox.add_child(_cat_label)

func show_reveal(artifact: Dictionary) -> void:
	_value_label.text = "TRUE VALUE: §%d" % artifact.get("value", 0)
	var cat: String = artifact.get("category", "")
	_cat_label.text = "CATEGORY: %s" % cat.to_upper()
	_cat_label.add_theme_color_override("font_color", _UITheme.cat_color(cat))
	visible = true

func hide_reveal() -> void:
	visible = false
