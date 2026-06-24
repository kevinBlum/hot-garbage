extends Control

const _UITheme = preload("res://src/scenes/ui_theme.gd")

var _cash_label: Label
var _collection_vbox: VBoxContainer
var _total_label: Label

func _ready() -> void:
    add_to_group("hud_nodes")
    # Fixed 130px left strip, full height
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

    var spacer := Control.new()
    spacer.custom_minimum_size = Vector2(0, _UITheme.GAP)
    vbox.add_child(spacer)

    var col_lbl := Label.new()
    col_lbl.text = "COLLECTION"
    _UITheme.style_section_label(col_lbl)
    vbox.add_child(col_lbl)

    _collection_vbox = VBoxContainer.new()
    _collection_vbox.add_theme_constant_override("separation", 4)
    vbox.add_child(_collection_vbox)

    _total_label = Label.new()
    _UITheme.style_label(_total_label, _UITheme.FS_LABEL, _UITheme.DIM)
    vbox.add_child(_total_label)

    refresh()

func refresh() -> void:
    var own_id: String = NetworkManager.player_names.get(multiplayer.get_unique_id(), "")

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
        var count: int = by_cat[cat]
        row.text = "■ %s ×%d" % [cat.capitalize(), count]
        _UITheme.style_label(row, _UITheme.FS_LABEL, _UITheme.cat_color(cat))
        row.autowrap_mode = TextServer.AUTOWRAP_OFF
        _collection_vbox.add_child(row)

    _total_label.text = "%d artifact%s" % [artifacts.size(), "s" if artifacts.size() != 1 else ""]
