# Audio + Settings + Shortcuts Design

## Goal

Add basic game feel: procedurally synthesized sound effects on key events, a settings screen (volume + display), and keyboard shortcuts (Escape to return to menu / quit).

---

## AudioManager Autoload

**File:** `hot-garbage-godot/src/audio/audio_manager.gd`
**Registered as:** `AudioManager` in `project.godot`

Generates all sound data in-memory at startup using `AudioStreamWAV` — no external audio files required.

### Sounds

Four distinct tones synthesized as mono 44100 Hz 16-bit PCM with exponential fade-out:

| Method | Frequency | Duration | Character |
|--------|-----------|----------|-----------|
| `play_ui()` | 880 Hz | 60 ms | Short click — button press |
| `play_bid()` | 550 Hz | 120 ms | Soft confirm — bid submitted |
| `play_open()` | 660 Hz | 200 ms | Rising tone — bidding opens |
| `play_resolve()` | 440 Hz | 350 ms | Lower settle — winner revealed |

Synthesis formula for sample `i` at sample rate `SR` and frequency `F`:
```
t = i / SR
sample = sin(2π × F × t) × 32767 × exp(-t × decay)
```
`decay = 8.0` for short sounds (ui, bid), `4.0` for longer (open, resolve).

### Volume

Properties:
```gdscript
var master_volume: float = 1.0   # 0.0–1.0
var sfx_volume: float    = 1.0   # 0.0–1.0
var music_volume: float  = 1.0   # 0.0–1.0 (reserved for future music)
```

Applied via AudioServer bus volumes:
- Master bus: `linear_to_db(master_volume)`
- SFX bus: `linear_to_db(sfx_volume)` — all AudioStreamPlayers routed to "SFX" bus
- Music bus: `linear_to_db(music_volume)` — reserved, create "Music" bus even if unused

Create buses in `_ready()` via `AudioServer.add_bus()` if they don't already exist; set send to "Master".

### Settings persistence

File: `user://settings.cfg` via `ConfigFile`.

```gdscript
func save_settings() -> void   # writes master/sfx/music_volume
func load_settings() -> void   # reads and applies; called in _ready()
```

`apply_volumes()` private method updates AudioServer bus dB from current property values. Called after loading and after any slider change.

### AudioStreamPlayer nodes

Create one `AudioStreamPlayer` per sound in `_ready()`, add as children, assign to "SFX" bus. Store as `_player_ui`, `_player_bid`, `_player_open`, `_player_resolve`.

`play_*()` methods simply call `.play()` on the corresponding player (fire-and-forget, no overlap needed).

---

## Sound Event Wiring

Wire `AudioManager.play_*()` calls into existing scenes — no architectural changes, just signal connections.

### Button press (`play_ui`)
Every `Button.pressed` signal in:
- `main_menu.gd` — HOST GAME, JOIN GAME buttons
- `lobby.gd` — START GAME button
- `auctioneer_view.gd` — OPEN EARLY, FORCE RESOLVE buttons
- `bidder_view.gd` — SUBMIT BID button
- `settings.gd` — BACK button, display toggle buttons
- `final_scores.gd` — any buttons present

Pattern: add `AudioManager.play_ui()` as an additional connection alongside the existing handler.

### Bid submitted (`play_bid`)
In `bidder_view.gd` `_on_submit_pressed()`: call `AudioManager.play_bid()` when bid is submitted.

### Bidding opens (`play_open`)
In `auctioneer_view.gd` and `bidder_view.gd` `on_open_bidding()`: call `AudioManager.play_open()`.

### Auction resolves (`play_resolve`)
In `bid_reveal.gd` `on_show_bid_result()`: call `AudioManager.play_resolve()`.

---

## Settings Scene

**Files:** `hot-garbage-godot/src/scenes/settings.gd`, `hot-garbage-godot/src/scenes/settings.tscn`

Programmatic layout (same approach as `main_menu.gd` — no .tscn editor, all built in `_build_ui()`).

### Layout

Centered VBoxContainer (`custom_minimum_size = Vector2(640, 600)`, `PRESET_CENTER`, separation = `GAP * 2`):

