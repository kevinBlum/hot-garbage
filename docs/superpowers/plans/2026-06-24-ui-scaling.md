# UI Scaling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the game launch fullscreen at 1920×1080 with all UI elements properly sized for desktop monitors.

**Architecture:** Set a 1920×1080 design canvas in `project.godot` with `canvas_items` stretch so Godot scales all UI nodes proportionally to the actual display. Update size constants in `ui_theme.gd` to match the larger canvas. Update fixed VBox widths in the two menu scenes.

**Tech Stack:** Godot 4.7, GDScript. No build step. Test by running the project from the Godot editor (F5) and visually verifying layout.

## Global Constraints

- Godot 4.7 GDScript — explicit type annotations on any `:=` where RHS is Variant
- All UI built programmatically — no `.tscn` edits
- `game_engine.gd` and `scoring.gd` must remain unchanged
- No new files — only modify existing files listed below

---

### Task 1: Project display settings + UITheme size constants

**Files:**
- Modify: `hot-garbage-godot/project.godot`
- Modify: `hot-garbage-godot/src/scenes/ui_theme.gd`

**Interfaces:**
- Produces: `UITheme` constants at new values — all scenes that `preload` `ui_theme.gd` pick up the changes automatically

- [ ] **Step 1: Add display section to `project.godot`**

Open `hot-garbage-godot/project.godot`. It currently has no `[display]` section. Add it at the end of the file:

```ini
[display]

window/size/viewport_width=1920
window/size/viewport_height=1080
window/stretch/mode="canvas_items"
window/stretch/scale_mode="fractional"
window/size/mode=3
```

`mode=3` is borderless fullscreen. `canvas_items` stretch scales individual UI nodes (text stays crisp). `fractional` scale handles non-integer ratios like 1440p (1.33×).

- [ ] **Step 2: Update size constants in `ui_theme.gd`**

In `hot-garbage-godot/src/scenes/ui_theme.gd`, replace the 8 const declarations:

```gdscript
const FS_LABEL    := 13
const FS_BODY     := 16
const FS_ARTIFACT := 24
const FS_VALUE    := 40
const FS_TIMER    := 48
const PAD         := 20
const GAP         := 12
const HUD_WIDTH   := 200
```

- [ ] **Step 3: Launch the game and verify**

Open `hot-garbage-godot/` in the Godot editor and press F5 (or Run > Run Project).

Expected:
- Game launches fullscreen (fills the entire monitor, no window chrome)
- Main menu appears centered with `HOT GARBAGE` title visible and legibly large
- Text is crisp (not blurry or pixelated)
- The black background fills the whole screen

If the game opens windowed instead of fullscreen, confirm `window/size/mode=3` was saved correctly in `project.godot`.

- [ ] **Step 4: Commit**

```bash
git add hot-garbage-godot/project.godot hot-garbage-godot/src/scenes/ui_theme.gd
git commit -m "feat: 1920x1080 canvas, fullscreen, updated UITheme size constants"
```

---

### Task 2: Menu VBox sizes

**Files:**
- Modify: `hot-garbage-godot/src/scenes/main_menu.gd`
- Modify: `hot-garbage-godot/src/scenes/lobby.gd`

**Interfaces:**
- Consumes: Task 1's updated `UITheme` constants (PAD, GAP already used; no new interface)

- [ ] **Step 1: Update `main_menu.gd` VBox size**

In `hot-garbage-godot/src/scenes/main_menu.gd`, find the line:

```gdscript
vbox.custom_minimum_size = Vector2(400, 320)
```

Replace with:

```gdscript
vbox.custom_minimum_size = Vector2(640, 480)
```

- [ ] **Step 2: Update `lobby.gd` VBox size**

In `hot-garbage-godot/src/scenes/lobby.gd`, find the line:

```gdscript
vbox.custom_minimum_size = Vector2(420, 420)
```

Replace with:

```gdscript
vbox.custom_minimum_size = Vector2(640, 520)
```

- [ ] **Step 3: Launch and verify both scenes**

Press F5 in the Godot editor.

Expected for main menu:
- `HOT GARBAGE` title, subtitle, name/IP fields, HOST and JOIN buttons fill roughly the center third of the screen
- No element is clipped or pushed off-screen
- Fields are wide enough to type a name and IP address comfortably

Navigate to lobby (host a game):
- `LOBBY` title, player list, PITCH TIMER spinbox, and START GAME button all visible and well-spaced
- SpinBox is wide enough to read `45 sec`

- [ ] **Step 4: Commit**

```bash
git add hot-garbage-godot/src/scenes/main_menu.gd hot-garbage-godot/src/scenes/lobby.gd
git commit -m "feat: expand menu VBox sizes for 1920x1080 canvas"
```
