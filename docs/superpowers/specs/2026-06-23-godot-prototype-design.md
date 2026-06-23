# Hot Garbage — Godot Prototype Design

**Date:** 2026-06-23
**Status:** Approved
**Scope:** Phase 1 networked prototype — desktop LAN play, Steam-networking-ready

---

## 1. Goals

Build a playable networked prototype of Hot Garbage in Godot 4.3+ (GDScript) that:
- Runs the full game loop: lobby → auction rounds → final scores
- Supports 4–8 players on a LAN, one device each
- Keeps the transport isolated so Steam GodotSteam can replace ENet later
- Preserves the privacy invariant: true artifact values never reach non-owner clients

This is Phase 1 of the roadmap (local networked prototype). The JS headless engine remains in the repo as reference; the Godot project lives in `hot-garbage-godot/`.

---

## 2. Architecture

Three strict layers with no downward coupling:

```
logic/          pure GDScript, no Godot UI imports — game rules only
network/        one autoload — all ENet setup and RPC routing
server/ + scenes/   host logic and display
```

### File structure

```
hot-garbage-godot/
├── project.godot
├── data/
│   └── artifacts.json          ← copy from parent repo
├── src/
│   ├── logic/
│   │   ├── game_engine.gd
│   │   └── scoring.gd
│   ├── network/
│   │   └── network_manager.gd  ← autoload
│   ├── server/
│   │   └── game_server.gd      ← host-only node
│   └── scenes/
│       ├── main_menu.tscn / main_menu.gd
│       ├── lobby.tscn / lobby.gd
│       ├── auctioneer_view.tscn / auctioneer_view.gd
│       ├── bidder_view.tscn / bidder_view.gd
│       ├── bid_reveal.tscn / bid_reveal.gd
│       └── final_scores.tscn / final_scores.gd
└── assets/
```

---

## 3. Game Flow

```
MainMenu → Lobby → [Game Loop] → FinalScores

Game Loop (repeats once per player per round):
  GameServer starts auction
    → AuctioneerView (auctioneer's private screen)
    → BidderView (all other players simultaneously)
    → all bids received (auto-resolves; host can force-resolve as escape hatch for dropped clients)
    → BidReveal (everyone: winner, price, optional chaos)
  Next auctioneer turn
```

### Scene responsibilities

| Scene | Who sees it | Responsibility |
|---|---|---|
| `MainMenu` | All | Host or join by IP; no game state |
| `Lobby` | All | Show connected players; host presses Start |
| `AuctioneerView` | Auctioneer only | Full artifact (name, category, flavor, **true value**); watch bid count tick up as peers submit; auto-advances when all bids received |
| `BidderView` | Non-auctioneers | Public artifact (name, category, flavor — **no value**); bid input + submit; locks after submit |
| `BidReveal` | All | Winner + price; appraiser reveal or event card if chaos fired |
| `FinalScores` | All | Ranked score breakdown with set multipliers |

---

## 4. Network Design

**Topology:** Godot 4 ENet, host-authoritative. Host runs `GameServer`; clients are display terminals.

**Steam-ready seam:** `NetworkManager` exposes exactly three transport methods:

```gdscript
func host(port: int) -> void
func join(ip: String, port: int) -> void
func send_to(peer_id: int, method: StringName, args: Array) -> void
```

Nothing outside `NetworkManager` calls Godot's `multiplayer` API. Replacing ENet with GodotSteam = rewriting these three methods only.

### RPC contract

| Direction | Method | Payload | Notes |
|---|---|---|---|
| client → host | `submit_bid(amount)` | int | Host clamps to player cash; ignores duplicates |
| host → auctioneer | `reveal_to_auctioneer(artifact)` | full artifact dict | **Targeted** — only RPC that carries `value` |
| host → all | `start_bidding(artifact)` | `{name, category, flavor, id}` | No value field |
| host → all | `show_bid_result(result)` | `{winner_id, price, seller_gain}` | |
| host → all | `show_chaos(chaos)` | `{type, text, extra}` | type: "appraiser" or "event" |
| host → all | `show_final_scores(ranking)` | array of score dicts | |
| host → all | `player_joined(id, name)` | | Lobby sync |
| host → all | `advance_to_scene(scene_name)` | string | Host drives all scene transitions |

### Privacy invariant

`GameServer` sends two separate RPCs at auction start:
1. `reveal_to_auctioneer(full_artifact)` — targeted to auctioneer's peer ID only
2. `start_bidding(public_artifact)` — broadcast, no `value` field

True value is **never** in a broadcast RPC.

---

## 5. Engine Port

### `scoring.gd`

Direct port of `scoring.js`. Pure static functions, no state.

```gdscript
const SET_THRESHOLD := 3
static func score_player(artifacts: Array, cash: int, categories: Dictionary) -> Dictionary
static func rank_players(players: Dictionary, categories: Dictionary) -> Array
```

### `game_engine.gd`

Port of `engine.js` with two deliberate changes from the JS version:

**1. No file I/O.** Constructor takes pre-parsed artifact data:
```gdscript
func _init(opts: Dictionary, artifact_data: Dictionary) -> void
```
`GameServer` loads `artifacts.json` and passes it in.

**2. Async bid collection instead of synchronous callback.** The JS engine collects bids via a `bidStrategy` callback in one shot. Godot bids arrive asynchronously over the network, so `run_auction()` splits into:

```gdscript
func start_auction(auctioneer_id: String) -> Dictionary   # returns public_artifact
func get_auctioneer_artifact() -> Dictionary              # returns full artifact
func submit_bid(player_id: String, amount: int) -> void   # called per incoming RPC
func resolve_auction() -> Dictionary                      # called when all bids in
```

Everything else ports verbatim: mulberry32 RNG, Fisher-Yates shuffle, chaos check, event application, `flags` dict, set bonus logic.

---

## 6. Decisions & Constraints

- **Bidding style:** Sealed one-shot (matches existing engine; open ascending is a future upgrade)
- **Round count:** `min(player_count, 6)` — matches JS engine default
- **Bank floor:** §25 if no bids — matches JS engine default
- **Starting cash:** §1000 — matches JS engine default
- **Chaos chance:** 0.25 (1-in-4) — matches JS engine default
- **Godot version:** 4.3+
- **Language:** GDScript
- **No bot players in prototype** — all seats are human network peers
- **No art assets** — placeholder colored panels per category, text only
