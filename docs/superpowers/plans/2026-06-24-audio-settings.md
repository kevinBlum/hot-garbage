# Audio + Settings + Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** AudioManager autoload with synthesized SFX, a settings screen (volume + display), and Escape keyboard shortcuts.

**Architecture:** AudioManager generates WAV data in-memory at startup — no external audio files. It manages AudioServer bus volumes and persists settings to `user://settings.cfg`. Settings scene follows the same programmatic-UI pattern as other scenes. Escape is handled per-scene via `_unhandled_key_input`.

**Tech Stack:** Godot 4.3, GDScript, `AudioStreamWAV`, `AudioServer`, `ConfigFile`, `DisplayServer`

## Global Constraints

- No external audio files — all sounds synthesized via `AudioStreamWAV` in GDScript
- UITheme constants (`FS_*`, `PAD`, `GAP`) used in settings scene — no hardcoded sizes
- All labels styled via `_UITheme.style_label()` or `_UITheme.style_section_label()`
- Settings scene uses programmatic layout (same pattern as `main_menu.gd`) — no Godot editor
- `engine.js` and `scoring.js` stay I/O-free
- `artifact.value` must never appear in broadcast/RPC context
- Autoloads (AudioManager, GameServer, NetworkManager) accessed by registered name, not `preload()`

---

### Task 1: AudioManager autoload

**Files:**
- Create: `hot-garbage-godot/src/audio/audio_manager.gd`
- Modify: `hot-garbage-godot/project.godot`

**Interfaces:**
- Produces:
  - `AudioManager.play_ui() -> void`
  - `AudioManager.play_bid() -> void`
  - `AudioManager.play_open() -> void`
  - `AudioManager.play_resolve() -> void`
  - `AudioManager.master_volume: float` (0.0–1.0)
  - `AudioManager.sfx_volume: float` (0.0–1.0)
  - `AudioManager.music_volume: float` (0.0–1.0)
  - `AudioManager.apply_volumes() -> void`
  - `AudioManager.save_settings() -> void`
  - `AudioManager.load_settings() -> void`

- [ ] **Step 1: Create the `src/audio/` directory and `audio_manager.gd`**

  ```gdscript
  extends Node

  var master_volume: float = 1.0
  var sfx_volume:    float = 1.0
  var music_volume:  float = 1.0

  var _player_ui:      AudioStreamPlayer
  var _player_bid:     AudioStreamPlayer
  var _player_open:    AudioStreamPlayer
  var _player_resolve: AudioStreamPlayer

  func _ready() -> void:
      _ensure_buses()
      _player_ui      = _make_player(_make_beep(880.0, 0.06, 8.0))
      _player_bid     = _make_player(_make_beep(550.0, 0.12, 8.0))
      _player_open    = _make_player(_make_beep(660.0, 0.20, 4.0))
      _player_resolve = _make_player(_make_beep(440.0, 0.35, 4.0))
      load_settings()

  func play_ui()      -> void: _player_ui.play()
  func play_bid()     -> void: _player_bid.play()
  func play_open()    -> void: _player_open.play()
  func play_resolve() -> void: _player_resolve.play()

  func apply_volumes() -> void:
      AudioServer.set_bus_volume_db(
          AudioServer.get_bus_index("Master"), linear_to_db(master_volume))
      var sfx_idx: int = AudioServer.get_bus_index("SFX")
      if sfx_idx >= 0:
          AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(sfx_volume))
      var music_idx: int = AudioServer.get_bus_index("Music")
      if music_idx >= 0:
          AudioServer.set_bus_volume_db(music_idx, linear_to_db(music_volume))

  func save_settings() -> void:
      var cfg := ConfigFile.new()
      cfg.set_value("audio", "master", master_volume)
      cfg.set_value("audio", "sfx",    sfx_volume)
      cfg.set_value("audio", "music",  music_volume)
      cfg.save("user://settings.cfg")

  func load_settings() -> void:
      var cfg := ConfigFile.new()
      if cfg.load("user://settings.cfg") != OK:
          apply_volumes()
          return
      master_volume = cfg.get_value("audio", "master", 1.0)
      sfx_volume    = cfg.get_value("audio", "sfx",    1.0)
      music_volume  = cfg.get_value("audio", "music",  1.0)
      apply_volumes()

  # ---- private ----

  func _ensure_buses() -> void:
      if AudioServer.get_bus_index("SFX") < 0:
          AudioServer.add_bus()
          var idx: int = AudioServer.get_bus_count() - 1
          AudioServer.set_bus_name(idx, "SFX")
          AudioServer.set_bus_send(idx, "Master")
      if AudioServer.get_bus_index("Music") < 0:
          AudioServer.add_bus()
          var idx: int = AudioServer.get_bus_count() - 1
          AudioServer.set_bus_name(idx, "Music")
          AudioServer.set_bus_send(idx, "Master")

  func _make_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
      var p := AudioStreamPlayer.new()
      p.stream = stream
      p.bus = "SFX"
      add_child(p)
      return p

  static func _make_beep(freq: float, duration: float, decay: float) -> AudioStreamWAV:
      var sample_rate: int = 44100
      var n: int = int(sample_rate * duration)
      var data := PackedByteArray()
      data.resize(n * 2)
      for i in n:
          var t: float = float(i) / float(sample_rate)
          var v: int = int(sin(TAU * freq * t) * 32767.0 * exp(-t * decay))
          data.encode_s16(i * 2, clampi(v, -32768, 32767))
      var wav := AudioStreamWAV.new()
      wav.format   = AudioStreamWAV.FORMAT_16_BITS
      wav.mix_rate = sample_rate
      wav.stereo   = false
      wav.data     = data
      return wav
  ```

