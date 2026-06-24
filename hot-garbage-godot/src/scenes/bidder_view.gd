extends Control

const _UITheme = preload("res://src/scenes/ui_theme.gd")

var _hud: Control
var _header_label: Label
var _name_label: Label
var _cat_label: Label
var _flavor_label: Label
var _phase_label: Label
var _countdown_label: Label
var _bid_input: SpinBox
var _submit_btn: Button
var _status_label: Label
var _bid_area: Control

var _pitch_seconds_left: float = 0.0
var _counting: bool = false

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
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(480, 480)
	vbox.add_theme_constant_override("separation", _UITheme.GAP)
	main.add_child(vbox)

	_header_label = Label.new()
	_header_label.text = "WAITING FOR AUCTION..."
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_section_label(_header_label)
	vbox.add_child(_header_label)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_UITheme.style_label(_name_label, _UITheme.FS_ARTIFACT, _UITheme.TEXT)
	vbox.add_child(_name_label)

	_cat_label = Label.new()
	_cat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(_cat_label, _UITheme.FS_LABEL, _UITheme.DIM)
	vbox.add_child(_cat_label)

	_flavor_label = Label.new()
	_flavor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flavor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_UITheme.style_label(_flavor_label, _UITheme.FS_BODY, _UITheme.DIM)
	vbox.add_child(_flavor_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, _UITheme.GAP)
	vbox.add_child(spacer)

	_phase_label = Label.new()
	_phase_label.text = "BIDDING OPENS IN"
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_section_label(_phase_label)
	vbox.add_child(_phase_label)

	_countdown_label = Label.new()
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(_countdown_label, _UITheme.FS_TIMER, _UITheme.TEXT)
	vbox.add_child(_countdown_label)

	# Bid area (shown dimmed during pitch, enabled when bidding opens)
	_bid_area = Control.new()
	_bid_area.custom_minimum_size = Vector2(0, 60)
	_bid_area.modulate.a = 0.35
	vbox.add_child(_bid_area)

	var bid_row := HBoxContainer.new()
	bid_row.set_anchors_preset(Control.PRESET_CENTER)
	bid_row.add_theme_constant_override("separation", _UITheme.GAP)
	_bid_area.add_child(bid_row)

	var bid_lbl := Label.new()
	bid_lbl.text = "Your bid: §"
	_UITheme.style_label(bid_lbl, _UITheme.FS_BODY, _UITheme.DIM)
	bid_row.add_child(bid_lbl)

	_bid_input = SpinBox.new()
	_bid_input.min_value = 0
	_bid_input.max_value = 99999
	_bid_input.step = 1
	_bid_input.editable = false
	_bid_input.add_theme_font_override("font", _UITheme.mono())
	_UITheme.style_line_edit(_bid_input.get_line_edit())
	bid_row.add_child(_bid_input)

	_submit_btn = Button.new()
	_submit_btn.text = "SUBMIT BID"
	_submit_btn.disabled = true
	_submit_btn.pressed.connect(_on_submit_pressed)
	_UITheme.style_button(_submit_btn)
	bid_row.add_child(_submit_btn)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(_status_label, _UITheme.FS_BODY, _UITheme.DIM)
	vbox.add_child(_status_label)

func on_start_pitch(artifact: Dictionary, pitch_duration: int) -> void:
	var auctioneer_name: String = ""
	# The auctioneer is tracked by GameServer; infer from player order via NetworkManager
	# Fallback: show generic header
	_header_label.text = "PITCH PHASE"
	_name_label.text = artifact.get("name", "")
	var cat: String = artifact.get("category", "")
	_cat_label.text = cat.to_upper()
	_cat_label.add_theme_color_override("font_color", _UITheme.cat_color(cat))
	_flavor_label.text = '"%s"' % artifact.get("flavor", "")

	_phase_label.text = "BIDDING OPENS IN"
	_pitch_seconds_left = float(pitch_duration)
	_counting = true
	_update_countdown_display()

	# Reset bid area to locked state
	_bid_area.modulate.a = 0.35
	_bid_input.editable = false
	_bid_input.value = 0
	_submit_btn.disabled = true
	_status_label.text = ""

func on_open_bidding() -> void:
	_counting = false
	_phase_label.text = "BIDDING IS OPEN"
	_countdown_label.text = ""
	_bid_area.modulate.a = 1.0
	_bid_input.editable = true
	_submit_btn.disabled = false

func _on_submit_pressed() -> void:
	_submit_btn.disabled = true
	_bid_input.editable = false
	_status_label.text = "Bid submitted. Waiting for others..."
	NetworkManager.submit_bid(int(_bid_input.value))

func _process(delta: float) -> void:
	if not _counting:
		return
	_pitch_seconds_left -= delta
	if _pitch_seconds_left < 0.0:
		_pitch_seconds_left = 0.0
		_counting = false
	_update_countdown_display()

func _update_countdown_display() -> void:
	var secs: int = int(ceil(_pitch_seconds_left))
	var mins: int = secs / 60
	var s: int = secs % 60
	_countdown_label.text = "%d:%02d" % [mins, s]