1. Title: "SETTINGS" — `FS_ARTIFACT`, GOLD, centered
2. Section label "AUDIO"
3. Row: "MASTER" label + HSlider (0.0–1.0)
4. Row: "SOUND EFFECTS" label + HSlider (0.0–1.0)
5. Row: "MUSIC" label + HSlider (0.0–1.0)
6. Section label "DISPLAY"
7. HBoxContainer: [WINDOWED button] [FULLSCREEN button] — toggle pair
8. BACK button (`style_button`)

Slider rows: HBoxContainer with a 160px min-width label left, HSlider right (`SIZE_EXPAND_FILL`).

HSlider styling: use `add_theme_stylebox_override` for "slider" (SURFACE bg, BORDER border) and "grabber_area" (GOLD bg). Font via `style_label`.

### Behaviour

- Sliders initialized from `AudioManager.master_volume`, `sfx_volume`, `music_volume`
- `value_changed` signal on each slider → updates the corresponding `AudioManager` property + calls `AudioManager.apply_volumes()` + calls `AudioManager.save_settings()`
- Display toggle: calls `DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)` or `WINDOW_MODE_FULLSCREEN` — highlight active button with `style_button`, the other with `style_ghost_button`
- BACK button: `get_tree().change_scene_to_file("res://src/scenes/main_menu.tscn")`

---

## Navigation and Shortcuts

### Settings access

Add a "SETTINGS" ghost button to `main_menu.gd`, below the JOIN GAME button (before the status label). Pressing it: `AudioManager.play_ui()` + `get_tree().change_scene_to_file("res://src/scenes/settings.tscn")`.

### Escape — main menu

In `main_menu.gd`, handle `_unhandled_key_input(event)`:
```gdscript
if event.is_action_pressed("ui_cancel"):
    _show_quit_dialog()
```

`_show_quit_dialog()` adds a `ConfirmationDialog` child: "Quit Hot Garbage?" with OK → `get_tree().quit()`, Cancel → close.

### Escape — in-game scenes

In `auctioneer_view.gd`, `bidder_view.gd`, `bid_reveal.gd`, `final_scores.gd`:
```gdscript
if event.is_action_pressed("ui_cancel"):
    _show_leave_dialog()
```

`_show_leave_dialog()` adds a `ConfirmationDialog`: "Leave game and return to menu?" with OK → `NetworkManager.disconnect_from_game()` + `get_tree().change_scene_to_file("res://src/scenes/main_menu.tscn")`.

`NetworkManager.disconnect_from_game()` is a new method that calls `multiplayer.multiplayer_peer = null` and resets `player_names`.

---

## Global Constraints

- No external audio files — all sounds synthesized at runtime via `AudioStreamWAV`
- `engine.js` and `scoring.js` stay I/O-free
- UITheme constants used for all sizes/colors in settings scene
- `artifact.value` never in public/broadcast context
- Settings scene follows the same programmatic-layout pattern as all other scenes (no `.tscn` editor use)

## Files

- `hot-garbage-godot/src/audio/audio_manager.gd` — new autoload
- `hot-garbage-godot/project.godot` — register AudioManager autoload + "SFX"/"Music" buses
- `hot-garbage-godot/src/scenes/settings.gd` — new scene script
- `hot-garbage-godot/src/scenes/settings.tscn` — new scene file (minimal, script-driven)
- `hot-garbage-godot/src/scenes/main_menu.gd` — SETTINGS button, Escape handler
- `hot-garbage-godot/src/scenes/lobby.gd` — button audio
- `hot-garbage-godot/src/scenes/auctioneer_view.gd` — button + open audio, Escape
- `hot-garbage-godot/src/scenes/bidder_view.gd` — bid + open audio, Escape
- `hot-garbage-godot/src/scenes/bid_reveal.gd` — resolve audio, Escape
- `hot-garbage-godot/src/scenes/final_scores.gd` — Escape
- `hot-garbage-godot/src/network/network_manager.gd` — `disconnect_from_game()`