- [ ] **Step 2: Register AudioManager in `project.godot`**

  In `[autoload]` section, add after the existing lines:
  ```ini
  AudioManager="*res://src/audio/audio_manager.gd"
  ```

- [ ] **Step 3: Verify no syntax errors**

  Run: `godot --headless --quit --path hot-garbage-godot 2>&1 | grep -i error | head -20`

  Expected: no GDScript errors; AudioManager registers without crash

- [ ] **Step 4: Commit**

  ```bash
  git add hot-garbage-godot/src/audio/audio_manager.gd hot-garbage-godot/project.godot
  git commit -m "feat: AudioManager autoload — synthesized SFX, volume control, settings persistence"
  ```

---

### Task 2: Wire audio events to all scenes

**Files:**
- Modify: `hot-garbage-godot/src/scenes/main_menu.gd`
- Modify: `hot-garbage-godot/src/scenes/lobby.gd`
- Modify: `hot-garbage-godot/src/scenes/auctioneer_view.gd`
- Modify: `hot-garbage-godot/src/scenes/bidder_view.gd`
- Modify: `hot-garbage-godot/src/scenes/bid_reveal.gd`

**Interfaces:**
- Consumes: `AudioManager.play_ui()`, `play_bid()`, `play_open()`, `play_resolve()` from Task 1

- [ ] **Step 1: main_menu.gd — button press audio**

  In `_on_host_pressed()`, add `AudioManager.play_ui()` as the first line.
  In `_on_join_pressed()`, add `AudioManager.play_ui()` as the first line.

- [ ] **Step 2: lobby.gd — button press audio**

  In `_on_start_pressed()`, add `AudioManager.play_ui()` as the first line.

- [ ] **Step 3: auctioneer_view.gd — button and event audio**

  In `_on_open_early_pressed()`, add `AudioManager.play_ui()` as the first line.

  In `on_open_bidding()`, add `AudioManager.play_open()` as the first line.

  If `_force_btn` exists, its `pressed` lambda currently calls `GameServer.force_resolve()`. Change the lambda to also call `AudioManager.play_ui()`:
  ```gdscript
  _force_btn.pressed.connect(func():
      AudioManager.play_ui()
      GameServer.force_resolve())
  ```

- [ ] **Step 4: bidder_view.gd — bid and event audio**

  In `_on_submit_pressed()`, add `AudioManager.play_bid()` as the first line.

  In `on_open_bidding()`, add `AudioManager.play_open()` as the first line.

- [ ] **Step 5: bid_reveal.gd — resolve audio**

  In `on_show_bid_result()`, add `AudioManager.play_resolve()` as the first line.

- [ ] **Step 6: Verify no syntax errors**

  Run: `godot --headless --quit --path hot-garbage-godot 2>&1 | grep -i error | head -20`

  Expected: no errors in any modified scene

- [ ] **Step 7: Commit**

  ```bash
  git add hot-garbage-godot/src/scenes/main_menu.gd \
          hot-garbage-godot/src/scenes/lobby.gd \
          hot-garbage-godot/src/scenes/auctioneer_view.gd \
          hot-garbage-godot/src/scenes/bidder_view.gd \
          hot-garbage-godot/src/scenes/bid_reveal.gd
  git commit -m "feat: wire audio events — UI clicks, bid submit, bidding open, auction resolve"
  ```

---

### Task 3: Settings scene

**Files:**
- Create: `hot-garbage-godot/src/scenes/settings.gd`
- Create: `hot-garbage-godot/src/scenes/settings.tscn`

**Interfaces:**
- Consumes: `AudioManager.master_volume`, `sfx_volume`, `music_volume`, `apply_volumes()`, `save_settings()` from Task 1
- Produces: a navigable scene at `res://src/scenes/settings.tscn`

- [ ] **Step 1: Create `settings.gd`**

  ```gdscript
  extends Control

  const _UITheme = preload("res://src/scenes/ui_theme.gd")

  func _ready() -> void:
      _build_ui()

  func _build_ui() -> void:
      _UITheme.add_bg(self)

      var vbox := VBoxContainer.new()
      vbox.set_anchors_preset(Control.PRESET_CENTER)
      vbox.custom_minimum_size = Vector2(640, 600)
      vbox.add_theme_constant_override("separation", _UITheme.GAP * 2)
      add_child(vbox)

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
  ```

