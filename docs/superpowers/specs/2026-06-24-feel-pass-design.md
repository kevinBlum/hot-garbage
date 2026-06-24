# Hot Garbage — Feel Pass Design Spec

## Goals

Make the game **simple, repeatable, fun, and goofy**. This pass adds the pitch phase (the core social mechanic), a persistent HUD, and a full visual style treatment across all six scenes. No new game rules or engine changes — pure UI/UX.

---

## 1. Visual Language

**Dark & Minimal.** The goofy content carries the tone; the chrome stays out of the way.

| Element | Value |
|---|---|
| Background | `#111111` |
| Surface (sidebar, panels) | `#0d0d0d` |
| Border / divider | `#222222` |
| Body text | `#ffffff` |
| Dim text (labels, hints) | `#555555` |
| Cash / gold accent | `#C9A227` |
| Font | `Courier New`, monospace fallback |

**Category accent colors** (border + text, never background fill):

| Category | Color |
|---|---|
| antiquities | `#C9A227` |
| curios | `#7B6CD9` |
| relics | `#C04F4F` |
| forgeries | `#3FA66A` |
| junk | `#8A8A8A` |

**Typography rules:**
- Section labels: 9px, `letter-spacing: 2px`, `color: #555`, ALL CAPS
- Artifact name: 16–18px, bold, white
- True value: 26–28px, bold, gold
- Countdown timer: 32px, bold, white
- Body / flavor text: 12px, italic, `#555`

**Spacing:** 12px internal padding on panels; 8px between elements.

---

## 2. Persistent HUD — Left Sidebar

Present on **all in-game scenes** (auctioneer_view, bidder_view, bid_reveal, final_scores). Not shown on main_menu or lobby.

**Layout:** Fixed 130px-wide column on the left edge, full height, `background: #0d0d0d`, right border `1px solid #222`.

**Contents (top to bottom):**
1. `YOU` label (dim, small caps)
2. Player's cash: `§NNN` in gold, 16px bold
3. `COLLECTION` label (dim, small caps)
4. One row per category owned, showing category color square + name + count: `■ Curios ×2`
5. Total artifact count at bottom, dim

**Implementation note:** A shared `hud.gd` script builds this sidebar and is instantiated by each in-game scene in its `_build_ui()`. It reads from `NetworkManager.player_names` (for own peer ID) and `GameServer` exposed state (see Section 6).

---

## 3. Pitch Phase

This is the core new mechanic. Each auction now has two phases:

### Phase 1 — Pitch (bidding locked)

The auctioneer talks over voice while a countdown runs. Bidders see the artifact info and the timer but **cannot bid yet**.

**Auctioneer screen during pitch:**
- Left sidebar (HUD)
- Role header: `YOU ARE THE AUCTIONEER` (gold, small caps)
- Artifact name (white, large)
- Category chip (colored border + text, no fill)
- Flavor text (italic, dim)
- `TRUE VALUE: §NNN` (gold, large)
- Countdown: big centered number, e.g. `0:42`
- `OPEN EARLY` button (dim, secondary style — ghost button)

**Bidder screen during pitch:**
- Left sidebar (HUD)
- Header: `[Name] IS SELLING` (dim, small caps)
- Artifact name, category chip, flavor text (same layout as auctioneer minus value)
- `BIDDING OPENS IN` label + big countdown `0:42`
- Bid input area — visible but fully dimmed and non-interactive (`modulate.a = 0.4`)

### Phase 2 — Bidding (open)

When the pitch timer expires OR the auctioneer hits OPEN EARLY, the server broadcasts `rpc_open_bidding()` to all peers.

**Auctioneer screen during bidding:**
- Countdown replaced by `BIDDING OPEN`
- Bid count: `Bids received: N / N` (updates live)
- `OPEN EARLY` button hidden/disabled
- `FORCE RESOLVE` button visible (host only, escape hatch — unchanged)

**Bidder screen during bidding:**
- `BIDDING OPENS IN` countdown replaced by `BIDDING IS OPEN`
- Bid input fully visible and enabled
- After submit: input dims, status line `Bid submitted. Waiting...`

---

## 4. Pitch Timer Configuration

- **Default:** 45 seconds
- **Range:** 20–120 seconds (20s floor prevents chaos; 120s ceiling prevents stalling)
- **Where set:** Lobby screen, host only. A labeled `SpinBox` showing `Pitch timer: 45s`.
- **How passed:** `GameServer.start_game(player_ids, pitch_duration)` receives it from the lobby.

