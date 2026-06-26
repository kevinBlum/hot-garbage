# Hot Garbage 3D Auction House Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 2D text-based in-game UI with a fully 3D multiplayer auction house where players run around a physics-filled room and submit bids via CanvasLayer overlays.

**Architecture:** Minimal Node.js server additions (junk masking, round info, bid timer, position relay), a new `NetworkTransport` GDScript autoload as the only game-action WebSocket touch point, and a single persistent `auction_house.tscn` scene that replaces all five 2D in-game scenes. Scenes stay loaded for the whole game session; phase changes update in-world elements and CanvasLayer overlays instead of swapping scenes.

**Tech Stack:** Node.js 18 + `node:test` (server), Godot 4.7 GDScript (client), `CharacterBody3D` + `RigidBody3D` physics, `SpringArm3D` third-person camera, `Label3D` in-world text, `CanvasLayer` overlays.

## Global Constraints

- `artifact.value` must never appear in any message sent to non-auctioneer clients.
- `junk` category is sent as `"unknown"` to bidders; auctioneer still sees `"junk"` via `auctioneer_reveal`.
- `NetworkTransport` (`src/network/network_transport.gd`) is the ONLY file that calls `NetworkManager._send()` for outbound game actions. Scene scripts never call `_send` directly.
- All auction logic stays on the Node.js server — no bid math moves to the client.
- Player positions are client-authoritative; server relays `player_move` without validation.
- 3D environment uses CSG primitives and `MeshInstance3D` only — no external `.glb`/`.obj` asset files required to run.
- Maximum 8 players (matches server `maxPlayers: 8`).
- `engine.js` and `scoring.js` must stay I/O-free (no fs/fetch/console).
- Never use `set_anchors_preset(Control.PRESET_CENTER)` with `custom_minimum_size` — always use `_UITheme.add_center_container(parent)` instead (see CLAUDE.md).
- Player color palette (8 colors, index by `player_names.find(name) % 8`): `["#E74C3C", "#3498DB", "#2ECC71", "#F39C12", "#9B59B6", "#1ABC9C", "#E67E22", "#EC407A"]`.

## File Map

**Server**
- Modify: `hot-garbage-server/game_session.js`
- Modify: `hot-garbage-server/server.js`
- Modify: `hot-garbage-server/test/game_session.test.js`

**Godot — Network**
- Create: `hot-garbage-godot/src/network/network_transport.gd`
- Modify: `hot-garbage-godot/src/network/network_manager.gd`
- Modify: `hot-garbage-godot/project.godot`

**Godot — Main Scene**
- Create: `hot-garbage-godot/src/scenes/auction_house.tscn`
- Create: `hot-garbage-godot/src/scenes/auction_house.gd`

**Godot — Characters**
- Create: `hot-garbage-godot/src/characters/local_player.gd`
- Create: `hot-garbage-godot/src/characters/local_player.tscn`
- Create: `hot-garbage-godot/src/characters/remote_player.gd`
- Create: `hot-garbage-godot/src/characters/remote_player.tscn`

**Godot — Props**
- Create: `hot-garbage-godot/src/props/throwable_prop.gd`

**Godot — UI Overlays**
- Create: `hot-garbage-godot/src/ui/hud_overlay.gd`
- Create: `hot-garbage-godot/src/ui/auctioneer_overlay.gd`
- Create: `hot-garbage-godot/src/ui/bid_panel.gd`
- Create: `hot-garbage-godot/src/ui/bid_reveal_overlay.gd`
- Create: `hot-garbage-godot/src/ui/chaos_card.gd`
- Create: `hot-garbage-godot/src/ui/final_scores_overlay.gd`

**Delete in Task 12**
- `hot-garbage-godot/src/scenes/auctioneer_view.gd` + `.tscn` + `.gd.uid`
- `hot-garbage-godot/src/scenes/bidder_view.gd` + `.tscn` + `.gd.uid`
- `hot-garbage-godot/src/scenes/bid_reveal.gd` + `.tscn` + `.gd.uid`
- `hot-garbage-godot/src/scenes/final_scores.gd` + `.tscn` + `.gd.uid`
- `hot-garbage-godot/src/scenes/hud.gd` + `.gd.uid`

---

## Task 1: Server Changes

**Files:**
- Modify: `hot-garbage-server/game_session.js`
- Modify: `hot-garbage-server/server.js`
- Modify: `hot-garbage-server/test/game_session.test.js`

**Interfaces:**
- Produces: `start_pitch` now includes `round: number` and `totalRounds: number`. `open_bidding` now auto-resolves after `bidTimeout` seconds (default 30). `player_move` is relayed to all room members except sender. Junk artifacts broadcast as `category: "unknown"` in `start_pitch`.

- [ ] **Step 1: Open `hot-garbage-server/game_session.js` and add junk masking + round info to `_beginTurn`**

  Find `_beginTurn()`. After `const publicArtifact = this._engine.startAuction(...)` and before the `_send` calls, add the junk mask. Then add `round` and `totalRounds` to the `start_pitch` broadcast:

  ```js
  async _beginTurn() {
    if (this._round > this._engine.getRounds()) {
      this._endGame();
      return;
    }

    this._turnGen++;
    const myGen = this._turnGen;
    this._biddingOpen = false;
    this._pendingResolve = false;
    this._receivedBidCount = 0;

    this._currentAuctioneer = this._order[this._turnIdx];

    for (const name of this._playerNames) {
      this._send(name, {
        type: 'advance_scene',
        scene: name === this._currentAuctioneer ? 'auctioneer_view' : 'bidder_view',
      });
    }

    const publicArtifact = this._engine.startAuction(this._currentAuctioneer);
    const fullArtifact = this._engine.getAuctioneerArtifact();

    // Mask junk category so bidders can't identify it from category alone
    if (publicArtifact.category === 'junk') publicArtifact.category = 'unknown';

    this._send(this._currentAuctioneer, {
      type: 'auctioneer_reveal',
      artifact: fullArtifact,
      pitchDuration: this._pitchDuration / 1000,
    });

    this._send(null, {
      type: 'start_pitch',
      artifact: publicArtifact,
      pitchDuration: this._pitchDuration / 1000,
      auctioneerName: this._currentAuctioneer,
      round: this._round,
      totalRounds: this._engine.getRounds(),
    });

    await sleep(this._pitchDuration);
    if (myGen === this._turnGen && !this._biddingOpen) {
      this._openBidding();
    }
  }
  ```

