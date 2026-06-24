# Layout Cohesion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace floating-island VBoxes with layouts that fill the 1920×1080 canvas — split panel for main menu, three-zone layout for in-game scenes.

**Architecture:** UITheme gains two layout helpers used by all scenes. Main menu switches to an HBoxContainer split. Auctioneer and bidder views rebuild around a full-rect HBoxContainer with artifact+action cards stacked left and a player panel right. Bid reveal and final scores get a simple width increase.

**Tech Stack:** Godot 4.3, GDScript, programmatic UI (no scene editor)

## Global Constraints

- UITheme constants (`FS_*`, `PAD`, `GAP`, `HUD_WIDTH`) used everywhere — no hardcoded pixel values
- All labels styled via `_UITheme.style_label()` or `_UITheme.style_section_label()`
- `artifact.value` must never appear in broadcast/RPC context
- `engine.js` and `scoring.js` must stay I/O-free (Godot-only changes)
- Card backgrounds use `_UITheme.make_panel()` StyleBox — no new colors
- `class_name` cross-file references use `preload()` — autoloads (GameServer, NetworkManager, AudioManager) accessed by name

---

### Task 1: UITheme layout helpers + VSeparator style

**Files:**
- Modify: `hot-garbage-godot/src/scenes/ui_theme.gd`

**Interfaces:**
- Produces:
  - `UITheme.make_card() -> PanelContainer` — PanelContainer with SIZE_EXPAND_FILL in both axes and `make_panel()` StyleBox applied
  - `UITheme.make_content_hbox(parent: Control) -> HBoxContainer` — HBoxContainer with PRESET_FULL_RECT, PAD insets all sides, GAP separation, added to parent
  - `UITheme.style_vseparator(sep: VSeparator) -> void` — styles a VSeparator with BORDER color, 1px wide

- [ ] **Step 1: Add the three helpers to `ui_theme.gd`**

  Append after `style_line_edit()`:

  ```gdscript
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
  ```

- [ ] **Step 2: Verify no syntax errors**

  Run: `godot --headless --quit --path hot-garbage-godot 2>&1 | grep -i error | head -20`

  Expected: no GDScript parse errors mentioning `ui_theme.gd`

- [ ] **Step 3: Commit**

  ```bash
  git add hot-garbage-godot/src/scenes/ui_theme.gd
  git commit -m "feat: UITheme layout helpers — make_card, make_content_hbox, style_vseparator"
  ```

---

### Task 2: main_menu.gd — split panel

**Files:**
- Modify: `hot-garbage-godot/src/scenes/main_menu.gd`

**Interfaces:**
- Consumes: `UITheme.style_vseparator()` from Task 1
- Produces: no new public API (internal layout change only)

- [ ] **Step 1: Rewrite `_build_ui()` in `main_menu.gd`**

  Replace the existing `_build_ui()` body (keep the function signature and all signal-handler methods unchanged). New `_build_ui()`:

  ```gdscript
  func _build_ui() -> void:
      _UITheme.add_bg(self)

      var hbox := HBoxContainer.new()
      hbox.set_anchors_preset(Control.PRESET_CENTER)
      hbox.custom_minimum_size = Vector2(960, 520)
      hbox.add_theme_constant_override("separation", 0)
      add_child(hbox)

      # --- Left panel: branding ---
      var left := VBoxContainer.new()
      left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
      left.add_theme_constant_override("separation", _UITheme.GAP * 2)
      left.alignment = BoxContainer.ALIGNMENT_CENTER
      hbox.add_child(left)

      var title := Label.new()
      title.text = "HOT GARBAGE"
      title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _UITheme.style_label(title, _UITheme.FS_ARTIFACT, _UITheme.GOLD)
      left.add_child(title)

      var tagline := Label.new()
      tagline.text = "a game of bluffing, bidding,\nand bad provenance"
      tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _UITheme.style_label(tagline, _UITheme.FS_LABEL, _UITheme.DIM)
      left.add_child(tagline)

      var meta := Label.new()
      meta.text = "2–6 players · ~45 min"
      meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _UITheme.style_label(meta, _UITheme.FS_LABEL, _UITheme.DIM)
      left.add_child(meta)

      # --- Separator ---
      var sep := VSeparator.new()
      _UITheme.style_vseparator(sep)
      hbox.add_child(sep)

      # --- Right panel: form ---
      var right := VBoxContainer.new()
      right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
      right.add_theme_constant_override("separation", _UITheme.GAP)
      right.alignment = BoxContainer.ALIGNMENT_CENTER
      hbox.add_child(right)

      var name_lbl := Label.new()
      name_lbl.text = "PLAYER NAME"
      _UITheme.style_section_label(name_lbl)
      right.add_child(name_lbl)

      _name_field = LineEdit.new()
      _name_field.placeholder_text = "Your name"
      _UITheme.style_line_edit(_name_field)
      right.add_child(_name_field)

      var ip_lbl := Label.new()
      ip_lbl.text = "HOST IP"
      _UITheme.style_section_label(ip_lbl)
      right.add_child(ip_lbl)

      _ip_field = LineEdit.new()
      _ip_field.placeholder_text = "Leave blank to host"
      _UITheme.style_line_edit(_ip_field)
      right.add_child(_ip_field)

      var spacer := Control.new()
      spacer.custom_minimum_size = Vector2(0, _UITheme.GAP)
      right.add_child(spacer)

      var host_btn := Button.new()
      host_btn.text = "HOST GAME"
      host_btn.pressed.connect(_on_host_pressed)
      _UITheme.style_button(host_btn)
      right.add_child(host_btn)

      var join_btn := Button.new()
      join_btn.text = "JOIN GAME"
      join_btn.pressed.connect(_on_join_pressed)
      _UITheme.style_ghost_button(join_btn)
      right.add_child(join_btn)

      _status_label = Label.new()
      _status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _UITheme.style_label(_status_label, _UITheme.FS_BODY, _UITheme.DIM)
      right.add_child(_status_label)
  ```

