# Hot Garbage — Internet Play Design

**Date:** 2026-06-24
**Status:** Approved
**Scope:** Replace LAN-only ENet transport with a hosted Node.js WebSocket server, enabling internet play with named password-protected rooms and DynamoDB-backed room persistence.

---

## 1. Goals

- Players can create named rooms with passwords and share them with friends over Discord/text
- No port forwarding, no IP address exchange
- Server sleeps when idle and wakes on first connection (near-zero cost when not playing)
- Room names and passwords persist across server restarts and sleep cycles
- Mid-game disconnects are recoverable — player rejoins with the same name + password
- Privacy invariant preserved: true artifact values never reach non-owner clients

Out of scope for this spec: comedy/polish/QoL improvements, open ascending bidding, mobile clients, Steam networking.

---

## 2. Overall Architecture

Three layers, clean separation:

```
┌─────────────────────────────────────────────────────────┐
│  AWS App Runner                                         │
│                                                         │
│  hot-garbage-server/          ← new Node.js package     │
│  ├── server.js                ← WebSocket + room mgmt   │
│  ├── game_session.js          ← per-room game loop      │
│  ├── room_store.js            ← DynamoDB read/write     │
│  └── (imports) ../server/engine.js + scoring.js         │
│                                                         │
│  DynamoDB table: hot-garbage-rooms                      │
│  (room metadata only — game state stays in memory)      │
└─────────────────────────────────────────────────────────┘
           ▲ WebSocket (wss://)
           │
┌──────────┴──────────────────────────────────────────────┐
│  Godot client (all players)                             │
│  NetworkManager rewritten: ENet → WebSocketPeer         │
│  Main menu: "room name + password" instead of IP field  │
└─────────────────────────────────────────────────────────┘
```

### What changes vs. what stays the same

| Component | Change |
|---|---|
| `server/engine.js` | **Unchanged** — server imports directly |
| `server/scoring.js` | **Unchanged** |
| `GameServer.gd` | **Stripped** — game logic moves to `game_session.js`; client copy becomes a thin display-state store |
| `NetworkManager.gd` | **Rewritten** — ENet RPCs → WebSocket JSON messages, same public signal API |
| All scenes (main_menu, lobby, auctioneer_view, bidder_view, bid_reveal, final_scores) | **Unchanged** except minor player-list iteration and "is me" check |
| `game_engine.gd` | **Unchanged** — kept for potential offline/local play later |

The key insight: `GameServer.gd` was already the only file doing host-only work with no UI dependencies. Moving it to Node.js is a clean cut. Every scene calls `NetworkManager` signals — we swap the transport underneath and scenes never notice.

---

## 3. Room System

### DynamoDB table: `hot-garbage-rooms`

| Attribute | Type | Notes |
|---|---|---|
| `roomName` (PK) | String | Stored lowercase; alphanumeric + hyphens, ≤ 20 chars |
| `passwordHash` | String | bcrypt hash — plain password never stored |
| `createdBy` | String | Player name of creator |
| `createdAt` | Number | Unix timestamp |
| `config` | Map | `{ pitchDuration, chaosChance, maxPlayers }` |

Game state (bids, artifacts, cash, turn order) is never written to Dynamo — it lives in memory in a `GameSession` object. If the server restarts mid-game, in-flight game state is lost but the room itself is restored from Dynamo on cold start.

### Room lifecycle

```
CREATE  → validate name (alphanumeric+hyphens, ≤ 20 chars)
          check name not already taken (Dynamo GetItem)
          bcrypt hash password
          write to Dynamo
          create in-memory RoomSession; creator joins as host

JOIN    → GetItem from Dynamo (404 → ROOM_NOT_FOUND)
          bcrypt compare password (mismatch → WRONG_PASSWORD)
          check player name not already in room (NAME_IN_USE)
          check room not full (ROOM_FULL)
          add player to in-memory RoomSession

REJOIN  → same as JOIN
          if a GameSession is active and player name is in the player list,
          player is handed back their seat (name is the stable identity key)

GAME END → GameSession cleared from memory; room stays in Dynamo
           room immediately ready for another game

DELETE  → host-only: delete from Dynamo, emit server_disconnected to all players
```

### Cold start room restore

On server startup, scan Dynamo to load all room definitions into memory as empty `RoomSession` objects (no active game). When a player joins a room that has no active game session, the `room_joined` response includes `serverRestarted: true`. The lobby shows a "Server restarted — start a new game" banner in that case. Players who created the room fresh never see the banner.

### Reconnect handling

