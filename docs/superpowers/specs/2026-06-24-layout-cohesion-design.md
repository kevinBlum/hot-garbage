# Layout Cohesion Design

## Goal

Replace floating-island VBoxes with layouts that fill the 1920×1080 canvas effectively. Two layout patterns: a split panel for the main menu, and a three-zone layout for the two primary in-game scenes. Secondary scenes (bid_reveal, final_scores) get a simple width bump.

---

## Main Menu — Split Panel

Replace the centered 640×480 VBoxContainer with an HBoxContainer two-panel split (~960px total, centered).

**Left panel (~50%):** game branding
- Title: "HOT GARBAGE" — `FS_ARTIFACT`, GOLD, centered
- Tagline: "a game of bluffing, bidding, and bad provenance" — `FS_LABEL`, DIM, centered
- Flavor bullets: "2–6 players", "~45 min" — `FS_LABEL`, DIM, centered

**Right panel (~50%):** connection form
- Section label "PLAYER NAME" → name LineEdit
- Section label "HOST IP" → IP LineEdit (placeholder "leave blank to host")
- HOST GAME button (`style_button`)
- JOIN GAME button (`style_ghost_button`)
- Status label — `FS_BODY`, DIM, centered

**Structure:**
```
HBoxContainer (custom_minimum_size = Vector2(960, 520), PRESET_CENTER, separation = GAP)
├── VBoxContainer left (size_flags_horizontal = SIZE_EXPAND_FILL, separation = GAP * 2)
└── VBoxContainer right (size_flags_horizontal = SIZE_EXPAND_FILL, separation = GAP)
```

A `VSeparator` between the two columns uses `style_line()` (DIM color, 1px). Add `static func style_vseparator(sep: VSeparator)` to UITheme.

---

## In-Game Scenes — Three-Zone Layout

Applies to: `auctioneer_view.gd` and `bidder_view.gd`.

Replace the centered 480×480 VBox with a full-rect HBoxContainer split:

```
[HUD 200px] | [left column 62.5%] | [right column 37.5%]
               ├── artifact card (fills half the height)
               └── action card   (fills half the height)
```

### Container hierarchy

```
scene (extends Control)
├── background ColorRect
├── HUD (offset_right = HUD_WIDTH, pinned left)
└── main Control (PRESET_FULL_RECT, offset_left = HUD_WIDTH)
    └── HBoxContainer (PRESET_FULL_RECT, PAD insets all sides, separation = GAP)
        ├── left_col VBoxContainer (SIZE_EXPAND_FILL, stretch_ratio = 2.5, separation = GAP)
        │   ├── artifact_card PanelContainer (SIZE_EXPAND_FILL vertically)
        │   │   └── CenterContainer
        │   │       └── VBoxContainer (separation = GAP)  ← artifact labels here
        │   └── action_card PanelContainer (SIZE_EXPAND_FILL vertically)
        │       └── CenterContainer
        │           └── VBoxContainer (separation = GAP)  ← timer/bid controls here
        └── right_col VBoxContainer (SIZE_EXPAND_FILL, stretch_ratio = 1.0)
            └── player_card PanelContainer (SIZE_EXPAND_FILL vertically)
                └── VBoxContainer (PAD margins, separation = GAP)  ← player list here
```

`PanelContainer` uses `_UITheme.make_panel()` StyleBox via `add_theme_stylebox_override("panel", ...)`.

The insets on the root HBoxContainer: `offset_left = PAD`, `offset_top = PAD`, `offset_right = -PAD`, `offset_bottom = -PAD`.

### UITheme additions

Add two static helpers to `ui_theme.gd`:

```gdscript
# Returns a PanelContainer sized to expand and fill, with the standard border+bg StyleBox.
static func make_card() -> PanelContainer:
    var card := PanelContainer.new()
    card.size_flags_vertical  = Control.SIZE_EXPAND_FILL
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    card.add_theme_stylebox_override("panel", make_panel())
    return card

# Creates an HBoxContainer filling `parent` with PAD insets and GAP separation, adds and returns it.
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
```

