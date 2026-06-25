extends Control

const _UITheme = preload("res://src/scenes/ui_theme.gd")

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	_UITheme.add_bg(self)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(640, 600)
	vbox.add_theme_constant_override("separation", _UITheme.GAP * 2)
	_UITheme.add_center_container(self).add_child(vbox)

	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(title, _UITheme.FS_ARTIFACT, _UITheme.GOLD)
	vbox.add_child(title)

	var audio_lbl := Label.new()
	audio_lbl.text = "AUDIO"
	_UITheme.style_section_label(audio_lbl)
	vbox.add_child(audio_lbl)

	vbox.add_child(_make_slider_row("MASTER", AudioManager.master_volume,
		func(v: float):
			AudioManager.master_volume = v
			AudioManager.apply_volumes()
			AudioManager.save_settings()))

	vbox.add_child(_make_slider_row("SOUND EFFECTS", AudioManager.sfx_volume,
		func(v: float):
			AudioManager.sfx_volume = v
			AudioManager.apply_volumes()
			AudioManager.save_settings()))

	vbox.add_child(_make_slider_row("MUSIC", AudioManager.music_volume,
		func(v: float):
			AudioManager.music_volume = v
			AudioManager.apply_volumes()
			AudioManager.save_settings()))

	var display_lbl := Label.new()
	display_lbl.text = "DISPLAY"
	_UITheme.style_section_label(display_lbl)
	vbox.add_child(display_lbl)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", _UITheme.GAP)
	vbox.add_child(mode_row)

	var is_fullscreen: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

	var windowed_btn := Button.new()
	windowed_btn.text = "WINDOWED"
	windowed_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not is_fullscreen:
		_UITheme.style_button(windowed_btn)
	else:
		_UITheme.style_ghost_button(windowed_btn)
	mode_row.add_child(windowed_btn)

	var fullscreen_btn := Button.new()
	fullscreen_btn.text = "FULLSCREEN"
	fullscreen_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_fullscreen:
		_UITheme.style_button(fullscreen_btn)
	else:
		_UITheme.style_ghost_button(fullscreen_btn)
	mode_row.add_child(fullscreen_btn)

	windowed_btn.pressed.connect(func():
		AudioManager.play_ui()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_UITheme.style_button(windowed_btn)
		_UITheme.style_ghost_button(fullscreen_btn))

	fullscreen_btn.pressed.connect(func():
		AudioManager.play_ui()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_UITheme.style_button(fullscreen_btn)
		_UITheme.style_ghost_button(windowed_btn))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, _UITheme.GAP)
	vbox.add_child(spacer)

	var back_btn := Button.new()
	back_btn.text = "BACK"
	back_btn.pressed.connect(_on_back_pressed)
	_UITheme.style_ghost_button(back_btn)
	vbox.add_child(back_btn)

func _on_back_pressed() -> void:
	AudioManager.play_ui()
	get_tree().change_scene_to_file("res://src/scenes/main_menu.tscn")

func _make_slider_row(label_text: String, initial: float, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _UITheme.GAP)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(200, 0)
	_UITheme.style_label(lbl, _UITheme.FS_BODY, _UITheme.DIM)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(on_change)
	row.add_child(slider)
	return row