- [ ] **Step 2: Create `settings.tscn`**

  Create a minimal `.tscn` file referencing the script:

  ```
  [gd_scene load_steps=2 format=3]

  [ext_resource type="Script" path="res://src/scenes/settings.gd" id="1"]

  [node name="Settings" type="Control"]
  script = ExtResource("1")
  anchor_right = 1.0
  anchor_bottom = 1.0
  ```

- [ ] **Step 3: Verify no syntax errors**

  Run: `godot --headless --quit --path hot-garbage-godot 2>&1 | grep -i error | head -20`

  Expected: no errors in `settings.gd`

- [ ] **Step 4: Commit**

  ```bash
  git add hot-garbage-godot/src/scenes/settings.gd hot-garbage-godot/src/scenes/settings.tscn
  git commit -m "feat: settings scene — volume sliders, windowed/fullscreen toggle"
  ```

---

### Task 4: Navigation + Escape shortcuts

**Files:**
- Modify: `hot-garbage-godot/src/scenes/main_menu.gd`
- Modify: `hot-garbage-godot/src/scenes/auctioneer_view.gd`
- Modify: `hot-garbage-godot/src/scenes/bidder_view.gd`
- Modify: `hot-garbage-godot/src/scenes/bid_reveal.gd`
- Modify: `hot-garbage-godot/src/scenes/final_scores.gd`
- Modify: `hot-garbage-godot/src/network/network_manager.gd`

**Interfaces:**
- Consumes: `AudioManager.play_ui()` from Task 1, `settings.tscn` from Task 3
- Produces: `NetworkManager.disconnect_from_game() -> void`

- [ ] **Step 1: Add `disconnect_from_game()` to NetworkManager**

  In `network_manager.gd`, add a new public method:

  ```gdscript
  func disconnect_from_game() -> void:
      multiplayer.multiplayer_peer = null
      player_names.clear()
  ```

- [ ] **Step 2: Add SETTINGS button to main_menu.gd**

  In `main_menu.gd` `_build_ui()`, after the JOIN GAME button and before the status label, add:

  ```gdscript
  var settings_btn := Button.new()
  settings_btn.text = "SETTINGS"
  settings_btn.pressed.connect(_on_settings_pressed)
  _UITheme.style_ghost_button(settings_btn)
  right.add_child(settings_btn)
  ```

  Add handler method:
  ```gdscript
  func _on_settings_pressed() -> void:
      AudioManager.play_ui()
      get_tree().change_scene_to_file("res://src/scenes/settings.tscn")
  ```

- [ ] **Step 3: Add Escape → quit dialog to main_menu.gd**

  Add `_unhandled_key_input` and `_show_quit_dialog()` to `main_menu.gd`:

  ```gdscript
  func _unhandled_key_input(event: InputEvent) -> void:
      if event.is_action_pressed("ui_cancel"):
          _show_quit_dialog()

  func _show_quit_dialog() -> void:
      var dlg := ConfirmationDialog.new()
      dlg.title = "Quit"
      dlg.dialog_text = "Quit Hot Garbage?"
      dlg.confirmed.connect(func(): get_tree().quit())
      dlg.canceled.connect(func(): dlg.queue_free())
      add_child(dlg)
      dlg.popup_centered()
  ```

- [ ] **Step 4: Add Escape → leave dialog to auctioneer_view.gd**

  Add to `auctioneer_view.gd`:

  ```gdscript
  func _unhandled_key_input(event: InputEvent) -> void:
      if event.is_action_pressed("ui_cancel"):
          _show_leave_dialog()

  func _show_leave_dialog() -> void:
      var dlg := ConfirmationDialog.new()
      dlg.title = "Leave"
      dlg.dialog_text = "Leave game and return to menu?"
      dlg.confirmed.connect(func():
          NetworkManager.disconnect_from_game()
          get_tree().change_scene_to_file("res://src/scenes/main_menu.tscn"))
      dlg.canceled.connect(func(): dlg.queue_free())
      add_child(dlg)
      dlg.popup_centered()
  ```

- [ ] **Step 5: Add the same Escape handler to bidder_view.gd, bid_reveal.gd, final_scores.gd**

  Add the identical `_unhandled_key_input` and `_show_leave_dialog()` methods from Step 4 to each of these three files verbatim. (The dialog text and behavior are the same in all in-game scenes.)

- [ ] **Step 6: Verify no syntax errors**

  Run: `godot --headless --quit --path hot-garbage-godot 2>&1 | grep -i error | head -20`

  Expected: no errors in any modified file

- [ ] **Step 7: Commit**

  ```bash
  git add hot-garbage-godot/src/network/network_manager.gd \
          hot-garbage-godot/src/scenes/main_menu.gd \
          hot-garbage-godot/src/scenes/auctioneer_view.gd \
          hot-garbage-godot/src/scenes/bidder_view.gd \
          hot-garbage-godot/src/scenes/bid_reveal.gd \
          hot-garbage-godot/src/scenes/final_scores.gd
  git commit -m "feat: settings nav + Escape shortcuts — quit dialog on menu, leave dialog in-game"
  ```