### Auctioneer artifact card content (all labels centered horizontally)

1. Section label: `"LOT #N OF M · AUCTIONEER"` — `style_section_label()`
2. `_name_label` — `FS_ARTIFACT`, TEXT, autowrap
3. `_cat_label` — `FS_LABEL`, `cat_color(category)`
4. `_value_label` — `FS_VALUE`, GOLD (e.g. `"TRUE VALUE: §420"`)
5. `_flavor_label` — `FS_BODY`, DIM, autowrap

### Auctioneer action card content (centered)

1. `_countdown_label` — `FS_TIMER`, TEXT (shows `"M:SS"` during pitch, `"BIDDING OPEN"` after)
2. `_bid_status_label` — `FS_BODY`, DIM (hidden during pitch)
3. HBoxContainer row: `_open_early_btn` + optional `_force_btn` (host only)

### Bidder artifact card content (centered; same as auctioneer minus true value)

1. `_header_label` — `style_section_label()` (e.g. `"PITCH PHASE"`)
2. `_name_label` — `FS_ARTIFACT`, TEXT, autowrap
3. `_cat_label` — `FS_LABEL`, `cat_color(category)`
4. `_flavor_label` — `FS_BODY`, DIM, autowrap

### Bidder action card content (centered)

1. `_phase_label` — `style_section_label()` (`"BIDDING OPENS IN"` / `"BIDDING IS OPEN"`)
2. `_countdown_label` — `FS_TIMER`, TEXT
3. `_bid_area` Control (`modulate.a = 0.4` during pitch, `1.0` when open):
   - HBoxContainer row: bid label + SpinBox + SUBMIT button (same as today)

### Player panel (both views)

Member var: `_player_vbox: VBoxContainer`
Method: `_refresh_players()` — called in `_build_ui()` and at start of each auction.

For each `peer_id` in `NetworkManager.player_names`:
- Row: name label + cash label (right-aligned)
- Name: TEXT normally, GOLD if `peer_id == multiplayer.get_unique_id()`
- Cash: from `GameServer.player_cash.get(name, -1)`; show `"§N"` if known, `"—"` if not

Structure: `_player_vbox` is a VBoxContainer inside the player_card's inner VBox, below a `"PLAYERS"` section label.

---

## Secondary Scenes — Wider Centered (bid_reveal, final_scores)

No layout structure changes — just widen the existing minimum size:

- `bid_reveal.gd`: `vbox.custom_minimum_size = Vector2(960, 300)` (was 480×300)
- `final_scores.gd`: already uses a ScrollContainer+outer VBox, not a fixed-size VBox — add `outer.custom_minimum_size = Vector2(960, 0)` to constrain width

---

## Global Constraints

- UITheme constants (`FS_*`, `PAD`, `GAP`, `HUD_WIDTH`) must be used throughout — no hardcoded px values
- `artifact.value` must never appear in broadcast/public context
- `engine.js` and `scoring.js` stay I/O-free (these are Godot-only changes)
- All labels styled via `style_label()` or `style_section_label()` — no inline font/color overrides
- `make_panel()` SURFACE+BORDER colors used for all card backgrounds — no new colors

## Files

- `hot-garbage-godot/src/scenes/ui_theme.gd` — add `make_card()`, `make_content_hbox()`, `style_vseparator()`
- `hot-garbage-godot/src/scenes/main_menu.gd` — split panel
- `hot-garbage-godot/src/scenes/auctioneer_view.gd` — three-zone layout
- `hot-garbage-godot/src/scenes/bidder_view.gd` — three-zone layout
- `hot-garbage-godot/src/scenes/bid_reveal.gd` — widen to 960px
- `hot-garbage-godot/src/scenes/final_scores.gd` — widen outer VBox to 960px min
