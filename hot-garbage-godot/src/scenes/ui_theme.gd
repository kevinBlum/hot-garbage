class_name UITheme
extends RefCounted

static var BG      := Color.html("111111")
static var SURFACE := Color.html("0d0d0d")
static var BORDER  := Color.html("222222")
static var TEXT    := Color.html("ffffff")
static var DIM     := Color.html("555555")
static var GOLD    := Color.html("C9A227")

static var CAT_COLORS: Dictionary = {
    "antiquities": Color.html("C9A227"),
    "curios":      Color.html("7B6CD9"),
    "relics":      Color.html("C04F4F"),
    "forgeries":   Color.html("3FA66A"),
    "junk":        Color.html("8A8A8A"),
}

const FS_LABEL    := 13
const FS_BODY     := 16
const FS_ARTIFACT := 24
const FS_VALUE    := 40
const FS_TIMER    := 48
const PAD         := 20
const GAP         := 12
const HUD_WIDTH   := 200

static var _mono: SystemFont

static func mono() -> SystemFont:
    if _mono == null:
        _mono = SystemFont.new()
        _mono.font_names = PackedStringArray(["Courier New", "Courier", "Liberation Mono"])
    return _mono

static func add_center_container(parent: Control) -> CenterContainer:
    var cc := CenterContainer.new()
    cc.set_anchors_preset(Control.PRESET_FULL_RECT)
    parent.add_child(cc)
    return cc

static func add_bg(node: Control) -> void:
    var bg := ColorRect.new()
    bg.color = BG
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    node.add_child(bg)
    node.move_child(bg, 0)

static func style_label(lbl: Label, size: int = FS_BODY, color: Color = TEXT) -> void:
    lbl.add_theme_font_override("font", mono())
    lbl.add_theme_font_size_override("font_size", size)
    lbl.add_theme_color_override("font_color", color)

static func style_section_label(lbl: Label) -> void:
    style_label(lbl, FS_LABEL, DIM)
    lbl.uppercase = true

static func make_panel(bg_color: Color = SURFACE, border_color: Color = BORDER) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = bg_color
    s.border_color = border_color
    s.border_width_left   = 1
    s.border_width_right  = 1
    s.border_width_top    = 1
    s.border_width_bottom = 1
    s.content_margin_left   = PAD
    s.content_margin_right  = PAD
    s.content_margin_top    = GAP
    s.content_margin_bottom = GAP
    return s

static func style_button(btn: Button, bg_color: Color = GOLD, fg_color: Color = BG) -> void:
    btn.add_theme_font_override("font", mono())
    btn.add_theme_font_size_override("font_size", FS_BODY)
    for state in ["normal", "hover", "pressed", "focus", "disabled"]:
        var s := StyleBoxFlat.new()
        s.bg_color = bg_color.lightened(0.1) if state == "hover" else bg_color
        if state == "disabled":
            s.bg_color = DIM
        btn.add_theme_stylebox_override(state, s)
    btn.add_theme_color_override("font_color", fg_color)
    btn.add_theme_color_override("font_hover_color", fg_color)
    btn.add_theme_color_override("font_pressed_color", fg_color)
    btn.add_theme_color_override("font_disabled_color", BG)

static func style_ghost_button(btn: Button) -> void:
    btn.add_theme_font_override("font", mono())
    btn.add_theme_font_size_override("font_size", FS_BODY)
    for state in ["normal", "hover", "pressed", "focus", "disabled"]:
        var s := StyleBoxFlat.new()
        s.bg_color = SURFACE
        s.border_color = DIM if state != "normal" else BORDER
        s.border_width_left   = 1
        s.border_width_right  = 1
        s.border_width_top    = 1
        s.border_width_bottom = 1
        btn.add_theme_stylebox_override(state, s)
    btn.add_theme_color_override("font_color", DIM)
    btn.add_theme_color_override("font_hover_color", TEXT)
    btn.add_theme_color_override("font_disabled_color", BORDER)

static func style_line_edit(le: LineEdit) -> void:
    le.add_theme_font_override("font", mono())
    le.add_theme_font_size_override("font_size", FS_BODY)
    le.add_theme_color_override("font_color", TEXT)
    le.add_theme_color_override("font_placeholder_color", DIM)
    le.add_theme_color_override("caret_color", GOLD)
    var s := StyleBoxFlat.new()
    s.bg_color = SURFACE
    s.border_color = BORDER
    s.border_width_left   = 1
    s.border_width_right  = 1
    s.border_width_top    = 1
    s.border_width_bottom = 1
    s.content_margin_left   = GAP
    s.content_margin_right  = GAP
    s.content_margin_top    = GAP
    s.content_margin_bottom = GAP
    le.add_theme_stylebox_override("normal", s)
    le.add_theme_stylebox_override("focus", s)
    le.add_theme_stylebox_override("read_only", s)

static func make_card() -> PanelContainer:
    var card := PanelContainer.new()
    card.size_flags_vertical   = Control.SIZE_EXPAND_FILL
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    card.add_theme_stylebox_override("panel", make_panel())
    return card

static func make_content_hbox(parent: Control) -> HBoxContainer:
    var hbox := HBoxContainer.new()
    hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
    hbox.offset_left   =  PAD
    hbox.offset_top    =  PAD
    hbox.offset_right  = -PAD
    hbox.offset_bottom = -PAD
    hbox.add_theme_constant_override("separation", GAP)
    parent.add_child(hbox)
    return hbox

static func style_vseparator(sep: VSeparator) -> void:
    var s := StyleBoxFlat.new()
    s.bg_color = BORDER
    sep.add_theme_stylebox_override("separator", s)
    sep.custom_minimum_size = Vector2(1, 0)

static func cat_color(category: String) -> Color:
    return CAT_COLORS.get(category.to_lower(), DIM)