---

## 5. Scene-by-Scene Changes

### `main_menu.gd`
- Apply dark minimal style to all elements (background, labels, inputs, buttons)
- No layout changes

### `lobby.gd`
- Apply dark minimal style
- Add `SpinBox` (host only, range 20–120, default 45, suffix `" sec"`) with label `PITCH TIMER`
- Pass selected value to `GameServer.start_game(player_ids, pitch_duration)`

### `auctioneer_view.gd`
- Full rebuild for two-phase layout (pitch → bidding)
- Add HUD sidebar
- Add countdown label (counts down from pitch_duration, bold 32px)
- Add `OPEN EARLY` ghost button — calls `NetworkManager.send_open_early()`
- On `rpc_open_bidding` received: hide countdown, show `BIDDING OPEN`, show bid count

### `bidder_view.gd`
- Full rebuild for two-phase layout
- Add HUD sidebar
- Add `BIDDING OPENS IN` + countdown (display only, not authoritative)
- Bid input rendered but dimmed/disabled until `rpc_open_bidding` received
- On open: enable input, update header to `BIDDING IS OPEN`

### `bid_reveal.gd`
- Apply dark minimal style
- No layout or logic changes

### `final_scores.gd`
- Apply dark minimal style
- No logic changes

---

## 6. New RPC Contract

### `NetworkManager` additions

```
rpc_start_pitch(artifact: Dictionary, pitch_duration: int)
  → broadcasts to all peers (call_local)
  → replaces current rpc_start_bidding
  → triggers on_start_pitch(artifact, pitch_duration) via propagate_call

rpc_open_bidding()
  → broadcasts to all peers (call_local)
  → triggers on_open_bidding() via propagate_call

send_open_early()
  → client → host RPC (any_peer, reliable)
  → host validates sender is current auctioneer, then calls _open_bidding()
```

The existing `rpc_start_bidding` is **replaced** by `rpc_start_pitch`. No other RPC changes.

### `GameServer` additions

- `start_game(player_ids: Array, pitch_duration: int)` — accepts timer setting
- `_pitch_duration: int` stored instance variable
- `_begin_turn()` sends `rpc_start_pitch(public_artifact, _pitch_duration)` instead of `rpc_start_bidding`
- `_open_bidding()` — called when pitch timer fires OR open_early received. Broadcasts `rpc_open_bidding()`. Guards against double-fire with `_bidding_open: bool` flag.
- Pitch timer: `get_tree().create_timer(_pitch_duration).timeout` awaited inside `_begin_turn` after sending rpc_start_pitch. If `_bidding_open` already true (auctioneer opened early), skip broadcast.

### `GameServer` exposed state for HUD

```gdscript
# Read by hud.gd to populate collection sidebar
var player_artifacts: Dictionary = {}  # player_id (String) -> Array of artifact Dicts
var player_cash: Dictionary = {}       # player_id (String) -> int
```

These are initialized in `start_game()` (cash = 1000 for all, artifacts = []) and updated incrementally after each `resolve_auction()` result: winner gains the artifact, winner's cash decreases by price, seller's cash increases by price. The HUD reads `player_artifacts[own_player_id]` and `player_cash[own_player_id]`, where `own_player_id = NetworkManager.player_names.get(multiplayer.get_unique_id(), "")`.

---

## 7. `hud.gd` — Shared Sidebar Component

New file: `hot-garbage-godot/src/scenes/hud.gd`

```
class: HUD (extends Control)
width: 130px fixed
anchor: left edge, full height

Reads:
  - NetworkManager.player_names (to find own player_id from peer_id)
  - GameServer.player_cash[own_player_id]
  - GameServer.player_artifacts[own_player_id]

Public method:
  refresh() — called by host scenes after bid resolution to update displayed values
```

Each in-game scene instantiates HUD as a child and positions its own content to the right of it.

---

## 8. What Is Not In Scope

- Other players' cash or collections (not shown — by design, information asymmetry)
- Sound effects, animations, particle effects
- Artwork or icons for artifacts
- Bidding timer (separate from pitch timer — bidding stays open until all bids received or force resolve)
- Mobile layout
- Any engine (game_engine.gd / scoring.gd) changes