- [ ] **Step 2: Verify no syntax errors**

  Run: `godot --headless --quit --path hot-garbage-godot 2>&1 | grep -i error | head -20`

  Expected: no errors in `main_menu.gd`

- [ ] **Step 3: Commit**

  ```bash
  git add hot-garbage-godot/src/scenes/main_menu.gd
  git commit -m "feat: main menu split panel — branding left, form right"
  ```

---

### Task 3: auctioneer_view.gd — three-zone layout

**Files:**
- Modify: `hot-garbage-godot/src/scenes/auctioneer_view.gd`

**Interfaces:**
- Consumes: `UITheme.make_card()`, `UITheme.make_content_hbox()` from Task 1
- Produces:
  - New member: `_player_vbox: VBoxContainer`
  - New method: `_refresh_players() -> void`
  - Existing public API unchanged: `on_auctioneer_reveal(artifact, pitch_duration)`, `on_open_bidding()`

The existing member vars `_role_label`, `_name_label`, `_cat_label`, `_flavor_label`, `_value_label`, `_countdown_label`, `_open_early_btn`, `_bid_status_label`, `_force_btn`, `_expected_bids`, `_received_bids`, `_pitch_seconds_left`, `_counting` all stay. Add `_player_vbox: VBoxContainer` at the top.

- [ ] **Step 1: Add `_player_vbox` member var**

  After line `var _counting: bool = false` add:
  ```gdscript
  var _player_vbox: VBoxContainer
  ```

