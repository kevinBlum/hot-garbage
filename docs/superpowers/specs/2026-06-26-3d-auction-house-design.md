# Hot Garbage 3D Auction House — Design Spec

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the 2D text-based in-game UI with a fully 3D multiplayer auction house where players inhabit low-poly characters, run around a physics-filled room, pick up and throw the auction items, and submit bids via screen overlay UI — while all auction logic stays on the existing Node.js WebSocket server.

**Architecture:** Option 1 — extend the existing WebSocket server minimally (position relay, junk masking, round info, bid timer), rebuild only the Godot in-game client in 3D, expose a `NetworkTransport` seam so the underlying transport can be swapped to ENet or Colyseus later without touching game logic.

**Tech Stack:** Godot 4.7, GDScript, Node.js WebSocket server (existing), Godot `CharacterBody3D` + `RigidBody3D` physics, `SpringArm3D` third-person camera, `Label3D` for in-world text, Godot 2D `CanvasLayer` for screen overlays.

---

## Global Constraints

- All auction logic (bid validation, round sequencing, scoring, chaos) stays on the Node.js server — no game logic moves to the client.
- `artifact.value` must never be sent to non-auctioneer clients. The auctioneer overlay is the only place a true value is displayed.
- The `junk` category must be masked as `"unknown"` in all messages sent to bidders. The auctioneer sees the real category.
- `NetworkTransport` is the only file that touches WebSocket directly. All other game code calls `NetworkTransport` methods.
- Main menu, lobby, and settings scenes stay 2D — only the in-game experience (everything after lobby → scene change) goes 3D.
- The 3D environment starts with Godot primitives and `CSGBox3D`/`MeshInstance3D` — no external 3D asset dependency required to run. Kenney.nl assets can drop in later.
- All player positions/physics are client-authoritative. The server is a dumb relay for `player_move` — no server-side position validation.
- Maximum 8 players, matching the existing server `maxPlayers` constraint.

---

## Section 1 — Server Changes

Small additions to `hot-garbage-server/server.js` and `game_session.js`. No existing behaviour changes.

### 1a. Junk category masking

In `game_session.js`, `_beginTurn()` already computes `publicArtifact` by calling `this._engine.startAuction()`. Add one line to mask junk before broadcast:

```js
const publicArtifact = this._engine.startAuction(this._currentAuctioneer);
if (publicArtifact.category === 'junk') publicArtifact.category = 'unknown';
```

The `fullArtifact` sent only to the auctioneer is unchanged.

### 1b. Round info in start_pitch

Add `round` and `totalRounds` to the `start_pitch` broadcast in `_beginTurn()`:

```js
this._send(null, {
  type: 'start_pitch',
  artifact: publicArtifact,
  pitchDuration: this._pitchDuration / 1000,
  auctioneerName: this._currentAuctioneer,
  round: this._round,
  totalRounds: this._engine.getRounds(),
});
```

### 1c. Bid timer (auto-resolve)

Add `bidTimeout` to `GameSession` config (default 30s). After `_openBidding()` fires, start a timeout that calls `_resolveAuction()` if it hasn't already resolved:

```js
_openBidding() {
  if (this._biddingOpen) return;
  this._biddingOpen = true;
  this._send(null, { type: 'open_bidding' });
  const timeout = this._config.bidTimeout ?? 30;
  if (timeout > 0) {
    setTimeout(() => {
      if (this._biddingOpen && !this._pendingResolve) this._resolveAuction();
    }, timeout * 1000);
  }
}
```

Players who have not submitted a bid by resolve time are treated as §0 bids (existing engine behaviour for missing bidders).

### 1d. Player position relay

Add a new message type `player_move` to `server.js`. The server relays it to all other players in the room without storing state:

```js
case 'player_move':
  broadcastRoom(ctx.roomName, {
    type: 'player_move',
    playerName: ctx.playerName,
    x: msg.x, y: msg.y, z: msg.z,
    ry: msg.ry,
    anim: msg.anim,
  }, ctx.playerName); // exclude sender
  return;
```