- [ ] **Step 2: Replace `_openBidding` with the bid timer version**

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

  Store `config` on the instance — add `this._config = config;` in the constructor (it already passes `config` to the engine but doesn't store it):

  ```js
  constructor(playerNames, config, send) {
    this._playerNames = playerNames;
    this._config = config;              // ← add this line
    this._pitchDuration = (config.pitchDuration ?? 45) * 1000;
    // ... rest unchanged
  }
  ```

- [ ] **Step 3: Add `_engineFactory` escape hatch to constructor (for testing)**

  Just below `this._config = config;`:

  ```js
  this._engineFactory = config._engineFactory || null;
  ```

  In `start()`, replace the `new HotGarbageServer(...)` call:

  ```js
  start() {
    this.isActive = true;
    this._engine = this._engineFactory
      ? this._engineFactory()
      : new HotGarbageServer({
          seed: (Math.random() * 0x100000000) >>> 0,
          playerIds: this._playerNames,
          chaosChance: this._chaosChance,
          dataPath: DATA_PATH,
        });
    this._order = this._engine.getOrder();
    this._beginTurn();
  }
  ```

- [ ] **Step 4: Add `player_move` relay in `hot-garbage-server/server.js`**

  In the `ws.on('message', ...)` switch block, add before the closing `}`:

  ```js
  case 'player_move':
    if (ctx.roomName) {
      broadcastRoom(ctx.roomName, {
        type: 'player_move',
        playerName: ctx.playerName,
        x: msg.x ?? 0, y: msg.y ?? 0, z: msg.z ?? 0,
        ry: msg.ry ?? 0,
        anim: msg.anim ?? 'idle',
      }, ctx.playerName); // exclude sender
    }
    return;
  ```

- [ ] **Step 5: Add tests to `hot-garbage-server/test/game_session.test.js`**

  Append these tests after the existing ones:

  ```js
  test('start_pitch includes round and totalRounds', async () => {
    const { session, log } = makeSession();
    session.start();
    await new Promise(r => setTimeout(r, 100));
    const pitch = msgsOf(log, 'start_pitch')[0];
    assert.ok(pitch, 'start_pitch should be sent');
    assert.equal(pitch.msg.round, 1, 'first turn is round 1');
    assert.equal(typeof pitch.msg.totalRounds, 'number');
    assert.ok(pitch.msg.totalRounds > 0);
  });

  test('junk category is masked as unknown in start_pitch', async () => {
    const log = [];
    const send = (to, msg) => log.push({ to, msg });
    const junkArtifact = { id: 99, name: 'Trash Bag', category: 'junk', flavor: 'Smells bad' };
    const mockEngine = {
      startAuction: () => ({ ...junkArtifact }),
      getAuctioneerArtifact: () => ({ ...junkArtifact, value: 50 }),
      submitBid: () => {},
      allBidsReceived: () => false,
      resolveAuction: () => ({ winner: 'BANK', price: 0, artifact: { id: 99 } }),
      maybeChaos: () => null,
      getFinalScores: () => [],
      getRounds: () => 5,
      getOrder: () => ['Alice', 'Bob', 'Carol'],
      players: {
        Alice: { cash: 1000, artifacts: [] },
        Bob:   { cash: 1000, artifacts: [] },
        Carol: { cash: 1000, artifacts: [] },
      },
    };
    const session = new GameSession(
      ['Alice', 'Bob', 'Carol'],
      { pitchDuration: 0, chaosChance: 0, _engineFactory: () => mockEngine },
      send
    );
    session.start();
    await new Promise(r => setTimeout(r, 100));
    const pitches = log.filter(e => e.msg.type === 'start_pitch');
    assert.ok(pitches.length > 0, 'start_pitch should be sent');
    for (const p of pitches) {
      assert.notEqual(p.msg.artifact.category, 'junk', 'junk must be masked in start_pitch');
      assert.equal(p.msg.artifact.category, 'unknown');
    }
    // Auctioneer reveal must still see real category
    const reveal = log.find(e => e.msg.type === 'auctioneer_reveal');
    assert.ok(reveal);
    assert.equal(reveal.msg.artifact.category, 'junk', 'auctioneer_reveal must preserve real category');
  });

  test('bid timer auto-resolves auction when no bids received', async () => {
    const { session, log } = makeSession(['Alice', 'Bob', 'Carol']);
    // Override bidTimeout in config — re-create with low timeout
    const log2 = [];
    const send2 = (to, msg) => log2.push({ to, msg });
    const session2 = new GameSession(
      ['Alice', 'Bob', 'Carol'],
      { pitchDuration: 0, chaosChance: 0, bidTimeout: 0.05 },
      send2
    );
    session2.start();
    await new Promise(r => setTimeout(r, 300));
    const results = log2.filter(e => e.msg.type === 'bid_result');
    assert.ok(results.length > 0, 'auction must auto-resolve via bid timer');
  });
  ```

- [ ] **Step 6: Run tests**

  ```bash
  cd hot-garbage-server && node --test test/game_session.test.js
  ```

  Expected: all tests pass, including the three new ones.

- [ ] **Step 7: Commit**

  ```bash
  git add hot-garbage-server/game_session.js hot-garbage-server/server.js hot-garbage-server/test/game_session.test.js
  git commit -m "feat: server — junk mask, round info, bid timer, player_move relay"
  ```

---

## Task 2: NetworkTransport Autoload

**Files:**
- Create: `hot-garbage-godot/src/network/network_transport.gd`
- Modify: `hot-garbage-godot/src/network/network_manager.gd`
- Modify: `hot-garbage-godot/project.godot`

**Interfaces:**
- Produces:
  - `NetworkTransport.send_bid(amount: int)`
  - `NetworkTransport.send_position(pos: Vector3, ry: float, anim: String)`
  - `NetworkTransport.send_open_early()`
  - `NetworkTransport.send_force_resolve()`
  - `NetworkTransport.send_start_game(pitch_duration: int)`
- `NetworkManager` now emits `player_moved(player_name, x, y, z, ry, anim)` signal
- `NetworkManager.on_start_pitch` propagate call now passes `round` and `totalRounds` (4 args total)

- [ ] **Step 1: Create `hot-garbage-godot/src/network/network_transport.gd`**

  ```gdscript
  extends Node

  func send_bid(amount: int) -> void:
      NetworkManager._send({ "type": "submit_bid", "amount": amount })

  func send_position(pos: Vector3, ry: float, anim: String) -> void:
      NetworkManager._send({
          "type": "player_move",
          "x": pos.x, "y": pos.y, "z": pos.z,
          "ry": ry, "anim": anim,
      })

  func send_open_early() -> void:
      NetworkManager._send({ "type": "open_early" })

  func send_force_resolve() -> void:
      NetworkManager._send({ "type": "force_resolve" })

  func send_start_game(pitch_duration: int) -> void:
      NetworkManager._send({ "type": "start_game", "pitchDuration": pitch_duration })
  ```

- [ ] **Step 2: Register `NetworkTransport` as an autoload in `hot-garbage-godot/project.godot`**

  In the `[autoload]` section, add the new line (order matters — after NetworkManager so it can call `NetworkManager._send`):

  ```ini
  [autoload]

  NetworkManager="*res://src/network/network_manager.gd"
  NetworkTransport="*res://src/network/network_transport.gd"
  GameServer="*res://src/server/game_server.gd"
  AudioManager="*res://src/audio/audio_manager.gd"
  ```

- [ ] **Step 3: Update `NetworkManager` — add `player_moved` signal and dispatch**

  At the top of `hot-garbage-godot/src/network/network_manager.gd`, add the signal (after the existing signals):

  ```gdscript
  signal player_moved(player_name: String, x: float, y: float, z: float, ry: float, anim: String)
  ```

  In `_dispatch()`, add the `player_move` case inside the `match` block:

  ```gdscript
  "player_move":
      player_moved.emit(
          msg.get("playerName", ""),
          float(msg.get("x", 0.0)), float(msg.get("y", 0.0)), float(msg.get("z", 0.0)),
          float(msg.get("ry", 0.0)),
          msg.get("anim", "idle"))
  ```

- [ ] **Step 4: Update `start_pitch` dispatch in `NetworkManager._dispatch` to pass round/totalRounds**

  Replace:

  ```gdscript
  "start_pitch":
      get_tree().get_root().propagate_call("on_start_pitch",
          [msg.get("artifact", {}), msg.get("pitchDuration", 45)], true)
      if msg.has("auctioneerName"):
          get_tree().get_root().propagate_call("on_auctioneer_name",
              [msg.get("auctioneerName", "")], true)
  ```

  With:

  ```gdscript
  "start_pitch":
      get_tree().get_root().propagate_call("on_start_pitch",
          [msg.get("artifact", {}), msg.get("pitchDuration", 45),
           msg.get("round", 1), msg.get("totalRounds", 5)], true)
      if msg.has("auctioneerName"):
          get_tree().get_root().propagate_call("on_auctioneer_name",
              [msg.get("auctioneerName", "")], true)
  ```

- [ ] **Step 5: Update existing scene scripts that implement `on_start_pitch` to accept the new args**

  `hot-garbage-godot/src/scenes/bidder_view.gd` line 175 — add the two new params (they're unused in the old scene but the signature must match):

  ```gdscript
  func on_start_pitch(artifact: Dictionary, pitch_duration: int, _round: int = 1, _total_rounds: int = 5) -> void:
  ```

  `hot-garbage-godot/src/scenes/auctioneer_view.gd` line 167 — same:

  ```gdscript
  func on_auctioneer_reveal(artifact: Dictionary, pitch_duration: int) -> void:
  ```
  *(auctioneer_reveal signature is unchanged; only `on_start_pitch` changed.)*

  In `hot-garbage-godot/src/scenes/auctioneer_view.gd` find `on_auctioneer_reveal` — that method name is unchanged, nothing to update there. Find `on_start_pitch` — `auctioneer_view.gd` does NOT implement `on_start_pitch`, only `on_auctioneer_reveal`. Confirm `bidder_view.gd` is the only file with `on_start_pitch`.

  Update `bidder_view.gd` line 175:

  ```gdscript
  func on_start_pitch(artifact: Dictionary, pitch_duration: int, _round: int = 1, _total_rounds: int = 5) -> void:
  ```

- [ ] **Step 6: Replace the send methods in `NetworkManager` that scene scripts currently call**

  The existing `NetworkManager.send_open_early()`, `submit_bid()`, `send_force_resolve()`, `start_game()` methods should remain for now (the old 2D scenes still call them). They will be removed in Task 12. No change needed here.

- [ ] **Step 7: Verify in the Godot editor**

  Open Godot, go to **Project → Project Settings → Autoload**. Confirm `NetworkTransport` appears below `NetworkManager`. No editor errors. Open the Script editor and confirm `network_transport.gd` parses without errors (no red underlines).

- [ ] **Step 8: Commit**

  ```bash
  git add hot-garbage-godot/src/network/network_transport.gd \
          hot-garbage-godot/src/network/network_manager.gd \
          hot-garbage-godot/src/scenes/bidder_view.gd \
          hot-garbage-godot/project.godot
  git commit -m "feat: NetworkTransport autoload + player_moved signal + round info dispatch"
  ```

---

## Task 3: 3D Room Environment + Scene Routing

**Files:**
- Create: `hot-garbage-godot/src/scenes/auction_house.tscn`
- Create: `hot-garbage-godot/src/scenes/auction_house.gd`
- Modify: `hot-garbage-godot/src/network/network_manager.gd`

**Interfaces:**
- Produces: `auction_house.tscn` loads when `advance_scene: auction_house` is received. The scene contains a static 30×20 room with stage, pedestal, scoreboard wall, and phase sign. `auction_house.gd` is a stub that will receive all game messages in later tasks.

- [ ] **Step 1: Add `auction_house` to `SCENE_PATHS` in `network_manager.gd`**

  In the `SCENE_PATHS` dictionary, add the new entry:

  ```gdscript
  const SCENE_PATHS := {
      "lobby":           "res://src/scenes/lobby.tscn",
      "auction_house":   "res://src/scenes/auction_house.tscn",
      "auctioneer_view": "res://src/scenes/auctioneer_view.tscn",
      "bidder_view":     "res://src/scenes/bidder_view.tscn",
      "bid_reveal":      "res://src/scenes/bid_reveal.tscn",
      "final_scores":    "res://src/scenes/final_scores.tscn",
  }
  ```

- [ ] **Step 2: Create `hot-garbage-godot/src/scenes/auction_house.tscn`**

  ```
  [gd_scene load_steps=2 format=3]

  [ext_resource type="Script" path="res://src/scenes/auction_house.gd" id="1"]

  [node name="AuctionHouse" type="Node3D"]
  script = ExtResource("1")
  ```

- [ ] **Step 3: Create `hot-garbage-godot/src/scenes/auction_house.gd` with the room geometry**

  This script builds the entire room on `_ready()`. All geometry is CSGBox3D/MeshInstance3D created in code.

  ```gdscript
  extends Node3D

  const _UITheme = preload("res://src/scenes/ui_theme.gd")

  # In-world label refs — updated per phase
  var _phase_sign_label: Label3D
  var _pedestal_label: Label3D
  var _timer_label: Label3D
  var _scoreboard_label: Label3D

  # Phase timer for bid countdown
  var _bid_time_left: float = 0.0
  var _bid_counting: bool = false

  # CanvasLayer populated in later tasks
  var _canvas: CanvasLayer

  func _ready() -> void:
      _build_room()
      _setup_canvas()
      _setup_lighting()

  func _build_room() -> void:
      # Floor
      _add_box(Vector3(0, -0.05, 0), Vector3(30, 0.1, 20), Color.html("2a2a2a"))
      # Back wall
      _add_box(Vector3(0, 3, -10), Vector3(30, 6, 0.2), Color.html("1e1e1e"))
      # Front wall
      _add_box(Vector3(0, 3, 10), Vector3(30, 6, 0.2), Color.html("1e1e1e"))
      # Left wall (scoreboard side)
      _add_box(Vector3(-15, 3, 0), Vector3(0.2, 6, 20), Color.html("1e1e1e"))
      # Right wall (phase sign side)
      _add_box(Vector3(15, 3, 0), Vector3(0.2, 6, 20), Color.html("1e1e1e"))
      # Ceiling
      _add_box(Vector3(0, 6.05, 0), Vector3(30, 0.1, 20), Color.html("141414"))

      # Stage platform (back of room, raised 0.5u)
      _add_box(Vector3(0, 0.25, -7), Vector3(14, 0.5, 6), Color.html("3a2a1a"))
      # Podium on stage
      _add_box(Vector3(0, 1.05, -8.5), Vector3(1.5, 1.1, 0.8), Color.html("4a3a2a"))

      # Item pedestal (center of room)
      _add_box(Vector3(0, 0.5, -1), Vector3(1.2, 1.0, 1.2), Color.html("2a3a4a"))
      # Pedestal display label
      _pedestal_label = _make_label3d("WAITING...", Vector3(0, 1.15, -1), 0.06)

      # Scoreboard billboard on left wall
      _add_box(Vector3(-14.8, 3, 0), Vector3(0.1, 3, 8), Color.html("111a11"))
      _scoreboard_label = _make_label3d("SCOREBOARD", Vector3(-14.6, 4.0, 0), 0.05)
      _scoreboard_label.rotation_degrees = Vector3(0, 90, 0)

      # Phase sign on right wall
      _add_box(Vector3(14.8, 4.5, -4), Vector3(0.1, 1.5, 5), Color.html("1a1a11"))
      _phase_sign_label = _make_label3d("NEXT UP", Vector3(14.6, 4.5, -4), 0.07)
      _phase_sign_label.rotation_degrees = Vector3(0, -90, 0)

      # Bid timer chalkboard (right wall, lower)
      _add_box(Vector3(14.8, 2.5, 2), Vector3(0.1, 1.5, 4), Color.html("0a1a0a"))
      _timer_label = _make_label3d("", Vector3(14.6, 2.5, 2), 0.1)
      _timer_label.rotation_degrees = Vector3(0, -90, 0)

      # Spawn point marker (invisible static body — actual spawn positions)
      _add_spawn_points()

  func _add_box(pos: Vector3, size: Vector3, color: Color) -> void:
      var body := StaticBody3D.new()
      body.position = pos
      add_child(body)

      var col := CollisionShape3D.new()
      var box := BoxShape3D.new()
      box.size = size
      col.shape = box
      body.add_child(col)

      var mesh := MeshInstance3D.new()
      var box_mesh := BoxMesh.new()
      box_mesh.size = size
      mesh.mesh = box_mesh
      var mat := StandardMaterial3D.new()
      mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
      mat.albedo_color = color
      mesh.material_override = mat
      body.add_child(mesh)

  func _make_label3d(text: String, pos: Vector3, pixel_size: float) -> Label3D:
      var lbl := Label3D.new()
      lbl.text = text
      lbl.pixel_size = pixel_size
      lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
      lbl.double_sided = true
      lbl.no_depth_test = true
      lbl.modulate = Color.WHITE
      lbl.position = pos
      add_child(lbl)
      return lbl

  func _add_spawn_points() -> void:
      # 8 spawn positions around the center area
      const SPAWNS: Array[Vector3] = [
          Vector3(-4, 0, 4), Vector3(-2, 0, 4), Vector3(0, 0, 4), Vector3(2, 0, 4),
          Vector3(4, 0, 4), Vector3(-3, 0, 6), Vector3(0, 0, 6), Vector3(3, 0, 6),
      ]
      for i in range(SPAWNS.size()):
          var marker := Marker3D.new()
          marker.name = "Spawn%d" % i
          marker.position = SPAWNS[i]
          add_child(marker)

  func _setup_canvas() -> void:
      _canvas = CanvasLayer.new()
      add_child(_canvas)

  func _setup_lighting() -> void:
      var env_node := WorldEnvironment.new()
      var env := Environment.new()
      env.background_mode = Environment.BG_COLOR
      env.background_color = Color.html("080808")
      env.ambient_light_color = Color.html("ffffff")
      env.ambient_light_energy = 0.3
      env_node.environment = env
      add_child(env_node)

      # Overhead fill light
      var fill := DirectionalLight3D.new()
      fill.rotation_degrees = Vector3(-60, 20, 0)
      fill.light_energy = 0.8
      fill.light_color = Color.html("ffe8c0")
      add_child(fill)

      # Cool rim
      var rim := DirectionalLight3D.new()
      rim.rotation_degrees = Vector3(-30, -160, 0)
      rim.light_energy = 0.4
      rim.light_color = Color.html("c0d8ff")
      add_child(rim)

      # Spot on pedestal
      var spot := SpotLight3D.new()
      spot.position = Vector3(0, 5.5, -1)
      spot.rotation_degrees = Vector3(-90, 0, 0)
      spot.light_energy = 1.5
      spot.spot_angle = 20.0
      spot.spot_range = 8.0
      add_child(spot)

  # --- Phase message stubs (filled in Tasks 6–11) ---

  func on_auctioneer_reveal(_artifact: Dictionary, _pitch_duration: int) -> void:
      pass

  func on_start_pitch(_artifact: Dictionary, _pitch_duration: int, _round: int = 1, _total_rounds: int = 5) -> void:
      _phase_sign_label.text = "PITCH PHASE"

  func on_auctioneer_name(_name: String) -> void:
      pass

  func on_open_bidding() -> void:
      _phase_sign_label.text = "BIDDING OPEN"

  func on_show_bid_result(_result: Dictionary) -> void:
      _phase_sign_label.text = "SOLD"

  func on_show_chaos(_chaos: Dictionary) -> void:
      pass

  func on_show_final_scores(_ranking: Array) -> void:
      _phase_sign_label.text = "GRAND REVEAL"
  ```

- [ ] **Step 4: Verify the scene loads**

  In the Godot editor, open `src/scenes/auction_house.tscn`. Press **F6** (Run Current Scene). You should see a dark 3D room with stage, pedestal, and walls. No script errors in the output panel.

- [ ] **Step 5: Test scene routing by starting a game**

  Start the local server (`cd hot-garbage-server && node server.js`), launch two Godot clients, create a room, join, start game. TEMPORARILY: for this task the server still sends `advance_scene: auctioneer_view / bidder_view`, so routing to `auction_house` won't trigger yet. That's fine — verify the scene compiles cleanly. The routing wiring happens in Task 12.

- [ ] **Step 6: Commit**

  ```bash
  git add hot-garbage-godot/src/scenes/auction_house.tscn \
          hot-garbage-godot/src/scenes/auction_house.gd \
          hot-garbage-godot/src/network/network_manager.gd
  git commit -m "feat: 3D auction house room + scene routing skeleton"
  ```

---

## Task 4: LocalPlayer Character

**Files:**
- Create: `hot-garbage-godot/src/characters/local_player.gd`
- Create: `hot-garbage-godot/src/characters/local_player.tscn`
- Modify: `hot-garbage-godot/src/scenes/auction_house.gd`

**Interfaces:**
- Consumes: `NetworkManager.player_names`, `NetworkManager.local_name`, `NetworkTransport.send_position()`
- Produces: `LocalPlayer` scene at `src/characters/local_player.tscn`. Spawned by `auction_house.gd` in `_ready()` at the player's spawn index. Walks with WASD, jumps with Space, sprints with Shift. Sends position at 10 Hz.

- [ ] **Step 1: Add input map setup to `auction_house.gd`**

  The input actions `move_forward`, `move_back`, `move_left`, `move_right`, `jump`, `sprint`, `interact` must exist. Add this static method and call it from `_ready()` of `auction_house.gd`:

  ```gdscript
  func _ready() -> void:
      _ensure_input_map()
      _build_room()
      _setup_canvas()
      _setup_lighting()
      _spawn_local_player()

  static func _ensure_input_map() -> void:
      const ACTIONS: Dictionary = {
          "move_forward": KEY_W,
          "move_back":    KEY_S,
          "move_left":    KEY_A,
          "move_right":   KEY_D,
          "jump":         KEY_SPACE,
          "sprint":       KEY_SHIFT,
          "interact":     KEY_E,
      }
      for action in ACTIONS:
          if InputMap.has_action(action):
              continue
          InputMap.add_action(action)
          var ev := InputEventKey.new()
          ev.physical_keycode = ACTIONS[action]
          InputMap.action_add_event(action, ev)
  ```

- [ ] **Step 2: Create `hot-garbage-godot/src/characters/local_player.tscn`**

  ```
  [gd_scene load_steps=2 format=3]

  [ext_resource type="Script" path="res://src/characters/local_player.gd" id="1"]

  [node name="LocalPlayer" type="CharacterBody3D"]
  script = ExtResource("1")
  ```

- [ ] **Step 3: Create `hot-garbage-godot/src/characters/local_player.gd`**

  ```gdscript
  extends CharacterBody3D

  const SPEED        := 5.0
  const SPRINT_MULT  := 1.8
  const JUMP_VEL     := 5.0
  const GRAVITY      := 9.8
  const SEND_INTERVAL := 0.1   # 10 Hz

  var _camera_arm: SpringArm3D
  var _camera: Camera3D
  var _mesh: MeshInstance3D
  var _name_label: Label3D
  var _crown_mesh: MeshInstance3D
  var _hand_anchor: Node3D
  var _grab_area: Area3D

  var _held_object: RigidBody3D = null
  var _send_timer: float = 0.0
  var _player_name: String = ""
  var _color: Color = Color.WHITE

  const PALETTE: PackedStringArray = [
      "#E74C3C", "#3498DB", "#2ECC71", "#F39C12",
      "#9B59B6", "#1ABC9C", "#E67E22", "#EC407A",
  ]

  func _ready() -> void:
      _player_name = NetworkManager.local_name
      var idx: int = NetworkManager.player_names.find(_player_name)
      _color = Color.html(PALETTE[idx % PALETTE.size()])
      _build_nodes()

  func _build_nodes() -> void:
      # Collision capsule
      var col := CollisionShape3D.new()
      var cap := CapsuleShape3D.new()
      cap.radius = 0.4
      cap.height = 1.8
      col.shape = cap
      col.position = Vector3(0, 0.9, 0)
      add_child(col)

      # Body mesh (capsule placeholder)
      _mesh = MeshInstance3D.new()
      var cap_mesh := CapsuleMesh.new()
      cap_mesh.radius = 0.4
      cap_mesh.height = 1.8
      _mesh.mesh = cap_mesh
      _mesh.position = Vector3(0, 0.9, 0)
      var mat := StandardMaterial3D.new()
      mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
      mat.albedo_color = _color
      _mesh.material_override = mat
      add_child(_mesh)

      # Hand anchor (right hand position for held objects)
      _hand_anchor = Node3D.new()
      _hand_anchor.position = Vector3(0.5, 0.9, -0.7)
      add_child(_hand_anchor)

      # Crown mesh (hidden; shown when this player is auctioneer)
      _crown_mesh = MeshInstance3D.new()
      var crown_box := BoxMesh.new()
      crown_box.size = Vector3(0.6, 0.2, 0.6)
      _crown_mesh.mesh = crown_box
      _crown_mesh.position = Vector3(0, 2.0, 0)
      var crown_mat := StandardMaterial3D.new()
      crown_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
      crown_mat.albedo_color = Color.html("C9A227")
      _crown_mesh.material_override = crown_mat
      _crown_mesh.visible = false
      add_child(_crown_mesh)

      # Name label
      _name_label = Label3D.new()
      _name_label.text = _player_name
      _name_label.pixel_size = 0.012
      _name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
      _name_label.no_depth_test = true
      _name_label.position = Vector3(0, 2.3, 0)
      add_child(_name_label)

      # Camera spring arm (third-person)
      _camera_arm = SpringArm3D.new()
      _camera_arm.position = Vector3(0, 1.6, 0)
      _camera_arm.spring_length = 4.0
      _camera_arm.rotation_degrees = Vector3(-20, 0, 0)
      add_child(_camera_arm)

      _camera = Camera3D.new()
      _camera_arm.add_child(_camera)

      # Grab detection area (sphere in front of player)
      _grab_area = Area3D.new()
      var grab_col := CollisionShape3D.new()
      var sphere := SphereShape3D.new()
      sphere.radius = 1.5
      grab_col.shape = sphere
      _grab_area.add_child(grab_col)
      _grab_area.position = Vector3(0, 0.9, -1.0)
      add_child(_grab_area)

  func _physics_process(delta: float) -> void:
      # Gravity
      if not is_on_floor():
          velocity.y -= GRAVITY * delta

      # WASD input relative to camera facing
      var input := Vector2(
          Input.get_axis("move_left", "move_right"),
          Input.get_axis("move_forward", "move_back")
      )
      var cam_basis := _camera_arm.global_basis
      var dir := (cam_basis.x * input.x - cam_basis.z * input.y).normalized()
      dir.y = 0.0

      var speed := SPEED * (SPRINT_MULT if Input.is_action_pressed("sprint") else 1.0)
      if dir.length() > 0.0:
          velocity.x = dir.x * speed
          velocity.z = dir.z * speed
          rotation.y = atan2(-dir.x, -dir.z)
      else:
          velocity.x = move_toward(velocity.x, 0, speed * 6.0 * delta)
          velocity.z = move_toward(velocity.z, 0, speed * 6.0 * delta)

      # Jump
      if Input.is_action_just_pressed("jump") and is_on_floor():
          velocity.y = JUMP_VEL

      # Camera rotation (mouse look — horizontal only for third-person)
      var mouse_delta := Input.get_last_mouse_velocity() * 0.0002
      _camera_arm.rotation.y -= mouse_delta.x
      _camera_arm.rotation.x = clamp(_camera_arm.rotation.x - mouse_delta.y, -1.2, 0.3)

      move_and_slide()

      # Interact (grab / throw)
      if Input.is_action_just_pressed("interact"):
          if _held_object:
              _throw()
          else:
              _try_grab()

      # Network position send at 10 Hz
      _send_timer += delta
      if _send_timer >= SEND_INTERVAL:
          _send_timer = 0.0
          var anim := "idle"
          if _held_object:
              anim = "hold"
          elif velocity.length() > 0.5:
              anim = "run"
          NetworkTransport.send_position(global_position, rotation.y, anim)

  func _try_grab() -> void:
      var bodies := _grab_area.get_overlapping_bodies()
      var nearest: RigidBody3D = null
      var nearest_dist := INF
      for body in bodies:
          if body is RigidBody3D and body.is_in_group("interactable"):
              var d := global_position.distance_to(body.global_position)
              if d < nearest_dist:
                  nearest_dist = d
                  nearest = body
      if nearest:
          _held_object = nearest
          nearest.freeze = true
          nearest.reparent(_hand_anchor, true)
          nearest.position = Vector3.ZERO

  func _throw() -> void:
      if not _held_object:
          return
      var obj := _held_object
      _held_object = null
      obj.reparent(get_parent(), true)
      obj.freeze = false
      var throw_dir := -_camera_arm.global_basis.z.normalized()
      obj.linear_velocity = throw_dir * 12.0 + Vector3(0, 4.0, 0)

  func set_crown_visible(v: bool) -> void:
      _crown_mesh.visible = v
  ```

- [ ] **Step 4: Spawn local player in `auction_house.gd`**

  Add this method and call it from `_ready()` (already wired in Task 3 Step 1):

  ```gdscript
  const LocalPlayerScene = preload("res://src/characters/local_player.tscn")

  var _local_player: CharacterBody3D = null

  func _spawn_local_player() -> void:
      _local_player = LocalPlayerScene.instantiate()
      add_child(_local_player)
      # Place at spawn index based on player order
      var idx: int = NetworkManager.player_names.find(NetworkManager.local_name)
      idx = max(idx, 0)
      var spawn := get_node_or_null("Spawn%d" % idx)
      if spawn:
          _local_player.position = spawn.position
      else:
          _local_player.position = Vector3(0, 0, 5)
      # Capture mouse for camera look
      Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
  ```

  Also add Escape to release mouse — add this to `auction_house.gd`:

  ```gdscript
  func _unhandled_key_input(event: InputEvent) -> void:
      if event.is_action_pressed("ui_cancel"):
          if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
              Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
          else:
              Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
  ```

- [ ] **Step 5: Verify**

  Press **F5** (Run Project), create a room, start a game (the server still sends old advance_scene keys, so you'll land in the old 2D view). To test LocalPlayer directly, temporarily set `run/main_scene` in project.godot to `res://src/scenes/auction_house.tscn`, run, confirm: character spawns, WASD moves, mouse rotates camera, Space jumps. Revert the main scene.

- [ ] **Step 6: Commit**

  ```bash
  git add hot-garbage-godot/src/characters/local_player.gd \
          hot-garbage-godot/src/characters/local_player.tscn \
          hot-garbage-godot/src/scenes/auction_house.gd
  git commit -m "feat: LocalPlayer — WASD movement, spring arm camera, 10Hz position send"
  ```

---

## Task 5: RemotePlayer + Position Sync

**Files:**
- Create: `hot-garbage-godot/src/characters/remote_player.gd`
- Create: `hot-garbage-godot/src/characters/remote_player.tscn`
- Modify: `hot-garbage-godot/src/scenes/auction_house.gd`

**Interfaces:**
- Consumes: `NetworkManager.player_moved` signal, `NetworkManager.player_registered` signal, `NetworkManager.player_disconnected` signal
- Produces: `RemotePlayer` scenes spawned per remote player, lerp toward received positions at factor 0.25/frame.

- [ ] **Step 1: Create `hot-garbage-godot/src/characters/remote_player.tscn`**

  ```
  [gd_scene load_steps=2 format=3]

  [ext_resource type="Script" path="res://src/characters/remote_player.gd" id="1"]

  [node name="RemotePlayer" type="Node3D"]
  script = ExtResource("1")
  ```

- [ ] **Step 2: Create `hot-garbage-godot/src/characters/remote_player.gd`**

  ```gdscript
  extends Node3D

  const PALETTE: PackedStringArray = [
      "#E74C3C", "#3498DB", "#2ECC71", "#F39C12",
      "#9B59B6", "#1ABC9C", "#E67E22", "#EC407A",
  ]

  var _mesh: MeshInstance3D
  var _name_label: Label3D
  var _crown_mesh: MeshInstance3D

  var _target_pos: Vector3 = Vector3.ZERO
  var _target_ry: float = 0.0
  var _player_name: String = ""

  func init(p_name: String) -> void:
      _player_name = p_name

  func _ready() -> void:
      var idx: int = NetworkManager.player_names.find(_player_name)
      var color := Color.html(PALETTE[idx % PALETTE.size()])

      # Body mesh
      _mesh = MeshInstance3D.new()
      var cap_mesh := CapsuleMesh.new()
      cap_mesh.radius = 0.4
      cap_mesh.height = 1.8
      _mesh.mesh = cap_mesh
      _mesh.position = Vector3(0, 0.9, 0)
      var mat := StandardMaterial3D.new()
      mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
      mat.albedo_color = color
      _mesh.material_override = mat
      add_child(_mesh)

      # Crown
      _crown_mesh = MeshInstance3D.new()
      var crown_box := BoxMesh.new()
      crown_box.size = Vector3(0.6, 0.2, 0.6)
      _crown_mesh.mesh = crown_box
      _crown_mesh.position = Vector3(0, 2.0, 0)
      var crown_mat := StandardMaterial3D.new()
      crown_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
      crown_mat.albedo_color = Color.html("C9A227")
      _crown_mesh.material_override = crown_mat
      _crown_mesh.visible = false
      add_child(_crown_mesh)

      # Name label
      _name_label = Label3D.new()
      _name_label.text = _player_name
      _name_label.pixel_size = 0.012
      _name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
      _name_label.no_depth_test = true
      _name_label.position = Vector3(0, 2.3, 0)
      add_child(_name_label)

  func apply_move(x: float, y: float, z: float, ry: float, _anim: String) -> void:
      _target_pos = Vector3(x, y, z)
      _target_ry = ry

  func _physics_process(_delta: float) -> void:
      global_position = global_position.lerp(_target_pos, 0.25)
      rotation.y = lerp_angle(rotation.y, _target_ry, 0.25)

  func set_crown_visible(v: bool) -> void:
      _crown_mesh.visible = v
  ```

- [ ] **Step 3: Wire remote players into `auction_house.gd`**

  Add at the top of `auction_house.gd`:

  ```gdscript
  const RemotePlayerScene = preload("res://src/characters/remote_player.tscn")

  # player_name → RemotePlayer node
  var _remote_players: Dictionary = {}
  ```

  Add this method and call it from `_ready()` after `_spawn_local_player()`:

  ```gdscript
  func _connect_player_signals() -> void:
      NetworkManager.player_registered.connect(_on_player_registered)
      NetworkManager.player_disconnected.connect(_on_player_disconnected)
      NetworkManager.player_moved.connect(_on_player_moved)
      # Spawn RemotePlayers for players already in the room
      for p_name in NetworkManager.player_names:
          if p_name != NetworkManager.local_name:
              _spawn_remote_player(p_name)

  func _on_player_registered(p_name: String) -> void:
      if p_name != NetworkManager.local_name and not _remote_players.has(p_name):
          _spawn_remote_player(p_name)

  func _on_player_disconnected(p_name: String) -> void:
      if _remote_players.has(p_name):
          _remote_players[p_name].queue_free()
          _remote_players.erase(p_name)

  func _on_player_moved(p_name: String, x: float, y: float, z: float, ry: float, anim: String) -> void:
      if not _remote_players.has(p_name):
          _spawn_remote_player(p_name)
      _remote_players[p_name].apply_move(x, y, z, ry, anim)

  func _spawn_remote_player(p_name: String) -> void:
      var rp: Node3D = RemotePlayerScene.instantiate()
      rp.init(p_name)
      add_child(rp)
      # Tentative start position
      rp.position = Vector3(0, 0, 5)
      _remote_players[p_name] = rp
  ```

  Update `_ready()` to call `_connect_player_signals()`:

  ```gdscript
  func _ready() -> void:
      _ensure_input_map()
      _build_room()
      _setup_canvas()
      _setup_lighting()
      _spawn_local_player()
      _connect_player_signals()
  ```

- [ ] **Step 4: Wire `on_auctioneer_name` to show/hide crowns**

  Replace the stub in `auction_house.gd`:

  ```gdscript
  func on_auctioneer_name(p_name: String) -> void:
      if _local_player:
          _local_player.set_crown_visible(NetworkManager.local_name == p_name)
      for name in _remote_players:
          _remote_players[name].set_crown_visible(name == p_name)
  ```

- [ ] **Step 5: Verify with two clients**

  Start local server. Open two Godot editor windows (or export one client and run it). Player A creates room, Player B joins, host starts game — once `auction_house` scene routing is enabled in Task 12 you'll see both players. For now: test manually by temporarily setting main_scene to auction_house.tscn, running two instances, and confirming remote player capsules appear and move.

- [ ] **Step 6: Commit**

  ```bash
  git add hot-garbage-godot/src/characters/remote_player.gd \
          hot-garbage-godot/src/characters/remote_player.tscn \
          hot-garbage-godot/src/scenes/auction_house.gd
  git commit -m "feat: RemotePlayer with lerp interpolation + position sync wiring"
  ```

---

## Task 6: Physics Props + Auction Item

**Files:**
- Create: `hot-garbage-godot/src/props/throwable_prop.gd`
- Modify: `hot-garbage-godot/src/scenes/auction_house.gd`

**Interfaces:**
- Produces: `ThrowableProp` RigidBody3D nodes in group `interactable`. Chairs, crates, and trinkets scattered in the room. Auction item prop spawned per `on_start_pitch`, reset to pedestal on `on_open_bidding`.

- [ ] **Step 1: Create `hot-garbage-godot/src/props/throwable_prop.gd`**

  ```gdscript
  extends RigidBody3D

  const _UITheme = preload("res://src/scenes/ui_theme.gd")

  enum Shape { BOX, CAPSULE, SPHERE }

  var _home_pos: Vector3 = Vector3.ZERO
  var _is_auction_item: bool = false
  var _mesh_instance: MeshInstance3D = null

  func init(pos: Vector3, size: Vector3, color: Color, shape: Shape = Shape.BOX, p_is_auction_item: bool = false) -> void:
      _home_pos = pos
      _is_auction_item = p_is_auction_item
      position = pos
      add_to_group("interactable")

      var col := CollisionShape3D.new()
      match shape:
          Shape.BOX:
              var box := BoxShape3D.new()
              box.size = size
              col.shape = box
          Shape.CAPSULE:
              var cap := CapsuleShape3D.new()
              cap.radius = size.x
              cap.height = size.y
              col.shape = cap
          Shape.SPHERE:
              var sphere := SphereShape3D.new()
              sphere.radius = size.x
              col.shape = sphere
      add_child(col)

      var mesh := MeshInstance3D.new()
      match shape:
          Shape.BOX:
              var box_mesh := BoxMesh.new()
              box_mesh.size = size
              mesh.mesh = box_mesh
          Shape.CAPSULE:
              var cap_mesh := CapsuleMesh.new()
              cap_mesh.radius = size.x
              cap_mesh.height = size.y
              mesh.mesh = cap_mesh
          Shape.SPHERE:
              var sphere_mesh := SphereMesh.new()
              sphere_mesh.radius = size.x
              sphere_mesh.height = size.x * 2
              mesh.mesh = sphere_mesh
      var mat := StandardMaterial3D.new()
      mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
      mat.albedo_color = color
      mesh.material_override = mat
      add_child(mesh)
      _mesh_instance = mesh

  func set_color(c: Color) -> void:
      if _mesh_instance == null:
          return
      var mat := StandardMaterial3D.new()
      mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
      mat.albedo_color = c
      _mesh_instance.material_override = mat

  func reset_to_home() -> void:
      freeze = false
      linear_velocity = Vector3.ZERO
      angular_velocity = Vector3.ZERO
      position = _home_pos
      rotation = Vector3.ZERO

  func lock_to_pedestal() -> void:
      freeze = true
      position = _home_pos
      rotation = Vector3.ZERO
      if get_parent() != get_tree().get_root().get_child(-1):
          # Re-parent to scene root if it was grabbed
          pass

  func set_interactable(v: bool) -> void:
      if v:
          add_to_group("interactable")
      else:
          remove_from_group("interactable")
  ```

- [ ] **Step 2: Scatter decorative props and track auction item in `auction_house.gd`**

  Add at the top:

  ```gdscript
  const ThrowablePropScript = preload("res://src/props/throwable_prop.gd")

  var _auction_item: RigidBody3D = null
  ```

  Add a `_spawn_props()` method and call it from `_ready()` before `_spawn_local_player()`:

  ```gdscript
  func _spawn_props() -> void:
      # Chairs (6) — left side of room
      var chair_positions: Array[Vector3] = [
          Vector3(-8, 0, 0), Vector3(-6, 0, 0), Vector3(-4, 0, 0),
          Vector3(-8, 0, 2), Vector3(-6, 0, 2), Vector3(-4, 0, 2),
      ]
      for pos in chair_positions:
          _make_prop(pos, Vector3(0.7, 1.2, 0.7), Color.html("5a3a2a"))

      # Crates (4) — right side
      var crate_positions: Array[Vector3] = [
          Vector3(6, 0, 0), Vector3(8, 0, 0),
          Vector3(6, 0, 2), Vector3(8, 0, 2),
      ]
      for pos in crate_positions:
          _make_prop(pos, Vector3(0.9, 0.9, 0.9), Color.html("4a3a1a"))

      # Trinkets (8) — scattered
      var trinket_positions: Array[Vector3] = [
          Vector3(-10, 0, -3), Vector3(-10, 0, -1), Vector3(10, 0, -3), Vector3(10, 0, -1),
          Vector3(-3, 0, -3), Vector3(3, 0, -3), Vector3(-5, 0, 1), Vector3(5, 0, 1),
      ]
      for pos in trinket_positions:
          _make_prop(pos, Vector3(0.3, 0.3, 0.3), Color.html("6a6a9a"), ThrowablePropScript.Shape.SPHERE)

  func _make_prop(pos: Vector3, size: Vector3, color: Color,
                  shape: int = ThrowablePropScript.Shape.BOX) -> RigidBody3D:
      var prop: RigidBody3D = RigidBody3D.new()
      prop.set_script(ThrowablePropScript)
      add_child(prop)
      prop.init(pos, size, color, shape)
      return prop
  ```

  Update `_ready()` to call `_spawn_props()`:

  ```gdscript
  func _ready() -> void:
      _ensure_input_map()
      _build_room()
      _spawn_props()
      _setup_canvas()
      _setup_lighting()
      _spawn_local_player()
      _connect_player_signals()
  ```

- [ ] **Step 3: Spawn / update auction item per pitch in `auction_house.gd`**

  Replace the `on_start_pitch` stub:

  ```gdscript
  func on_start_pitch(artifact: Dictionary, _pitch_duration: int, round: int = 1, total_rounds: int = 5) -> void:
      _phase_sign_label.text = "PITCH PHASE\nROUND %d/%d" % [round, total_rounds]
      var cat: String = artifact.get("category", "unknown")
      var cat_color: Color = _UITheme.cat_color(cat)

      # Spawn or reset auction item on pedestal
      if _auction_item == null:
          _auction_item = _make_prop(Vector3(0, 1.2, -1), Vector3(0.4, 0.4, 0.4), cat_color, ThrowablePropScript.Shape.BOX)
      else:
          _auction_item.set_color(cat_color)
          _auction_item.reset_to_home()

      _auction_item.set_interactable(true)
      _pedestal_label.text = "%s\n[%s]" % [artifact.get("name", ""), cat.to_upper()]

  func on_open_bidding() -> void:
      _phase_sign_label.text = "BIDDING OPEN"
      if _auction_item:
          _auction_item.set_interactable(false)
          _auction_item.lock_to_pedestal()
  ```

- [ ] **Step 4: Verify**

  Run the scene directly. Confirm chairs, crates, and trinkets spawn. Grab a chair with E, throw it. The auction item prop spawning will be testable after Task 12 wires the server messages.

- [ ] **Step 5: Commit**

  ```bash
  git add hot-garbage-godot/src/props/throwable_prop.gd \
          hot-garbage-godot/src/scenes/auction_house.gd
  git commit -m "feat: throwable props + auction item on pedestal"
  ```

---

## Task 7: HUD Overlay + Phase State Machine

**Files:**
- Create: `hot-garbage-godot/src/ui/hud_overlay.gd`
- Modify: `hot-garbage-godot/src/scenes/auction_house.gd`

**Interfaces:**
- Consumes: `GameServer.player_cash`, `GameServer.player_artifacts`, `NetworkManager.local_name`; `sync_player_state` already updates these via `GameServer.receive_player_state()`
- Produces: persistent top-left HUD strip showing cash, round counter, collection pips. Refreshes when `GameServer.receive_player_state` calls `call_group("hud_nodes", "refresh")`.

- [ ] **Step 1: Create `hot-garbage-godot/src/ui/hud_overlay.gd`**

  This is a `CanvasLayer` child, not a full scene. It's instantiated directly in `auction_house.gd`.

  ```gdscript
  extends Control

  const _UITheme = preload("res://src/scenes/ui_theme.gd")

  var _cash_label: Label
  var _round_label: Label
  var _collection_vbox: VBoxContainer

  func _ready() -> void:
      add_to_group("hud_nodes")
      set_anchors_preset(Control.PRESET_TOP_LEFT)
      custom_minimum_size = Vector2(200, 300)

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

      _round_label = Label.new()
      _round_label.text = ""
      _UITheme.style_label(_round_label, _UITheme.FS_LABEL, _UITheme.DIM)
      vbox.add_child(_round_label)

      var col_lbl := Label.new()
      col_lbl.text = "COLLECTION"
      _UITheme.style_section_label(col_lbl)
      vbox.add_child(col_lbl)

      _collection_vbox = VBoxContainer.new()
      _collection_vbox.add_theme_constant_override("separation", 4)
      vbox.add_child(_collection_vbox)

      refresh()

  func refresh() -> void:
      var own_id: String = NetworkManager.local_name
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
          row.text = "■ %s ×%d" % [cat.capitalize(), by_cat[cat]]
          _UITheme.style_label(row, _UITheme.FS_LABEL, _UITheme.cat_color(cat))
          row.autowrap_mode = TextServer.AUTOWRAP_OFF
          _collection_vbox.add_child(row)

  func set_round(round: int, total: int) -> void:
      _round_label.text = "ROUND %d / %d" % [round, total]
  ```

- [ ] **Step 2: Instantiate HUD in `auction_house.gd`**

  Add at the top:

  ```gdscript
  const HUDOverlayScript = preload("res://src/ui/hud_overlay.gd")
  var _hud: Control = null
  ```

  In `_setup_canvas()`:

  ```gdscript
  func _setup_canvas() -> void:
      _canvas = CanvasLayer.new()
      add_child(_canvas)

      _hud = HUDOverlayScript.new()
      _canvas.add_child(_hud)
  ```

- [ ] **Step 3: Wire `on_start_pitch` to update round label**

  In the `on_start_pitch` method, after setting the phase sign, add:

  ```gdscript
  if _hud:
      _hud.set_round(round, total_rounds)
  ```

- [ ] **Step 4: Add bid countdown to `_process` in `auction_house.gd`**

  Add:

  ```gdscript
  func _process(delta: float) -> void:
      if _bid_counting:
          _bid_time_left -= delta
          if _bid_time_left < 0.0:
              _bid_time_left = 0.0
              _bid_counting = false
          var secs: int = int(ceil(_bid_time_left))
          _timer_label.text = "%d" % secs if secs > 0 else ""
  ```

  Update `on_open_bidding` to start the countdown. The bid timeout is whatever the server config says; we don't know it exactly on the client, so we read it from the server's `open_bidding` message. Update the server to include `bidTimeout` in `open_bidding`:

  In `hot-garbage-server/game_session.js`, update `_openBidding`:

  ```js
  _openBidding() {
    if (this._biddingOpen) return;
    this._biddingOpen = true;
    const timeout = this._config.bidTimeout ?? 30;
    this._send(null, { type: 'open_bidding', bidTimeout: timeout });
    if (timeout > 0) {
      setTimeout(() => {
        if (this._biddingOpen && !this._pendingResolve) this._resolveAuction();
      }, timeout * 1000);
    }
  }
  ```

  In `network_manager.gd`, update the `open_bidding` dispatch to pass `bidTimeout`:

  ```gdscript
  "open_bidding":
      get_tree().get_root().propagate_call("on_open_bidding",
          [msg.get("bidTimeout", 30)], true)
  ```

  This means all scenes implementing `on_open_bidding` need to accept the new param. Update existing ones:

  In `bidder_view.gd` line 196:
  ```gdscript
  func on_open_bidding(_bid_timeout: float = 30.0) -> void:
  ```

  In `auctioneer_view.gd` line 188:
  ```gdscript
  func on_open_bidding(_bid_timeout: float = 30.0) -> void:
  ```

  In `bid_reveal.gd` there is no `on_open_bidding` — nothing to change.

  Update `auction_house.gd` `on_open_bidding`:

  ```gdscript
  func on_open_bidding(bid_timeout: float = 30.0) -> void:
      _phase_sign_label.text = "BIDDING OPEN"
      _bid_time_left = bid_timeout
      _bid_counting = true
      if _auction_item:
          _auction_item.set_interactable(false)
          _auction_item.lock_to_pedestal()
  ```

- [ ] **Step 5: Run the server tests to confirm new open_bidding field doesn't break anything**

  ```bash
  cd hot-garbage-server && node --test test/game_session.test.js
  ```

  Expected: all tests pass. The `bidTimeout` field is additive and backward-compatible.

- [ ] **Step 6: Verify HUD manually**

  Temporarily point main scene at auction_house.tscn, run, confirm HUD appears top-left with "YOU" / "§0" / "ROUND —". After Task 12 wires the game, `sync_player_state` will update the cash.

- [ ] **Step 7: Commit**

  ```bash
  git add hot-garbage-godot/src/ui/hud_overlay.gd \
          hot-garbage-godot/src/scenes/auction_house.gd \
          hot-garbage-godot/src/scenes/bidder_view.gd \
          hot-garbage-godot/src/scenes/auctioneer_view.gd \
          hot-garbage-server/game_session.js
  git commit -m "feat: HUD overlay + bid countdown timer + open_bidding includes bidTimeout"
  ```

---

## Task 8: Auctioneer Overlay

**Files:**
- Create: `hot-garbage-godot/src/ui/auctioneer_overlay.gd`
- Modify: `hot-garbage-godot/src/scenes/auction_house.gd`

**Interfaces:**
- Consumes: `on_auctioneer_reveal(artifact, pitch_duration)` — shown only to the auctioneer. Hidden on `on_show_bid_result`.
- Produces: top-center banner showing `TRUE VALUE: §N` and `CATEGORY: X` with gold border.

- [ ] **Step 1: Create `hot-garbage-godot/src/ui/auctioneer_overlay.gd`**

  ```gdscript
  extends Control

  const _UITheme = preload("res://src/scenes/ui_theme.gd")

  var _value_label: Label
  var _cat_label: Label

  func _ready() -> void:
      visible = false
      set_anchors_preset(Control.PRESET_TOP_WIDE)
      custom_minimum_size = Vector2(0, 80)

      var panel := PanelContainer.new()
      panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
      var style := _UITheme.make_panel(_UITheme.SURFACE, _UITheme.GOLD)
      panel.add_theme_stylebox_override("panel", style)
      add_child(panel)

      var vbox := VBoxContainer.new()
      vbox.add_theme_constant_override("separation", 4)
      panel.add_child(vbox)

      _value_label = Label.new()
      _value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _UITheme.style_label(_value_label, _UITheme.FS_VALUE, _UITheme.GOLD)
      vbox.add_child(_value_label)

      _cat_label = Label.new()
      _cat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _UITheme.style_label(_cat_label, _UITheme.FS_LABEL, _UITheme.DIM)
      vbox.add_child(_cat_label)

  func show_reveal(artifact: Dictionary) -> void:
      _value_label.text = "TRUE VALUE: §%d" % artifact.get("value", 0)
      var cat: String = artifact.get("category", "")
      _cat_label.text = "CATEGORY: %s" % cat.to_upper()
      visible = true

  func hide_reveal() -> void:
      visible = false
  ```

- [ ] **Step 2: Add auctioneer overlay to `auction_house.gd`**

  ```gdscript
  const AuctioneerOverlayScript = preload("res://src/ui/auctioneer_overlay.gd")
  var _auctioneer_overlay: Control = null
  ```

  In `_setup_canvas()`, after adding `_hud`:

  ```gdscript
  _auctioneer_overlay = AuctioneerOverlayScript.new()
  _canvas.add_child(_auctioneer_overlay)
  ```

  Replace the `on_auctioneer_reveal` stub:

  ```gdscript
  func on_auctioneer_reveal(artifact: Dictionary, _pitch_duration: int) -> void:
      if _auctioneer_overlay:
          _auctioneer_overlay.show_reveal(artifact)
  ```

  In `on_show_bid_result`, hide it:

  ```gdscript
  func on_show_bid_result(result: Dictionary) -> void:
      _phase_sign_label.text = "SOLD"
      if _auctioneer_overlay:
          _auctioneer_overlay.hide_reveal()
  ```

- [ ] **Step 3: Verify**

  After Task 12 is complete the auctioneer will see the overlay during pitch. For now: manually call `_auctioneer_overlay.show_reveal({"value": 500, "category": "antiquities"})` from a debugger breakpoint or test code to confirm the banner appears top-center.

- [ ] **Step 4: Commit**

  ```bash
  git add hot-garbage-godot/src/ui/auctioneer_overlay.gd \
          hot-garbage-godot/src/scenes/auction_house.gd
  git commit -m "feat: auctioneer overlay — true value + category banner"
  ```

---

## Task 9: Bid Panel

**Files:**
- Create: `hot-garbage-godot/src/ui/bid_panel.gd`
- Modify: `hot-garbage-godot/src/scenes/auction_house.gd`

**Interfaces:**
- Consumes: `on_open_bidding(bid_timeout)` to show; `on_show_bid_result` to hide. Calls `NetworkTransport.send_bid(amount)` on submit.
- Produces: bottom-center panel with SpinBox, SUBMIT BID button, countdown label. Auto-submits §0 when countdown hits 0.

- [ ] **Step 1: Create `hot-garbage-godot/src/ui/bid_panel.gd`**

  ```gdscript
  extends Control

  const _UITheme = preload("res://src/scenes/ui_theme.gd")

  var _item_label: Label
  var _cash_label: Label
  var _bid_input: SpinBox
  var _submit_btn: Button
  var _status_label: Label
  var _countdown_label: Label

  var _time_left: float = 0.0
  var _counting: bool = false
  var _submitted: bool = false

  func _ready() -> void:
      visible = false
      set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
      custom_minimum_size = Vector2(0, 200)

      var panel := PanelContainer.new()
      panel.custom_minimum_size = Vector2(600, 0)
      _UITheme.add_center_container(self).add_child(panel)
      panel.add_theme_stylebox_override("panel", _UITheme.make_panel())

      var vbox := VBoxContainer.new()
      vbox.add_theme_constant_override("separation", _UITheme.GAP)
      panel.add_child(vbox)

      _item_label = Label.new()
      _item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _UITheme.style_label(_item_label, _UITheme.FS_BODY, _UITheme.DIM)
      vbox.add_child(_item_label)

      _cash_label = Label.new()
      _cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _UITheme.style_label(_cash_label, _UITheme.FS_LABEL, _UITheme.GOLD)
      vbox.add_child(_cash_label)

      var bid_row := HBoxContainer.new()
      bid_row.add_theme_constant_override("separation", _UITheme.GAP)
      bid_row.alignment = BoxContainer.ALIGNMENT_CENTER
      vbox.add_child(bid_row)

      var lbl := Label.new()
      lbl.text = "Your bid: §"
      _UITheme.style_label(lbl, _UITheme.FS_BODY, _UITheme.DIM)
      bid_row.add_child(lbl)

      _bid_input = SpinBox.new()
      _bid_input.min_value = 0
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
      _UITheme.style_label(_status_label, _UITheme.FS_LABEL, _UITheme.DIM)
      vbox.add_child(_status_label)

      _countdown_label = Label.new()
      _countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _UITheme.style_label(_countdown_label, _UITheme.FS_TIMER, _UITheme.TEXT)
      vbox.add_child(_countdown_label)

  func open_for_bidding(artifact: Dictionary, bid_timeout: float, player_cash: int) -> void:
      _item_label.text = "%s  [%s]" % [artifact.get("name", ""), artifact.get("category", "unknown").to_upper()]
      _cash_label.text = "Your cash: §%d" % player_cash
      _bid_input.max_value = player_cash
      _bid_input.value = 0
      _bid_input.editable = true
      _submit_btn.disabled = false
      _status_label.text = ""
      _submitted = false
      _time_left = bid_timeout
      _counting = true
      visible = true
      AudioManager.play_open()

  func close() -> void:
      visible = false
      _counting = false

  func _on_submit_pressed() -> void:
      if _submitted:
          return
      _submitted = true
      _submit_btn.disabled = true
      _bid_input.editable = false
      _status_label.text = "Bid submitted. Waiting..."
      NetworkTransport.send_bid(int(_bid_input.value))
      AudioManager.play_bid()

  func _process(delta: float) -> void:
      if not _counting:
          return
      _time_left -= delta
      if _time_left <= 0.0:
          _time_left = 0.0
          _counting = false
          _countdown_label.text = "0"
          if not _submitted:
              _on_submit_pressed()   # auto-submit §0
          return
      var secs: int = int(ceil(_time_left))
      _countdown_label.text = "%d" % secs
  ```

- [ ] **Step 2: Add bid panel to `auction_house.gd`**

  ```gdscript
  const BidPanelScript = preload("res://src/ui/bid_panel.gd")
  var _bid_panel: Control = null
  var _current_artifact: Dictionary = {}
  ```

  In `_setup_canvas()`:

  ```gdscript
  _bid_panel = BidPanelScript.new()
  _canvas.add_child(_bid_panel)
  ```

  Update `on_start_pitch` to save the artifact:

  ```gdscript
  func on_start_pitch(artifact: Dictionary, _pitch_duration: int, round: int = 1, total_rounds: int = 5) -> void:
      _current_artifact = artifact
      _phase_sign_label.text = "PITCH PHASE\nROUND %d/%d" % [round, total_rounds]
      # ... rest of method unchanged
      if _hud:
          _hud.set_round(round, total_rounds)
  ```

  Update `on_open_bidding`:

  ```gdscript
  func on_open_bidding(bid_timeout: float = 30.0) -> void:
      _phase_sign_label.text = "BIDDING OPEN"
      _bid_time_left = bid_timeout
      _bid_counting = true
      if _auction_item:
          _auction_item.set_interactable(false)
          _auction_item.lock_to_pedestal()
      # Show bid panel only for bidders (not the auctioneer)
      if _bid_panel and not _is_auctioneer:
          var own_cash: int = GameServer.player_cash.get(NetworkManager.local_name, 0)
          _bid_panel.open_for_bidding(_current_artifact, bid_timeout, own_cash)

  func on_show_bid_result(result: Dictionary) -> void:
      _phase_sign_label.text = "SOLD"
      if _auctioneer_overlay:
          _auctioneer_overlay.hide_reveal()
      if _bid_panel:
          _bid_panel.close()
  ```

  Add `_is_auctioneer` tracking:

  ```gdscript
  var _is_auctioneer: bool = false

  func on_auctioneer_name(p_name: String) -> void:
      _is_auctioneer = (p_name == NetworkManager.local_name)
      if _local_player:
          _local_player.set_crown_visible(_is_auctioneer)
      for name in _remote_players:
          _remote_players[name].set_crown_visible(name == p_name)
  ```

- [ ] **Step 3: Verify**

  Temporarily set main scene to auction_house.tscn. In Godot debugger, call `_bid_panel.open_for_bidding({"name": "Vase", "category": "antiquities"}, 15.0, 1200)` from the Remote tab. Confirm panel slides in bottom-center, countdown ticks, SUBMIT BID enables. After 15 seconds confirm auto-submit fires.

- [ ] **Step 4: Commit**

  ```bash
  git add hot-garbage-godot/src/ui/bid_panel.gd \
          hot-garbage-godot/src/scenes/auction_house.gd
  git commit -m "feat: bid panel — SpinBox, countdown, auto-submit on timeout"
  ```

---

## Task 10: Bid Reveal Overlay + Chaos Card

**Files:**
- Create: `hot-garbage-godot/src/ui/bid_reveal_overlay.gd`
- Create: `hot-garbage-godot/src/ui/chaos_card.gd`
- Modify: `hot-garbage-godot/src/scenes/auction_house.gd`

**Interfaces:**
- Consumes: `on_show_bid_result(result)` → shows SOLD card 3s then auto-hides. `on_show_chaos(chaos)` → slides in chaos card for 4s.
- Produces: full-screen SOLD card with winner + price. Gold `CPUParticles3D` burst on winner's character. Chaos slide-in card on right.

- [ ] **Step 1: Create `hot-garbage-godot/src/ui/bid_reveal_overlay.gd`**

  ```gdscript
  extends Control

  const _UITheme = preload("res://src/scenes/ui_theme.gd")

  var _header: Label
  var _result_label: Label

  func _ready() -> void:
      visible = false
      set_anchors_preset(Control.PRESET_FULL_RECT)
      modulate.a = 0.0

      var bg := ColorRect.new()
      bg.color = Color(0, 0, 0, 0.7)
      bg.set_anchors_preset(Control.PRESET_FULL_RECT)
      add_child(bg)

      var vbox := VBoxContainer.new()
      vbox.custom_minimum_size = Vector2(700, 200)
      vbox.add_theme_constant_override("separation", _UITheme.GAP * 2)
      _UITheme.add_center_container(self).add_child(vbox)

      _header = Label.new()
      _header.text = "SOLD"
      _header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _UITheme.style_label(_header, 64, _UITheme.GOLD)
      vbox.add_child(_header)

      _result_label = Label.new()
      _result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
      _UITheme.style_label(_result_label, _UITheme.FS_ARTIFACT, _UITheme.TEXT)
      vbox.add_child(_result_label)

  func show_result(result: Dictionary) -> void:
      if result.winner == "BANK":
          _result_label.text = "No takers.\nBank paid §%d." % result.price
      else:
          _result_label.text = "%s\nwon for §%d!" % [result.winner, result.price]
      visible = true
      var tw := create_tween()
      tw.tween_property(self, "modulate:a", 1.0, 0.3)
      tw.tween_interval(2.5)
      tw.tween_property(self, "modulate:a", 0.0, 0.3)
      tw.tween_callback(func(): visible = false)
      AudioManager.play_resolve()
  ```

- [ ] **Step 2: Create `hot-garbage-godot/src/ui/chaos_card.gd`**

  ```gdscript
  extends Control

  const _UITheme = preload("res://src/scenes/ui_theme.gd")

  var _text_label: Label

  func _ready() -> void:
      visible = false
      set_anchors_preset(Control.PRESET_RIGHT_WIDE)
      custom_minimum_size = Vector2(320, 200)
      offset_left = -340
      offset_right = 0

      var panel := PanelContainer.new()
      panel.set_anchors_preset(Control.PRESET_FULL_RECT)
      panel.add_theme_stylebox_override("panel", _UITheme.make_panel(_UITheme.SURFACE, _UITheme.GOLD))
      add_child(panel)

      var vbox := VBoxContainer.new()
      vbox.add_theme_constant_override("separation", _UITheme.GAP)
      panel.add_child(vbox)

      var header := Label.new()
      header.text = "CHAOS!"
      header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _UITheme.style_label(header, _UITheme.FS_ARTIFACT, _UITheme.GOLD)
      vbox.add_child(header)

      _text_label = Label.new()
      _text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
      _UITheme.style_label(_text_label, _UITheme.FS_BODY, _UITheme.TEXT)
      vbox.add_child(_text_label)

  func show_chaos(chaos: Dictionary) -> void:
      var kind: String = chaos.get("type", "")
      var text: String = chaos.get("text", "")
      if kind == "appraiser":
          _text_label.text = "APPRAISER:\n%s" % text
      else:
          _text_label.text = "EVENT:\n%s" % text
          var extra: Dictionary = chaos.get("extra", {})
          if extra.has("victim") and extra.has("lostName"):
              _text_label.text += "\n%s loses \"%s\"!" % [extra.victim, extra.lostName]

      visible = true
      position.x = 340   # slide in from right
      var tw := create_tween()
      tw.tween_property(self, "position:x", 0.0, 0.3)
      tw.tween_interval(3.5)
      tw.tween_property(self, "position:x", 340.0, 0.3)
      tw.tween_callback(func(): visible = false)
  ```

- [ ] **Step 3: Add both overlays to `auction_house.gd` and wire them**

  ```gdscript
  const BidRevealScript = preload("res://src/ui/bid_reveal_overlay.gd")
  const ChaosCardScript  = preload("res://src/ui/chaos_card.gd")

  var _bid_reveal: Control = null
  var _chaos_card: Control = null
  ```

  In `_setup_canvas()`:

  ```gdscript
  _bid_reveal = BidRevealScript.new()
  _canvas.add_child(_bid_reveal)

  _chaos_card = ChaosCardScript.new()
  _canvas.add_child(_chaos_card)
  ```

  Update `on_show_bid_result`:

  ```gdscript
  func on_show_bid_result(result: Dictionary) -> void:
      _phase_sign_label.text = "SOLD"
      if _auctioneer_overlay:
          _auctioneer_overlay.hide_reveal()
      if _bid_panel:
          _bid_panel.close()
      if _bid_reveal:
          _bid_reveal.show_result(result)
      if _hud:
          _hud.refresh()
      # Gold burst on winner's character
      _burst_winner(result.get("winner", ""))
  ```

  Update `on_show_chaos`:

  ```gdscript
  func on_show_chaos(chaos: Dictionary) -> void:
      if chaos.is_empty():
          return
      if _chaos_card:
          _chaos_card.show_chaos(chaos)
  ```

  Add winner particle burst helper:

  ```gdscript
  func _burst_winner(winner_name: String) -> void:
      var target: Node3D = null
      if winner_name == NetworkManager.local_name:
          target = _local_player
      elif _remote_players.has(winner_name):
          target = _remote_players[winner_name]
      if target == null:
          return
      var particles := CPUParticles3D.new()
      particles.emitting = true
      particles.one_shot = true
      particles.amount = 40
      particles.lifetime = 1.5
      particles.initial_velocity_min = 3.0
      particles.initial_velocity_max = 6.0
      particles.color = Color.html("C9A227")
      particles.position = target.position + Vector3(0, 1.5, 0)
      add_child(particles)
      get_tree().create_timer(2.0).timeout.connect(func(): particles.queue_free())
  ```

- [ ] **Step 4: Verify**

  From the debugger, call `_bid_reveal.show_result({"winner": "Alice", "price": 420})`. Confirm SOLD card fades in and out. Call `_chaos_card.show_chaos({"type": "appraiser", "text": "That was worth $900!"})`. Confirm card slides in from right.

- [ ] **Step 5: Commit**

  ```bash
  git add hot-garbage-godot/src/ui/bid_reveal_overlay.gd \
          hot-garbage-godot/src/ui/chaos_card.gd \
          hot-garbage-godot/src/scenes/auction_house.gd
  git commit -m "feat: bid reveal overlay, chaos card, winner gold burst"
  ```

---

## Task 11: Final Scores Overlay

**Files:**
- Create: `hot-garbage-godot/src/ui/final_scores_overlay.gd`
- Modify: `hot-garbage-godot/src/scenes/auction_house.gd`

**Interfaces:**
- Consumes: `on_show_final_scores(ranking)` where ranking is the existing array from `engine.getFinalScores()`.
- Produces: full-screen overlay with ranked list, set bonus indicators, LEAVE/PLAY AGAIN buttons. Replaces screen entirely (no scene swap).

- [ ] **Step 1: Create `hot-garbage-godot/src/ui/final_scores_overlay.gd`**

  ```gdscript
  extends Control

  const _UITheme = preload("res://src/scenes/ui_theme.gd")

  var _score_vbox: VBoxContainer

  func _ready() -> void:
      visible = false
      set_anchors_preset(Control.PRESET_FULL_RECT)

      _UITheme.add_bg(self)

      var scroll := ScrollContainer.new()
      scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
      add_child(scroll)

      var outer := VBoxContainer.new()
      outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
      outer.add_theme_constant_override("separation", _UITheme.GAP * 2)
      outer.offset_left   = _UITheme.PAD * 2
      outer.offset_top    = _UITheme.PAD * 2
      outer.offset_right  = -_UITheme.PAD * 2
      outer.offset_bottom = -_UITheme.PAD * 2
      outer.custom_minimum_size = Vector2(960, 0)
      scroll.add_child(outer)

      var title := Label.new()
      title.text = "GRAND REVEAL"
      title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _UITheme.style_label(title, _UITheme.FS_ARTIFACT, _UITheme.GOLD)
      outer.add_child(title)

      _score_vbox = VBoxContainer.new()
      _score_vbox.add_theme_constant_override("separation", _UITheme.GAP)
      outer.add_child(_score_vbox)

      var btn_row := HBoxContainer.new()
      btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
      btn_row.add_theme_constant_override("separation", _UITheme.GAP)
      outer.add_child(btn_row)

      if NetworkManager.is_host():
          var play_again := Button.new()
          play_again.text = "PLAY AGAIN"
          play_again.pressed.connect(_on_play_again)
          _UITheme.style_button(play_again)
          btn_row.add_child(play_again)

      var leave_btn := Button.new()
      leave_btn.text = "LEAVE"
      leave_btn.pressed.connect(_on_leave)
      _UITheme.style_ghost_button(leave_btn)
      btn_row.add_child(leave_btn)

  func show_scores(ranking: Array) -> void:
      visible = true
      for child in _score_vbox.get_children():
          child.queue_free()

      const MEDALS: Array[String] = ["#1", "#2", "#3", "#4", "#5", "#6", "#7", "#8"]

      for i in range(ranking.size()):
          var p: Dictionary = ranking[i]
          var medal: String = MEDALS[i] if i < MEDALS.size() else "#%d" % (i + 1)

          var sep := HSeparator.new()
          _score_vbox.add_child(sep)

          var header := Label.new()
          header.text = "%s  %s — %d pts  (§%d cash)" % [medal, p.id, p.total, p.cash]
          _UITheme.style_label(header, _UITheme.FS_BODY, _UITheme.TEXT)
          header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
          _score_vbox.add_child(header)

          var breakdown: Dictionary = p.get("breakdown", {})
          for cat in breakdown:
              var b: Dictionary = breakdown[cat]
              var completed: bool = b.get("completed", false)
              var set_str: String = ("  SET ×%.1f" % b.get("multiplier", 1.0)) if completed else ""
              var line := Label.new()
              line.text = "  %s: %d items, §%d raw → §%d%s" % [
                  cat.capitalize(), b.get("count", 0), b.get("raw", 0), b.get("scored", 0), set_str
              ]
              _UITheme.style_label(line, _UITheme.FS_LABEL,
                  _UITheme.cat_color(cat) if completed else _UITheme.DIM)
              _score_vbox.add_child(line)

  func _on_play_again() -> void:
      NetworkManager._send({ "type": "delete_room" })
      Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
      get_tree().change_scene_to_file("res://src/scenes/main_menu.tscn")

  func _on_leave() -> void:
      NetworkManager.disconnect_from_game()
      Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
      get_tree().change_scene_to_file("res://src/scenes/main_menu.tscn")
  ```

  Note: `_on_play_again` calls `NetworkManager._send` directly because this is a connection lifecycle call, not a game action — it's the same pattern as `disconnect_from_game()`. Only outbound *game* actions go through NetworkTransport.

- [ ] **Step 2: Add final scores overlay to `auction_house.gd`**

  ```gdscript
  const FinalScoresScript = preload("res://src/ui/final_scores_overlay.gd")
  var _final_scores: Control = null
  ```

  In `_setup_canvas()`:

  ```gdscript
  _final_scores = FinalScoresScript.new()
  _canvas.add_child(_final_scores)
  ```

  Replace the `on_show_final_scores` stub:

  ```gdscript
  func on_show_final_scores(ranking: Array) -> void:
      _phase_sign_label.text = "GRAND REVEAL"
      if _final_scores:
          _final_scores.show_scores(ranking)
  ```

- [ ] **Step 3: Verify**

  From debugger, call `_final_scores.show_scores([{"id": "Alice", "total": 2400, "cash": 300, "breakdown": {"antiquities": {"count": 2, "raw": 800, "scored": 1600, "completed": true, "multiplier": 2.0}}}])`. Confirm overlay appears full-screen with correct data.

- [ ] **Step 4: Commit**

  ```bash
  git add hot-garbage-godot/src/ui/final_scores_overlay.gd \
          hot-garbage-godot/src/scenes/auction_house.gd
  git commit -m "feat: final scores overlay with LEAVE/PLAY AGAIN buttons"
  ```

---

## Task 12: Scene Cleanup + advance_scene: auction_house

This task switches the server to send `advance_scene: auction_house` once at game start, removes per-turn scene changes, and deletes the old 2D in-game scene files.

**Files:**
- Modify: `hot-garbage-server/game_session.js`
- Modify: `hot-garbage-server/test/game_session.test.js`
- Modify: `hot-garbage-godot/src/network/network_manager.gd`
- Delete: old 2D in-game scenes (list below)

**Interfaces:**
- Produces: server sends `advance_scene: auction_house` in `start()`. No `advance_scene` messages during turns. `final_scores_overlay` handles end-of-game UI without a scene change.

- [ ] **Step 1: Update `game_session.js` — send `advance_scene: auction_house` once in `start()`**

  In `start()`, add the broadcast right before `_beginTurn()`:

  ```js
  start() {
    this.isActive = true;
    this._engine = this._engineFactory
      ? this._engineFactory()
      : new HotGarbageServer({
          seed: (Math.random() * 0x100000000) >>> 0,
          playerIds: this._playerNames,
          chaosChance: this._chaosChance,
          dataPath: DATA_PATH,
        });
    this._order = this._engine.getOrder();
    this._send(null, { type: 'advance_scene', scene: 'auction_house' });
    this._beginTurn();
  }
  ```

- [ ] **Step 2: Remove per-turn `advance_scene` calls from `_beginTurn` and `_resolveAuction` and `_endGame`**

  In `_beginTurn()`, delete the entire block:

  ```js
  // DELETE THIS BLOCK:
  for (const name of this._playerNames) {
    this._send(name, {
      type: 'advance_scene',
      scene: name === this._currentAuctioneer ? 'auctioneer_view' : 'bidder_view',
    });
  }
  ```

  In `_resolveAuction()`, delete:

  ```js
  // DELETE THIS LINE:
  this._send(null, { type: 'advance_scene', scene: 'bid_reveal' });
  ```

  In `_endGame()`, delete:

  ```js
  // DELETE THIS LINE:
  this._send(null, { type: 'advance_scene', scene: 'final_scores' });
  ```

- [ ] **Step 3: Update `game_session.test.js` for new scene behavior**

  The existing test `'start sends advance_scene to each player'` now expects a single `auction_house` broadcast, not per-player auctioneer/bidder sends. Replace it:

  ```js
  test('start sends advance_scene auction_house to all players', async () => {
    const { session, log } = makeSession();
    session.start();
    await new Promise(r => setTimeout(r, 100));
    const scenes = msgsOf(log, 'advance_scene');
    assert.equal(scenes.length, 1, 'only one advance_scene should be sent');
    assert.equal(scenes[0].to, null, 'advance_scene should be broadcast');
    assert.equal(scenes[0].msg.scene, 'auction_house');
  });
  ```

  Also verify no `advance_scene` during bidding resolve — add:

  ```js
  test('resolveAuction does not send advance_scene', async () => {
    const { session, log } = makeSession(['Alice', 'Bob', 'Carol']);
    session.start();
    await new Promise(r => setTimeout(r, 100));
    log.length = 0; // clear startup messages
    session.openEarly('Alice'); // trigger bidding
    await new Promise(r => setTimeout(r, 50));
    session.forceResolve('Alice');
    await new Promise(r => setTimeout(r, 100));
    const scenes = msgsOf(log, 'advance_scene');
    assert.equal(scenes.length, 0, 'no advance_scene during auction resolve');
  });
  ```

- [ ] **Step 4: Run server tests**

  ```bash
  cd hot-garbage-server && node --test test/game_session.test.js
  ```

  Expected: all tests pass.

- [ ] **Step 5: Remove old in-game scene keys from `NetworkManager.SCENE_PATHS`**

  In `network_manager.gd`, update `SCENE_PATHS`:

  ```gdscript
  const SCENE_PATHS := {
      "lobby":         "res://src/scenes/lobby.tscn",
      "auction_house": "res://src/scenes/auction_house.tscn",
  }
  ```

  Remove the `dispatch` handlers for `auctioneer_reveal` and the propagate_call dispatch patterns that are now handled inside `auction_house.gd`. Actually — keep them. `propagate_call` still works correctly: it calls the method on whatever scene is currently loaded. Since `auction_house.gd` implements all these methods, the dispatch continues to work without changes to `_dispatch()`.

  The only thing to remove from `_dispatch` is the now-unused `send_open_early`, `submit_bid`, `send_force_resolve` methods that old scenes called directly on NetworkManager. These are kept too — the old API still functions as pass-throughs for now. Leave them; they're harmless.

- [ ] **Step 6: Delete old 2D in-game scene files**

  ```bash
  cd hot-garbage-godot
  rm src/scenes/auctioneer_view.gd src/scenes/auctioneer_view.gd.uid src/scenes/auctioneer_view.tscn
  rm src/scenes/bidder_view.gd src/scenes/bidder_view.gd.uid src/scenes/bidder_view.tscn
  rm src/scenes/bid_reveal.gd src/scenes/bid_reveal.gd.uid src/scenes/bid_reveal.tscn
  rm src/scenes/final_scores.gd src/scenes/final_scores.gd.uid src/scenes/final_scores.tscn
  rm src/scenes/hud.gd src/scenes/hud.gd.uid
  ```

  Open the Godot editor. Confirm no errors about missing files. The `.uid` files may or may not exist depending on Godot's import cache — delete whichever exist.

- [ ] **Step 7: Full end-to-end test**

  Start the server:
  ```bash
  cd hot-garbage-server && node server.js
  ```

  Open two Godot clients. Player 1 creates a room, Player 2 joins. Player 1 starts the game. Both clients should:
  1. Load `auction_house.tscn` (the 3D room)
  2. See their colored capsule character and the other player
  3. See a PITCH PHASE sign on the right wall
  4. Auctioneer sees the true value banner top-center
  5. After pitch timer, bidding opens — non-auctioneer sees bid panel bottom-center
  6. Submit bid → SOLD card fades in
  7. Chaos card slides in if chaos fires
  8. Next pitch begins (round counter increments)
  9. After all rounds, GRAND REVEAL overlay covers the screen

- [ ] **Step 8: Commit**

  ```bash
  cd ..  # back to repo root
  git add hot-garbage-server/game_session.js \
          hot-garbage-server/test/game_session.test.js \
          hot-garbage-godot/src/network/network_manager.gd
  git rm hot-garbage-godot/src/scenes/auctioneer_view.gd \
         hot-garbage-godot/src/scenes/auctioneer_view.tscn \
         hot-garbage-godot/src/scenes/bidder_view.gd \
         hot-garbage-godot/src/scenes/bidder_view.tscn \
         hot-garbage-godot/src/scenes/bid_reveal.gd \
         hot-garbage-godot/src/scenes/bid_reveal.tscn \
         hot-garbage-godot/src/scenes/final_scores.gd \
         hot-garbage-godot/src/scenes/final_scores.tscn \
         hot-garbage-godot/src/scenes/hud.gd
  git commit -m "feat: switch to single advance_scene: auction_house, remove old 2D in-game scenes"
  ```

---

*Plan complete. 12 tasks. No external assets required. Server tests verifiable with `node --test`. Godot tasks verifiable by running the scene and checking visual output.*