- [ ] **Step 2: Rewrite `_build_ui()`**

  Replace the entire `_build_ui()` body:

  ```gdscript
  func _build_ui() -> void:
      _UITheme.add_bg(self)

      const HUDScript = preload("res://src/scenes/hud.gd")
      _hud = HUDScript.new()
      add_child(_hud)

      var main := Control.new()
      main.set_anchors_preset(Control.PRESET_FULL_RECT)
      main.offset_left = _UITheme.HUD_WIDTH
      add_child(main)

      var hbox := _UITheme.make_content_hbox(main)

      # Left column (artifact + action stacked)
      var left_col := VBoxContainer.new()
      left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
      left_col.size_flags_stretch_ratio = 2.5
      left_col.add_theme_constant_override("separation", _UITheme.GAP)
      hbox.add_child(left_col)

      # Artifact card
      var artifact_card := _UITheme.make_card()
      left_col.add_child(artifact_card)

      var artifact_center := CenterContainer.new()
      artifact_card.add_child(artifact_center)

      var artifact_vbox := VBoxContainer.new()
      artifact_vbox.add_theme_constant_override("separation", _UITheme.GAP)
      artifact_center.add_child(artifact_vbox)

      _role_label = Label.new()
      _role_label.text = "YOU ARE THE AUCTIONEER"
      _role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _UITheme.style_section_label(_role_label)
      artifact_vbox.add_child(_role_label)

      _name_label = Label.new()
      _name_label.text = "..."
      _name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
      _UITheme.style_label(_name_label, _UITheme.FS_ARTIFACT, _UITheme.TEXT)
      artifact_vbox.add_child(_name_label)

      _cat_label = Label.new()
      _cat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _UITheme.style_label(_cat_label, _UITheme.FS_LABEL, _UITheme.DIM)
      artifact_vbox.add_child(_cat_label)

      _value_label = Label.new()
      _value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _UITheme.style_label(_value_label, _UITheme.FS_VALUE, _UITheme.GOLD)
      artifact_vbox.add_child(_value_label)

      _flavor_label = Label.new()
      _flavor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _flavor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
      _UITheme.style_label(_flavor_label, _UITheme.FS_BODY, _UITheme.DIM)
      artifact_vbox.add_child(_flavor_label)

      # Action card
      var action_card := _UITheme.make_card()
      left_col.add_child(action_card)

      var action_center := CenterContainer.new()
      action_card.add_child(action_center)

      var action_vbox := VBoxContainer.new()
      action_vbox.add_theme_constant_override("separation", _UITheme.GAP)
      action_center.add_child(action_vbox)

      _countdown_label = Label.new()
      _countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _UITheme.style_label(_countdown_label, _UITheme.FS_TIMER, _UITheme.TEXT)
      action_vbox.add_child(_countdown_label)

      _bid_status_label = Label.new()
      _bid_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _bid_status_label.visible = false
      _UITheme.style_label(_bid_status_label, _UITheme.FS_BODY, _UITheme.DIM)
      action_vbox.add_child(_bid_status_label)

      var btn_row := HBoxContainer.new()
      btn_row.add_theme_constant_override("separation", _UITheme.GAP)
      btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
      action_vbox.add_child(btn_row)

      _open_early_btn = Button.new()
      _open_early_btn.text = "OPEN EARLY"
      _open_early_btn.pressed.connect(_on_open_early_pressed)
      _UITheme.style_ghost_button(_open_early_btn)
      _open_early_btn.visible = false
      btn_row.add_child(_open_early_btn)

      if NetworkManager.is_host():
          _force_btn = Button.new()
          _force_btn.text = "FORCE RESOLVE"
          _force_btn.pressed.connect(func(): GameServer.force_resolve())
          _UITheme.style_ghost_button(_force_btn)
          _force_btn.visible = false
          btn_row.add_child(_force_btn)

      # Right column (player panel)
      var right_col := VBoxContainer.new()
      right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
      right_col.size_flags_stretch_ratio = 1.0
      hbox.add_child(right_col)

      var player_card := _UITheme.make_card()
      right_col.add_child(player_card)

      var player_inner := VBoxContainer.new()
      player_inner.set_anchors_preset(Control.PRESET_FULL_RECT)
      player_inner.offset_left   =  _UITheme.PAD
      player_inner.offset_top    =  _UITheme.PAD
      player_inner.offset_right  = -_UITheme.PAD
      player_inner.offset_bottom = -_UITheme.PAD
      player_inner.add_theme_constant_override("separation", _UITheme.GAP)
      player_card.add_child(player_inner)

      var players_lbl := Label.new()
      players_lbl.text = "PLAYERS"
      _UITheme.style_section_label(players_lbl)
      player_inner.add_child(players_lbl)

      _player_vbox = VBoxContainer.new()
      _player_vbox.add_theme_constant_override("separation", 4)
      player_inner.add_child(_player_vbox)

      _refresh_players()
  ```

- [ ] **Step 3: Add `_refresh_players()` method**

  Add after `_build_ui()`:

  ```gdscript
  func _refresh_players() -> void:
      for child in _player_vbox.get_children():
          child.queue_free()
      var own_id: int = multiplayer.get_unique_id()
      for peer_id in NetworkManager.player_names:
          var name: String = NetworkManager.player_names[peer_id]
          var row := HBoxContainer.new()
          row.add_theme_constant_override("separation", _UITheme.GAP)
          _player_vbox.add_child(row)
          var is_me: bool = peer_id == own_id
          var name_lbl := Label.new()
          name_lbl.text = name
          name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
          _UITheme.style_label(name_lbl, _UITheme.FS_BODY,
              _UITheme.GOLD if is_me else _UITheme.TEXT)
          row.add_child(name_lbl)
          var cash: int = GameServer.player_cash.get(name, -1)
          var cash_lbl := Label.new()
          cash_lbl.text = "§%d" % cash if cash >= 0 else "—"
          _UITheme.style_label(cash_lbl, _UITheme.FS_BODY, _UITheme.DIM)
          row.add_child(cash_lbl)
  ```

