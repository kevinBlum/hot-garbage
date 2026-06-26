extends Control

const _UITheme = preload("res://src/scenes/ui_theme.gd")

var _cash_label: Label
var _round_label: Label
var _collection_vbox: VBoxContainer
var _countdown_label: Label

func _ready() -> void:
	add_to_group("hud_nodes")
	# Fixed left strip, full height
	anchor_left   = 0.0
	anchor_top    = 0.0
	anchor_right  = 0.0
	anchor_bottom = 1.0
	offset_left   = 0.0
	offset_top    = 0.0
	offset_right  = _UITheme.HUD_WIDTH
	offset_bottom = 0.0

	var bg := ColorRect.new()
	bg.color = _UITheme.SURFACE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var sep := ColorRect.new()
	sep.color = _UITheme.BORDER
	sep.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	sep.custom_minimum_size = Vector2(1, 0)
	add_child(sep)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   = _UITheme.PAD
	vbox.offset_top    = _UITheme.PAD
	vbox.offset_right  = -_UITheme.PAD
	vbox.offset_bottom = -_UITheme.PAD
	vbox.add_theme_constant_override("separation", _UITheme.GAP)
	add_child(vbox)

	var you_lbl := Label.new()
	you_lbl.text = "YOU"
	_UITheme.style_section_label(you_lbl)
	vbox.add_child(you_lbl)

	_cash_label = Label.new()
	_cash_label.text = "§—"
	_UITheme.style_label(_cash_label, _UITheme.FS_ARTIFACT, _UITheme.GOLD)
	_cash_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	vbox.add_child(_cash_label)

	_round_label = Label.new()
	_round_label.text = ""
	_UITheme.style_label(_round_label, _UITheme.FS_LABEL, _UITheme.DIM)
	vbox.add_child(_round_label)

	var col_lbl := Label.new()
	col_lbl.text = "COLLECTION"
	_UITheme.style_section_label(col_lbl)
	vbox.add_child(col_lbl)

	_collection_vbox = VBoxContainer.new()
	_collection_vbox.add_theme_constant_override("separation", 4)
	vbox.add_child(_collection_vbox)

	# Spacer to push countdown to bottom
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var bid_section := Label.new()
	bid_section.text = "BID TIMER"
	_UITheme.style_section_label(bid_section)
	vbox.add_child(bid_section)

	_countdown_label = Label.new()
	_countdown_label.text = ""
	_UITheme.style_label(_countdown_label, _UITheme.FS_ARTIFACT, _UITheme.GOLD)
	_countdown_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_countdown_label.visible = false
	vbox.add_child(_countdown_label)

	refresh()

func refresh() -> void:
	var own_id: String = NetworkManager.local_name
	var cash: int = GameServer.player_cash.get(own_id, 0)
	_cash_label.text = "§%d" % cash

	for child in _collection_vbox.get_children():
		child.queue_free()

	var artifacts: Array = GameServer.player_artifacts.get(own_id, [])
	var by_cat: Dictionary = {}
	for a in artifacts:
		var cat: String = a.get("category", "")
		by_cat[cat] = by_cat.get(cat, 0) + 1

	for cat in by_cat:
		var row := Label.new()
		row.text = "■ %s ×%d" % [cat.capitalize(), by_cat[cat]]
		_UITheme.style_label(row, _UITheme.FS_LABEL, _UITheme.cat_color(cat))
		row.autowrap_mode = TextServer.AUTOWRAP_OFF
		_collection_vbox.add_child(row)

func set_round(round: int, total: int) -> void:
	_round_label.text = "ROUND %d / %d" % [round, total]

func update_cash(amount: int) -> void:
	_cash_label.text = "§%d" % amount

func update_round(round: int, total: int) -> void:
	set_round(round, total)

func update_collection(artifacts: Array) -> void:
	for child in _collection_vbox.get_children():
		child.queue_free()

	var by_cat: Dictionary = {}
	for a in artifacts:
		var cat: String = a.get("category", "")
		by_cat[cat] = by_cat.get(cat, 0) + 1

	for cat in by_cat:
		var row := Label.new()
		row.text = "■ %s ×%d" % [cat.capitalize(), by_cat[cat]]
		_UITheme.style_label(row, _UITheme.FS_LABEL, _UITheme.cat_color(cat))
		row.autowrap_mode = TextServer.AUTOWRAP_OFF
		_collection_vbox.add_child(row)

func start_bid_countdown(seconds: float) -> void:
	_countdown_label.visible = true
	_countdown_label.text = "%d" % int(ceil(seconds))

func stop_bid_countdown() -> void:
	_countdown_label.visible = false
	_countdown_label.text = ""