No position is stored on the server. Late-joining players get no position history — they see other players teleport to their current position on their first `player_move` message, which is acceptable.

---

## Section 2 — NetworkTransport (Godot)

New autoload at `src/network/network_transport.gd`. Wraps all outbound WebSocket writes and all inbound dispatch routing. `NetworkManager` is refactored to call `NetworkTransport` instead of touching `_ws` directly.

```gdscript
# src/network/network_transport.gd
extends Node

signal message_received(msg: Dictionary)

func send(msg: Dictionary) -> void:
    # internal — calls _ws.send_text
    pass

func send_bid(amount: int) -> void:
    send({ "type": "submit_bid", "amount": amount })

func send_position(pos: Vector3, ry: float, anim: String) -> void:
    send({ "type": "player_move", "x": pos.x, "y": pos.y, "z": pos.z,
           "ry": ry, "anim": anim })

func send_open_early() -> void:
    send({ "type": "open_early" })

func send_force_resolve() -> void:
    send({ "type": "force_resolve" })

func send_start_game(pitch_duration: int) -> void:
    send({ "type": "start_game", "pitchDuration": pitch_duration })
```

All game scenes subscribe to `NetworkTransport.message_received` and filter by `msg.type`. `NetworkManager` handles connection lifecycle (connect, reconnect, close) and emits connection signals as today — it does not dispatch game messages.

Swapping the transport later = rewrite `network_transport.gd` only.

---

## Section 3 — Scene Structure

### Scenes that stay 2D (unchanged or minor polish)
- `src/scenes/main_menu.tscn` / `main_menu.gd` — add brief "how to play" text blurb, room name hint
- `src/scenes/lobby.tscn` / `lobby.gd` — show who created the room, show "waiting for host to start"
- `src/scenes/settings.tscn` / `settings.gd` — unchanged

### Scenes that are replaced
All five in-game scenes (`bidder_view`, `auctioneer_view`, `bid_reveal`, `final_scores`, `hud`) are deleted and replaced by one scene:

**`src/scenes/auction_house.tscn`** — the single persistent 3D scene used for the entire game session. Loads when the server sends `advance_scene: auction_house` (new scene key). The scene never changes during a game; auction phases update in-world elements and screen overlays instead.

The server's `advance_scene` messages for `bidder_view` and `auctioneer_view` are replaced by a single `advance_scene: auction_house` sent once at game start. Phase messages (`start_pitch`, `open_bidding`, `bid_result`, `chaos`, `final_scores`) are received inside the scene and update state without a scene swap.

---

## Section 4 — 3D Auction House Environment

### Room layout

Single room, ~30×20 units. Constructed from `StaticBody3D` + `CSGBox3D` primitives. All loose props are `RigidBody3D`.

```
[BACK WALL]
  ┌────────────────────────────┐
  │         STAGE              │  ← raised platform 0.5u, podium prop,
  │       [PODIUM]             │    gavel stand (gavel mode only)
  │                            │
  │       [PEDESTAL]           │  ← item display, center of room
  │                            │
  │  chairs  boxes  trinkets   │  ← throwable RigidBody3D props
  │                            │
  │       spawn zone           │  ← players appear here at game start
  └────────────────────────────┘
[FRONT WALL / CAMERA SIDE]

[LEFT WALL]  — Scoreboard wall (3D billboard, updates each auction)
[RIGHT WALL] — Phase sign + bid timer display (chalkboard prop)
```

### Key props

| Prop | Type | Notes |
|------|------|-------|
| Stage platform | StaticBody3D | Raised 0.5u, players can walk up |
| Podium | StaticBody3D | Auctioneer stands behind it |
| Gavel stand | StaticBody3D | Used in gavel mode only; hidden in default mode |
| Item pedestal | StaticBody3D | Center room; `Label3D` shows item name + category |
| Scoreboard | StaticBody3D + SubViewport | Left wall, rendered as texture, updated each auction |
| Bid timer sign | StaticBody3D + Label3D | Right wall, shows countdown during bidding |
| Phase sign | StaticBody3D + Label3D | Above stage, shows PITCH / BIDDING / SOLD / GRAND REVEAL |
| Chairs (×6) | RigidBody3D | Stackable, throwable |
| Crates (×4) | RigidBody3D | Throwable |
| Trinkets (×8) | RigidBody3D | Small decorative props, throwable |
| Auction item | RigidBody3D | Spawned per-auction from item data; resets to pedestal on bidding open |

