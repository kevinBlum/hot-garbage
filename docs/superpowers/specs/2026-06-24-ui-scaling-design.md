# Hot Garbage — UI Scaling Design Spec

## Goal

Make the game fill the screen correctly at 1080p and 1440p desktop monitors. Currently there is no viewport configuration — the game launches in a small default window with no scaling, making all UI elements tiny and poorly placed.

---

## 1. Godot Project Settings

Add a `[display]` section to `project.godot`:

```
[display]

window/size/viewport_width=1920
window/size/viewport_height=1080
window/stretch/mode="canvas_items"
window/stretch/scale_mode="fractional"
window/size/mode=3
```

- **Viewport 1920×1080** — design canvas matches the primary target. At 1440p (2560×1440), Godot scales up 1.33×.
- **canvas_items stretch** — scales individual UI nodes so text rendering stays crisp (vs. viewport mode which upscales a blurry texture).
- **fractional scale** — smooth interpolation at non-integer ratios.
- **mode=3** — borderless fullscreen on launch (standard modern desktop approach). Players can Alt+F4 or add a quit shortcut.

A resolution settings screen is out of scope for this pass.

---

## 2. `ui_theme.gd` — Updated Size Constants

All sizes are now authored for the 1920×1080 canvas. Godot handles scaling to the actual display.

| Constant | Old | New | Notes |
|---|---|---|---|
| `FS_LABEL` | 9 | 13 | Section headers (ALL CAPS, dim) |
| `FS_BODY` | 12 | 16 | Body text, status lines |
| `FS_ARTIFACT` | 17 | 24 | Artifact names, titles |
| `FS_VALUE` | 27 | 40 | True value display |
| `FS_TIMER` | 32 | 48 | Pitch countdown |
| `PAD` | 12 | 20 | Internal panel padding |
| `GAP` | 8 | 12 | Element spacing |
| `HUD_WIDTH` | 130 | 200 | Left sidebar width |

No other changes to `ui_theme.gd`.

---

## 3. Menu Layout — `main_menu.gd` and `lobby.gd`

Both scenes use a centered `VBoxContainer` with `custom_minimum_size`. Update to fill ~⅓ of the 1920×1080 canvas:

| Scene | Old size | New size |
|---|---|---|
| `main_menu.gd` | `Vector2(400, 320)` | `Vector2(640, 480)` |
| `lobby.gd` | `Vector2(420, 420)` | `Vector2(640, 520)` |

No structural changes — only the `custom_minimum_size` value changes.

---

## 4. In-Game Scenes

`auctioneer_view`, `bidder_view`, `bid_reveal`, and `final_scores` all use `PRESET_FULL_RECT` for their main content area. They will fill the 1920×1080 canvas automatically. The only change that affects them is `HUD_WIDTH` increasing from 130 to 200, which is already referenced via `_UITheme.HUD_WIDTH` — no scene-level code changes needed.

---

## 5. What Is Not In Scope

- Resolution settings screen
- Per-scene layout redesign
- Mobile or tablet layouts
- Aspect ratio letterboxing (Godot handles this via stretch mode)
