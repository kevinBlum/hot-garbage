extends Control

const _UITheme = preload("res://src/scenes/ui_theme.gd")

var _item_label: Label
var _cash_label: Label
var _bid_input: SpinBox
var _submit_btn: Button
var _status_label: Label
var _countdown_label: Label

var _time_left: float = 0.0
var _counting: bool = false
var _submitted: bool = false

# The panel container that we slide in/out
var _panel: PanelContainer

func _ready() -> void:
	visible = false
	# Occupy the bottom strip
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	custom_minimum_size = Vector2(0, 200)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(600, 0)
	_UITheme.add_center_container(self).add_child(_panel)
	_panel.add_theme_stylebox_override("panel", _UITheme.make_panel())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", _UITheme.GAP)
	_panel.add_child(vbox)

	_item_label = Label.new()
	_item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(_item_label, _UITheme.FS_BODY, _UITheme.DIM)
	vbox.add_child(_item_label)

	_cash_label = Label.new()
	_cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(_cash_label, _UITheme.FS_LABEL, _UITheme.GOLD)
	vbox.add_child(_cash_label)

	var bid_row := HBoxContainer.new()
	bid_row.add_theme_constant_override("separation", _UITheme.GAP)
	bid_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(bid_row)

	var lbl := Label.new()
	lbl.text = "Your bid: §"
	_UITheme.style_label(lbl, _UITheme.FS_BODY, _UITheme.DIM)
	bid_row.add_child(lbl)

	_bid_input = SpinBox.new()
	_bid_input.min_value = 0
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
	_UITheme.style_label(_status_label, _UITheme.FS_LABEL, _UITheme.DIM)
	vbox.add_child(_status_label)

	_countdown_label = Label.new()
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(_countdown_label, _UITheme.FS_TIMER, _UITheme.TEXT)
	vbox.add_child(_countdown_label)

func open_for_bidding(artifact: Dictionary, bid_timeout: float, player_cash: int) -> void:
	var cat: String = artifact.get("category", "unknown")
	var display_cat: String = "UNKNOWN" if cat == "unknown" else cat.to_upper()
	_item_label.text = "%s  [%s]" % [artifact.get("name", ""), display_cat]
	_item_label.add_theme_color_override("font_color", _UITheme.cat_color(cat))
	_cash_label.text = "Your cash: §%d" % player_cash
	_bid_input.max_value = player_cash
	_bid_input.value = 0
	_bid_input.editable = true
	_submit_btn.disabled = false
	_status_label.text = ""
	_submitted = false
	_time_left = bid_timeout
	_counting = true

	# Slide in from bottom
	visible = true
	offset_top = get_viewport_rect().size.y
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "offset_top", 0.0, 0.3)

func close() -> void:
	_counting = false
	if not visible:
		return
	# Slide out to bottom
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "offset_top", get_viewport_rect().size.y, 0.25)
	tween.tween_callback(func(): visible = false)

func _on_submit_pressed() -> void:
	if _submitted:
		return
	_submitted = true
	_submit_btn.disabled = true
	_bid_input.editable = false
	_status_label.text = "Bid submitted. Waiting..."
	NetworkTransport.send_bid(int(_bid_input.value))

func _process(delta: float) -> void:
	if not _counting:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_time_left = 0.0
		_counting = false
		_countdown_label.text = "0"
		if not _submitted:
			_on_submit_pressed()  # auto-submit §0
		return
	var secs: int = int(ceil(_time_left))
	_countdown_label.text = "%d" % secs