### Lighting

Three-point lighting: warm overhead fill, cool rim, spot on the pedestal that intensifies during pitch phase. `WorldEnvironment` with a subtle ambient glow. No global illumination — flat shading on materials keeps the low-poly look.

### Art style

All geometry uses `StandardMaterial3D` with `shading_mode = SHADING_MODE_UNSHADED` for flat low-poly look. Category palette colors from `UITheme` apply to material albedo on category-colored props. Character materials are assigned per-player from a fixed 8-color palette at spawn.

---

## Section 5 — Player Character

### Node structure

```
PlayerCharacter (CharacterBody3D)
├── CollisionShape3D        ← capsule
├── MeshInstance3D          ← low-poly body (placeholder capsule → Kenney swap)
├── HandAnchor (Node3D)     ← right hand position, for held object parenting
├── SpringArm3D             ← camera arm (local player only)
│   └── Camera3D
├── Label3D                 ← player name above head
├── CrownMesh (MeshInstance3D, hidden by default) ← auctioneer indicator
└── GrabArea (Area3D)       ← sphere trigger for pickup detection
```

`HandAnchor` is a plain `Node3D` positioned at the hand offset from the capsule center. When a proper rigged mesh replaces the capsule, this can become a `BoneAttachment3D` without touching any other code.

Two versions: `LocalPlayer` (has camera + input handling) and `RemotePlayer` (interpolates from network position updates).

### Movement

- WASD relative to camera forward
- Shift: sprint (1.8× speed)
- Space: jump (single hop, `CharacterBody3D.move_and_slide`)
- Gravity: standard Godot 9.8
- Squash/stretch on land: `Tween` scale Y 0.7→1.2→1.0 over 0.2s for bouncy feel

### Pickup / throw

- `GrabArea` detects nearby `RigidBody3D` nodes tagged `interactable`
- Press `E`: grab nearest — object freezes physics, parents to hand bone, `held_object` reference stored
- Hold `E` + move mouse: aim direction
- Release `E`: throw — unparents object, restores physics, applies `character.velocity + camera.basis.z * -throw_force` as impulse
- One object at a time; grabbing a second drops the first
- Auction item is `interactable` during pitch phase only; on `open_bidding` it is kinematically reset to pedestal position and marked non-interactable until next pitch

### Network sync (LocalPlayer)

`NetworkTransport.send_position()` called in `_physics_process` throttled to 10Hz (track elapsed time, only send when ≥ 0.1s since last send).

Payload: `{ x, y, z, ry, anim }` where `anim` is one of `"idle"`, `"run"`, `"hold"`, `"throw"`.

### Remote player interpolation

`RemotePlayer._physics_process` tweens `global_position` and `rotation.y` toward latest received values using `lerp` at factor 0.25 per frame. Animation state applies immediately on receipt.

### Auctioneer indicator

When `start_pitch` arrives, the player matching `auctioneerName` has `CrownMesh.visible = true`. All other players have it `false`. Removed when `bid_result` arrives.

### Player color palette

Eight distinct colors assigned round-robin at join time (one per possible player slot), stored in `NetworkManager.player_colors: Dictionary`. Applied to character `MeshInstance3D` surface material. Persists for the session.

Palette (hex): `#E74C3C`, `#3498DB`, `#2ECC71`, `#F39C12`, `#9B59B6`, `#1ABC9C`, `#E67E22`, `#EC407A`.

---

## Section 6 — In-Game UI

All overlay UI lives in a `CanvasLayer` inside `AuctionHouse`. None of it is in-world — in-world text uses `Label3D` on props.

### Persistent HUD (always visible)

