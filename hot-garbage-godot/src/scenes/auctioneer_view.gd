extends Control

const _UITheme = preload("res://src/scenes/ui_theme.gd")

var _hud: Control
var _role_label: Label
var _name_label: Label
var _cat_label: Label
var _flavor_label: Label
var _value_label: Label
var _countdown_label: Label
var _open_early_btn: Button
var _bid_status_label: Label
var _force_btn: Button

var _expected_bids: int = 0
var _received_bids: int = 0
var _pitch_seconds_left: float = 0.0
var _counting: bool = false

func _ready() -> void:
	_build_ui()
	_expected_bids = NetworkManager.get_peer_ids().size()

func _build_ui() -> void:
	_UITheme.add_bg(self)

	# HUD sidebar
	const HUDScript = preload("res://src/scenes/hud.gd")
	_hud = HUDScript.new()
	add_child(_hud)

	# Main content area — offset right of HUD
	var main := Control.new()
	main.set_anchors_preset(Control.PRESET_FULL_RECT)
	main.offset_left = _UITheme.HUD_WIDTH
	add_child(main)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(480, 480)
	vbox.add_theme_constant_override("separation", _UITheme.GAP)
	main.add_child(vbox)

	_role_label = Label.new()
	_role_label.text = "YOU ARE THE AUCTIONEER"
	_role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_section_label(_role_label)
	vbox.add_child(_role_label)

	_name_label = Label.new()
	_name_label.text = "..."
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

	_value_label = Label.new()
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(_value_label, _UITheme.FS_VALUE, _UITheme.GOLD)
	vbox.add_child(_value_label)

	_countdown_label = Label.new()
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UITheme.style_label(_countdown_label, _UITheme.FS_TIMER, _UITheme.TEXT)
	vbox.add_child(_countdown_label)

	_bid_status_label = Label.new()
	_bid_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bid_status_label.visible = false
	_UITheme.style_label(_bid_status_label, _UITheme.FS_BODY, _UITheme.DIM)
	vbox.add_child(_bid_status_label)

	_open_early_btn = Button.new()
	_open_early_btn.text = "OPEN EARLY"
	_open_early_btn.pressed.connect(_on_open_early_pressed)
	_UITheme.style_ghost_button(_open_early_btn)
	_open_early_btn.visible = false
	vbox.add_child(_open_early_btn)

	if NetworkManager.is_host():
		_force_btn = Button.new()
		_force_btn.text = "FORCE RESOLVE"
		_force_btn.pressed.connect(func(): GameServer.force_resolve())
		_UITheme.style_ghost_button(_force_btn)
		_force_btn.visible = false
		vbox.add_child(_force_btn)

func on_auctioneer_reveal(artifact: Dictionary, pitch_duration: int) -> void:
	_received_bids = 0
	_name_label.text = artifact.name
	var cat: String = artifact.get("category", "")
	_cat_label.text = cat.to_upper()
	_cat_label.add_theme_color_override("font_color", _UITheme.cat_color(cat))
	_flavor_label.text = '"%s"' % artifact.get("flavor", "")
	_value_label.text = "TRUE VALUE: §%d" % artifact.value

	_pitch_seconds_left = float(pitch_duration)
	_counting = true
	_countdown_label.visible = true
	_update_countdown_display()

	_open_early_btn.visible = true
	_open_early_btn.disabled = false
	_bid_status_label.visible = false

	if not NetworkManager.bid_received.is_connected(_on_bid_count_update):
		NetworkManager.bid_received.connect(_on_bid_count_update)

func on_open_bidding() -> void:
	_counting = false
	_countdown_label.text = "BIDDING OPEN"
	_open_early_btn.visible = false
	_bid_status_label.visible = true
	_bid_status_label.text = "Bids received: 0 / %d" % _expected_bids
	if _force_btn != null:
		_force_btn.visible = true

func _on_bid_count_update(_peer_id: int, _amount: int) -> void:
	_received_bids += 1
	_bid_status_label.text = "Bids received: %d / %d" % [_received_bids, _expected_bids]

func _on_open_early_pressed() -> void:
	_open_early_btn.disabled = true
	NetworkManager.send_open_early()

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