Player names are the stable identity key (matches the engine's `player_id`). A reconnecting player rejoins with the correct room name + password. The server matches by name to their existing game slot — no tokens needed. The password is the reconnect credential.

---

## 4. Message Protocol

All messages are JSON over WebSocket: `{ "type": "...", ...payload }`.

### Client → Server

| Message | Payload | Notes |
|---|---|---|
| `create_room` | `roomName, password, playerName` | Creates + joins as host |
| `join_room` | `roomName, password, playerName` | Joins or rejoins existing room |
| `start_game` | _(none)_ | Host only; ignored from non-host |
| `open_early` | _(none)_ | Auctioneer requests early bid open |
| `submit_bid` | `amount` | Server clamps to player cash |
| `force_resolve` | _(none)_ | Host escape hatch for stuck auctions |
| `delete_room` | _(none)_ | Host only; kicks all players |

### Server → Client

| Message | Payload | Who receives |
|---|---|---|
| `room_joined` | `roomName, isHost, config, players[], serverRestarted` | Joining player only — `serverRestarted: true` when room exists but no active game (server woke cold) |
| `player_joined` | `playerName, players[]` | All in room |
| `player_left` | `playerName, players[]` | All in room |
| `error` | `code, message` | Requesting player only |
| `advance_scene` | `scene` (logical name) | All |
| `auctioneer_reveal` | `artifact` (with value), `pitchDuration` | **Auctioneer only** |
| `start_pitch` | `artifact` (no value), `pitchDuration`, `auctioneerName` | All |
| `open_bidding` | _(none)_ | All |
| `bid_result` | `winner, price, artifact` (no value) | All |
| `chaos` | `type, text, extra` | All |
| `sync_player_state` | `cash, artifacts[]` | Targeted player only |
| `final_scores` | `ranking[]` | All |
| `bid_count` | `received, total` | Auctioneer only — updates "Bids received: X/Y" display |

### Error codes

`ROOM_NOT_FOUND`, `WRONG_PASSWORD`, `NAME_TAKEN` (room already exists on create), `NAME_IN_USE` (player name already active in room), `ROOM_FULL`, `GAME_IN_PROGRESS` (joining a room mid-game and name not in player list).

### Privacy invariant

`auctioneer_reveal` is a direct send to one WebSocket connection. `start_pitch` is the broadcast with the `value` field stripped server-side before sending. Same contract as the ENet implementation — server-side enforcement, not client-side trust.

### Scene routing

Server sends logical scene names (`"lobby"`, `"auctioneer_view"`, `"bidder_view"`, `"bid_reveal"`, `"final_scores"`). The Godot client maps these to `res://` paths in NetworkManager. Server never knows Godot file paths.

---

## 5. Godot Client Changes

### NetworkManager.gd — full rewrite

Replaces ENet with `WebSocketPeer`. Same signal names where possible; same `propagate_call` dispatch so all scenes receive `on_auctioneer_reveal`, `on_start_pitch`, etc. without changes.

**New public API:**

```gdscript
# Connection
func create_room(room_name: String, password: String, player_name: String) -> void
func join_room(room_name: String, password: String, player_name: String) -> void
func disconnect_from_game() -> void
func is_host() -> bool              # set from room_joined message

# Gameplay (unchanged callers)
func send_open_early() -> void
func submit_bid(amount: int) -> void

# State read by scenes
var player_names: Array[String]     # ordered list, replaces peer_id dict
var local_name: String

# Signals
signal room_joined(room_name: String, is_host: bool)
signal player_registered(player_name: String)   # emitted on player_joined
signal player_disconnected(player_name: String) # emitted on player_left
signal connection_failed()
signal server_disconnected()
signal error_received(code: String, message: String)
signal bid_count_updated(received: int, total: int)    # auctioneer only — from server bid_count message
```

`_process()` polls `WebSocketPeer` each frame and dispatches incoming JSON to scene callbacks via `propagate_call` — same pattern as before, new transport.

**Server URL constant:**

```gdscript
const SERVER_URL := "wss://hot-garbage.your-domain.com/ws"  # prod
# const SERVER_URL := "ws://localhost:3000/ws"              # local dev
```

### main_menu.gd — UI changes only

- IP field → Room Name field (alphanumeric + hyphens)
- Password field added (shown for both create and join)
- HOST GAME → CREATE ROOM (calls `create_room()`)
- JOIN GAME → JOIN ROOM (calls `join_room()`)
- Error label surfaces `error_received` codes in plain language

### GameServer.gd — stripped to display-state store

Game logic moves to Node.js `game_session.js`. The client copy becomes:

```gdscript
# Display state — populated by sync_player_state messages
var player_cash: Dictionary = {}
var player_artifacts: Dictionary = {}

func receive_player_state(cash: int, artifacts: Array) -> void:
    # unchanged — called by NetworkManager on sync_player_state
```

Scenes continue to read `GameServer.player_cash.get(name, -1)` with no changes.

### Game scenes — minimal touch

Two mechanical changes across lobby, auctioneer_view, bidder_view, and final_scores:

1. **"Is me" check:** `peer_id == multiplayer.get_unique_id()` → `name == NetworkManager.local_name`
2. **Player list iteration:** `NetworkManager.player_names` is now `Array[String]` instead of `{peer_id: name}` dict — loop syntax simplifies

Everything else — layouts, HUD, chaos display, bid input, countdown timers, leave dialogs — untouched.

---

## 6. Server Package

### File structure

```
hot-garbage-server/
├── Dockerfile
├── package.json          ← ws, @aws-sdk/client-dynamodb, bcrypt
├── server.js             ← WebSocket server, connection lifecycle, message dispatch
├── room_store.js         ← DynamoDB GetItem / PutItem / DeleteItem / Scan
└── game_session.js       ← per-room game loop; imports ../../server/engine.js
```

### server.js responsibilities

- Accept WebSocket connections
- Route incoming messages to `RoomSession` handlers
- Maintain `Map<roomName, RoomSession>` in memory
- On startup: scan Dynamo, populate room map as empty sessions
- Sets `serverRestarted: true` in `room_joined` when a player joins a room with no active game session

### game_session.js responsibilities

Port of `GameServer.gd` host logic:
- `start_game(playerIds, config)` — initialises `GameEngine`, begins turn loop
- `_begin_turn()` — routes `advance_scene`, `auctioneer_reveal`, `start_pitch`
- `_open_bidding()` — broadcasts `open_bidding`
- `submit_bid(playerName, amount)` — delegates to engine, resolves when all bids in
- `_resolve_auction()` — broadcasts `bid_result`, `chaos`, advances to next turn
- `_end_game()` — broadcasts `final_scores`

Imports `engine.js` and `scoring.js` verbatim — no modifications to either.

### room_store.js responsibilities

Thin DynamoDB wrapper:
- `createRoom(roomName, passwordHash, createdBy, config)`
- `getRoom(roomName)` → room record or null
- `deleteRoom(roomName)`
- `scanAllRooms()` → array of room records (called on startup only)

Password comparison (`bcrypt.compare`) happens in `server.js` before calling the store.

---

## 7. AWS Deployment

### Service: AWS App Runner

App Runner deploys the container, provides managed TLS, auto-pauses after 5 minutes of inactivity, and auto-resumes on the first incoming connection (cold start ~5–8 seconds).

```
ECR repository:     hot-garbage-server
App Runner service: hot-garbage
  vCPU: 0.25   memory: 0.5 GB
  auto-pause:  enabled, 5 min idle
  port:        3000
  env vars:    DYNAMODB_TABLE=hot-garbage-rooms
               DYNAMODB_REGION=us-east-1
  IAM role:    dynamodb:GetItem, PutItem, DeleteItem, Scan on table ARN

DynamoDB table:     hot-garbage-rooms (on-demand billing, us-east-1)
```

### Cost profile

| State | Cost |
|---|---|
| Paused (idle) | ~$0 |
| Active (game running) | ~$0.016/hour (0.25 vCPU) |
| DynamoDB | ~$0 (on-demand, tiny items) |
| 3-hour game night | ~$0.05 |

### TLS / domain

App Runner provides a default `https://[id].us-east-1.awsapprunner.com` endpoint. Custom domain (`play.hot-garbage.yourname.com`) via Route 53 CNAME is one CLI command when desired.

### Local development

```yaml
# docker-compose.yml
services:
  server:
    build: ./hot-garbage-server
    ports: ["3000:3000"]
    environment:
      DYNAMODB_TABLE: hot-garbage-rooms
      DYNAMODB_ENDPOINT: http://dynamodb-local:8000
  dynamodb-local:
    image: amazon/dynamodb-local
    ports: ["8000:8000"]
```

`NetworkManager.gd` `SERVER_URL` constant points to `ws://localhost:3000/ws` for local dev. Switch to `wss://` prod URL for builds.

### Deployment flow

```bash
docker build -t hot-garbage-server ./hot-garbage-server
docker tag hot-garbage-server [account].dkr.ecr.us-east-1.amazonaws.com/hot-garbage-server:latest
docker push [account].dkr.ecr.us-east-1.amazonaws.com/hot-garbage-server:latest
# App Runner auto-deploys on new image push (configurable)
```

Existing AWS bootstrapping from other repos covers ECR repository creation, App Runner service setup, and IAM role configuration.

---

## 8. Decisions & Constraints

- **Room state persistence:** DynamoDB stores room metadata only. In-flight game state is in-memory; a server restart loses the active game but not the room.
- **Reconnect credential:** room name + password. No separate token needed — password is the stable credential.
- **Player identity:** player name string (same as engine's `player_id`). Names must be unique within a room; server rejects `NAME_IN_USE`.
- **Game logic:** `engine.js` and `scoring.js` imported verbatim — no modifications.
- **Transport:** WebSocket (WSS in prod, WS for local dev). ENet removed entirely.
- **No spectators in v1:** every connected player in a room is a game participant.
- **Host migration:** not in scope — if the host disconnects during a game, the session ends. Room persists; players start a new game.
- **Max players:** configurable per room in `config.maxPlayers`, default 8, minimum 2.