Top-left strip:
- Your cash: `§1200` in gold
- Round counter: `ROUND 2 / 5`
- Your collection pips: colored squares, one per artifact owned by category

### Auctioneer overlay (auctioneer only, pitch phase)

Small banner top-center:
- `TRUE VALUE: §740`
- `CATEGORY: ANTIQUITIES`
- Subtle gold border; invisible to all other players

### Bid panel (all non-auctioneers, bidding phase)

Slides in from bottom when `open_bidding` received:
- Item name and category (masked if junk)
- Your current cash
- `SpinBox` for bid amount (min 0, max player cash)
- `SUBMIT BID` button — disables on press, shows "Waiting..."
- Bid countdown timer mirroring the in-world sign
- Auto-dismissed when timer hits 0 (bid submitted as §0 if not manually submitted)

### Bid reveal overlay (all players, resolve phase)

Full-screen card fades in for 3s:
- `SOLD` header
- Winner name large
- `§740` price large
- Item name
- "No takers. Bank paid §X." if winner is BANK
- Winner's `RemotePlayer` gets a `CPUParticles3D` gold burst simultaneously
- Fades out automatically; next pitch begins

### Chaos card (all players, after resolve if chaos fires)

Slides in from right, persists 4s:
- `APPRAISER:` or `EVENT:` header
- Chaos text
- Victim/lost-item line if applicable

### Final scores overlay (end of game)

Replaces entire screen (no scene change):
- `GRAND REVEAL` title
- Ranked list: medal, name, total pts, cash
- Per-category breakdown with set bonus indicators
- `PLAY AGAIN` button (host only) — sends `delete_room` + returns to main menu
- `LEAVE` button for non-hosts

### Phase sign values

| Phase | Sign text | Pedestal spotlight |
|-------|-----------|-------------------|
| Pre-pitch | `NEXT UP` | Off |
| Pitch | `PITCH PHASE` | On (bright) |
| Bidding | `BIDDING OPEN` | Dim |
| Reveal | `SOLD` | Dim |
| Final | `GRAND REVEAL` | Off |

---

## Section 7 — Game Modes

### Default: Hidden Bid

Current behaviour — bid panel accepts a typed number, submitted secretly. Server resolves all bids simultaneously. This is the primary mode and is implemented first.

### Future: Gavel Mode (public bid)

Optional room config flag `bidMode: "gavel"`. When enabled:
- Gavel stand prop is visible on stage
- During bidding phase, players walk to the gavel stand and press `E` to interact (replaces throw — gavel is not throwable)
- Interacting with the gavel opens a small quick-bid panel (same SpinBox + submit)
- On submit, a `player_bid_public` message is broadcast: `{ playerName, amount }` — all players see who bid (but not the amount until reveal)
- Auctioneer sees a `bid_count` update as today
- Resolve logic is unchanged

Gavel mode is specced here for awareness but **not implemented in this plan**. The gavel stand prop is built but hidden in default mode so it can be enabled later without environment changes.

---

## Section 8 — Server Scene Key Change

`game_session.js` `_beginTurn()` currently sends `advance_scene: bidder_view` or `advance_scene: auctioneer_view`. Replace with a single `advance_scene: auction_house` sent once when `start()` is called, then remove the per-turn `advance_scene` calls. Phase changes are communicated via `start_pitch`, `open_bidding`, `bid_result`, `final_scores` as today.

`network_manager.gd` `SCENE_PATHS` adds:
```gdscript
"auction_house": "res://src/scenes/auction_house.tscn",
```

The old scene paths (`bidder_view`, `auctioneer_view`, `bid_reveal`) are removed from `SCENE_PATHS` once the 3D client ships.

---

## Out of Scope

- Ragdoll / Gang Beasts physics (future upgrade once character controller is solid)
- Gavel mode implementation (specced, not built)
- Sound effects beyond existing `AudioManager` hooks (new 3D positional audio is future work)
- Custom character creator / cosmetics
- Mobile / web export (desktop only for now)
- HTTPS / WSS (existing HTTP/WS, no change)
- Spectator mode
- Replay system