- [ ] **Step 4: Call `_refresh_players()` at auction start**

  In `on_auctioneer_reveal()`, add `_refresh_players()` as the first line of the method body.

- [ ] **Step 5: Verify no syntax errors**

  Run: `godot --headless --quit --path hot-garbage-godot 2>&1 | grep -i error | head -20`

  Expected: no errors in `auctioneer_view.gd`

- [ ] **Step 6: Commit**

  ```bash
  git add hot-garbage-godot/src/scenes/auctioneer_view.gd
  git commit -m "feat: auctioneer view three-zone layout — artifact card, action card, player panel"
  ```

---

### Task 4: bidder_view.gd — three-zone layout

**Files:**
- Modify: `hot-garbage-godot/src/scenes/bidder_view.gd`

**Interfaces:**
- Consumes: `UITheme.make_card()`, `UITheme.make_content_hbox()` from Task 1
- Produces:
  - New member: `_player_vbox: VBoxContainer`
  - New method: `_refresh_players() -> void` (identical logic to Task 3)
  - Existing public API unchanged: `on_start_pitch(artifact, pitch_duration)`, `on_open_bidding()`

Existing member vars all stay. Add `_player_vbox: VBoxContainer`.

- [ ] **Step 1: Add `_player_vbox` member var**

  After `var _counting: bool = false` add:
  ```gdscript
  var _player_vbox: VBoxContainer
  ```

- [ ] **Step 2: Rewrite `_build_ui()`**

  Replace entire body:

  ```gdscript
  func _build_ui() -> void:
      _UITheme.add_bg(self)

      const HUDScript = preload("res://src/scenes/hud.gd")
      _hud = HUDScript.new()
      add_child(_hud)

      var main := Control.new()
      main.set_anchors_preset(Control.PRESET_FULL_RECT)
      main.offset_left = _UITheme.HUD_WIDTH
      add_child(main)

      var hbox := _UITheme.make_content_hbox(main)

      # Left column
      var left_col := VBoxContainer.new()
      left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
      left_col.size_flags_stretch_ratio = 2.5
      left_col.add_theme_constant_override("separation", _UITheme.GAP)
      hbox.add_child(left_col)

      # Artifact card
      var artifact_card := _UITheme.make_card()
      left_col.add_child(artifact_card)

      var artifact_center := CenterContainer.new()
      artifact_card.add_child(artifact_center)

      var artifact_vbox := VBoxContainer.new()
      artifact_vbox.add_theme_constant_override("separation", _UITheme.GAP)
      artifact_center.add_child(artifact_vbox)

      _header_label = Label.new()
      _header_label.text = "WAITING FOR AUCTION..."
      _header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _UITheme.style_section_label(_header_label)
      artifact_vbox.add_child(_header_label)

      _name_label = Label.new()
      _name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
      _UITheme.style_label(_name_label, _UITheme.FS_ARTIFACT, _UITheme.TEXT)
      artifact_vbox.add_child(_name_label)

      _cat_label = Label.new()
      _cat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _UITheme.style_label(_cat_label, _UITheme.FS_LABEL, _UITheme.DIM)
      artifact_vbox.add_child(_cat_label)

      _flavor_label = Label.new()
      _flavor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _flavor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
      _UITheme.style_label(_flavor_label, _UITheme.FS_BODY, _UITheme.DIM)
      artifact_vbox.add_child(_flavor_label)

      # Action card
      var action_card := _UITheme.make_card()
      left_col.add_child(action_card)

      var action_center := CenterContainer.new()
      action_card.add_child(action_center)

      var action_vbox := VBoxContainer.new()
      action_vbox.add_theme_constant_override("separation", _UITheme.GAP)
      action_center.add_child(action_vbox)

      _phase_label = Label.new()
      _phase_label.text = "BIDDING OPENS IN"
      _phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _UITheme.style_section_label(_phase_label)
      action_vbox.add_child(_phase_label)

      _countdown_label = Label.new()
      _countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _UITheme.style_label(_countdown_label, _UITheme.FS_TIMER, _UITheme.TEXT)
      action_vbox.add_child(_countdown_label)

      _bid_area = Control.new()
      _bid_area.custom_minimum_size = Vector2(0, 60)
      _bid_area.modulate.a = 0.4
      action_vbox.add_child(_bid_area)

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
      action_vbox.add_child(_status_label)

      # Right column (player panel)
      var right_col := VBoxContainer.new()
      right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
      right_col.size_flags_stretch_ratio = 1.0
      hbox.add_child(right_col)

      var player_card := _UITheme.make_card()
      right_col.add_child(player_card)

      var player_inner := VBoxContainer.new()
      player_inner.set_anchors_preset(Control.PRESET_FULL_RECT)
      player_inner.offset_left   =  _UITheme.PAD
      player_inner.offset_top    =  _UITheme.PAD
      player_inner.offset_right  = -_UITheme.PAD
      player_inner.offset_bottom = -_UITheme.PAD
      player_inner.add_theme_constant_override("separation", _UITheme.GAP)
      player_card.add_child(player_inner)

      var players_lbl := Label.new()
      players_lbl.text = "PLAYERS"
      _UITheme.style_section_label(players_lbl)
      player_inner.add_child(players_lbl)

      _player_vbox = VBoxContainer.new()
      _player_vbox.add_theme_constant_override("separation", 4)
      player_inner.add_child(_player_vbox)

      _refresh_players()
  ```

