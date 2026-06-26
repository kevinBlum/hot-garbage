extends Control

const _UITheme = preload("res://src/scenes/ui_theme.gd")

var _fade_timer: float = 0.0
var _fading: bool = false

func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_assigned(role: Dictionary, objective: Dictionary) -> void:
	for child in get_children():
		child.queue_free()

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 220)
	_UITheme.add_center_container(self).add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   _UITheme.PAD * 2)
	margin.add_theme_constant_override("margin_right",  _UITheme.PAD * 2)
	margin.add_theme_constant_override("margin_top",    _UITheme.PAD * 2)
	margin.add_theme_constant_override("margin_bottom", _UITheme.PAD * 2)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", _UITheme.GAP)
	margin.add_child(vbox)

	var role_lbl := Label.new()
	role_lbl.text = "YOUR ROLE: %s" % role.get("name", "UNKNOWN")
	_UITheme.style_label(role_lbl, _UITheme.FS_ARTIFACT, _UITheme.GOLD)
	role_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(role_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = role.get("description", "")
	_UITheme.style_label(desc_lbl, _UITheme.FS_BODY, _UITheme.TEXT)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_lbl)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var obj_lbl := Label.new()
	obj_lbl.text = "OBJECTIVE: Acquire \"%s\" — §%d bonus" % [
		objective.get("itemName", "?"), objective.get("bonus", 0)]
	_UITheme.style_label(obj_lbl, _UITheme.FS_LABEL, _UITheme.DIM)
	obj_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	obj_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(obj_lbl)

	visible = true
	modulate.a = 1.0
	_fading = false
	_fade_timer = 0.0

func _start_fade() -> void:
	_fading = true
	_fade_timer = 1.5

func _process(delta: float) -> void:
	if not _fading:
		return
	_fade_timer -= delta
	if _fade_timer <= 0.0:
		visible = false
		_fading = false
		return
	modulate.a = clampf(_fade_timer / 1.5, 0.0, 1.0)