- [ ] **Step 3: Add `_refresh_players()` method**

  Identical to Task 3 — add after `_build_ui()`:

  ```gdscript
  func _refresh_players() -> void:
      for child in _player_vbox.get_children():
          child.queue_free()
      var own_id: int = multiplayer.get_unique_id()
      for peer_id in NetworkManager.player_names:
          var name: String = NetworkManager.player_names[peer_id]
          var row := HBoxContainer.new()
          row.add_theme_constant_override("separation", _UITheme.GAP)
          _player_vbox.add_child(row)
          var is_me: bool = peer_id == own_id
          var name_lbl := Label.new()
          name_lbl.text = name
          name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
          _UITheme.style_label(name_lbl, _UITheme.FS_BODY,
              _UITheme.GOLD if is_me else _UITheme.TEXT)
          row.add_child(name_lbl)
          var cash: int = GameServer.player_cash.get(name, -1)
          var cash_lbl := Label.new()
          cash_lbl.text = "§%d" % cash if cash >= 0 else "—"
          _UITheme.style_label(cash_lbl, _UITheme.FS_BODY, _UITheme.DIM)
          row.add_child(cash_lbl)
  ```

- [ ] **Step 4: Call `_refresh_players()` at auction start**

  In `on_start_pitch()`, add `_refresh_players()` as the first line.

- [ ] **Step 5: Verify no syntax errors**

  Run: `godot --headless --quit --path hot-garbage-godot 2>&1 | grep -i error | head -20`

  Expected: no errors in `bidder_view.gd`

- [ ] **Step 6: Commit**

  ```bash
  git add hot-garbage-godot/src/scenes/bidder_view.gd
  git commit -m "feat: bidder view three-zone layout — artifact card, action card, player panel"
  ```

---

### Task 5: bid_reveal.gd + final_scores.gd — wider centered layout

**Files:**
- Modify: `hot-garbage-godot/src/scenes/bid_reveal.gd`
- Modify: `hot-garbage-godot/src/scenes/final_scores.gd`

**Interfaces:**
- No new public API; internal layout width change only

- [ ] **Step 1: Widen bid_reveal VBox**

  In `bid_reveal.gd` `_build_ui()`, change:
  ```gdscript
  vbox.custom_minimum_size = Vector2(480, 300)
  ```
  to:
  ```gdscript
  vbox.custom_minimum_size = Vector2(960, 300)
  ```

- [ ] **Step 2: Widen final_scores outer VBox**

  In `final_scores.gd` `_build_ui()`, after the line `outer.offset_bottom = -_UITheme.PAD * 2` add:
  ```gdscript
  outer.custom_minimum_size = Vector2(960, 0)
  ```

- [ ] **Step 3: Verify no syntax errors**

  Run: `godot --headless --quit --path hot-garbage-godot 2>&1 | grep -i error | head -20`

  Expected: no errors in either file

- [ ] **Step 4: Commit**

  ```bash
  git add hot-garbage-godot/src/scenes/bid_reveal.gd hot-garbage-godot/src/scenes/final_scores.gd
  git commit -m "feat: widen bid_reveal and final_scores content area to 960px"
  ```
