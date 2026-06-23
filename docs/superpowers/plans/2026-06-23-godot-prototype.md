# Hot Garbage Godot Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a playable LAN-networked Godot 4 prototype of Hot Garbage — full game loop from lobby through final scores, host-authoritative, Steam-transport-ready.

**Architecture:** Pure GDScript logic layer (game_engine.gd, scoring.gd) owns all rules with zero Godot UI coupling; a NetworkManager autoload owns all ENet setup and RPC routing; GameServer autoload drives game flow on the host only; six focused scenes handle display.

**Tech Stack:** Godot 4.3+, GDScript, ENet (built-in), artifacts.json from parent repo.

## Global Constraints

- Godot version: 4.3+, GDScript only (no C#)
- Project root: `hot-garbage-godot/` (sibling of `server/`, `data/`, etc.)
- `src/logic/` files: zero Godot imports — `class_name` only, no `extends Node`
- True artifact `value` field NEVER appears in any broadcast RPC payload — only in `reveal_to_auctioneer` targeted to one peer
- All multiplayer API calls (`multiplayer.*`, `ENetMultiplayerPeer`) confined to `src/network/network_manager.gd`
- Scene transitions driven by host only via `NetworkManager.advance_scene` RPC
- Sealed one-shot bidding; no timers in v1 — auto-resolve when all non-auctioneer peers submit
- Default game constants: startingCash=1000, chaosChance=0.25, bankFloor=25, rounds=min(players,6)
- No bot players in prototype; no art assets — colored panels + text only

---

## File Map

| File | Responsibility |
|---|---|
| `hot-garbage-godot/project.godot` | Project config, autoload registration |
| `hot-garbage-godot/data/artifacts.json` | Copy from `../data/artifacts.json` |
| `src/logic/scoring.gd` | Pure port of scoring.js — static functions only |
| `src/logic/game_engine.gd` | Pure port of engine.js — async bid collection variant |
| `src/logic/test_scoring.gd` | Headless test script for scoring.gd |
| `src/logic/test_game_engine.gd` | Headless test script for game_engine.gd |
| `src/network/network_manager.gd` | Autoload: ENet setup + ALL RPC definitions |
| `src/server/game_server.gd` | Autoload: host-only game flow orchestration |
| `src/scenes/main_menu.gd` | Host/Join UI, name entry |
| `src/scenes/main_menu.tscn` | Scene root for main_menu.gd |
| `src/scenes/lobby.gd` | Player list, Start button (host only) |
| `src/scenes/lobby.tscn` | Scene root for lobby.gd |
| `src/scenes/auctioneer_view.gd` | Auctioneer's private screen |
| `src/scenes/auctioneer_view.tscn` | Scene root |
| `src/scenes/bidder_view.gd` | Bidder's screen — public artifact + bid input |
| `src/scenes/bidder_view.tscn` | Scene root |
| `src/scenes/bid_reveal.gd` | Post-auction result + chaos display |
| `src/scenes/bid_reveal.tscn` | Scene root |
| `src/scenes/final_scores.gd` | End-of-game ranked breakdown |
| `src/scenes/final_scores.tscn` | Scene root |

---

## Task 1: Project Scaffold

**Files:**
- Create: `hot-garbage-godot/project.godot`
- Create: `hot-garbage-godot/data/artifacts.json` (copy)
- Create: all `src/` subdirectories

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p hot-garbage-godot/data
mkdir -p hot-garbage-godot/src/logic
mkdir -p hot-garbage-godot/src/network
mkdir -p hot-garbage-godot/src/server
mkdir -p hot-garbage-godot/src/scenes
cp data/artifacts.json hot-garbage-godot/data/artifacts.json
```

- [ ] **Step 2: Create project.godot**

Create `hot-garbage-godot/project.godot`:

```ini
; Engine configuration file.
; It's best edited using the editor UI and not directly,
; but this minimal version is valid for Godot 4.3+.

config_version=5

[application]

config/name="Hot Garbage"
run/main_scene="res://src/scenes/main_menu.tscn"
config/features=PackedStringArray("4.3", "Forward Plus")

[autoload]

NetworkManager="*res://src/network/network_manager.gd"
GameServer="*res://src/server/game_server.gd"

[rendering]

renderer/rendering_method="forward_plus"
renderer/rendering_method.mobile="mobile"
```

- [ ] **Step 3: Create placeholder .tscn files**

Each scene needs a minimal .tscn so the project doesn't error on missing files. Run these to create them — you'll replace the content per-task:

Create `hot-garbage-godot/src/scenes/main_menu.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/scenes/main_menu.gd" id="1"]

[node name="MainMenu" type="Control"]
script = ExtResource("1")
anchor_right = 1.0
anchor_bottom = 1.0
```

Create `hot-garbage-godot/src/scenes/lobby.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/scenes/lobby.gd" id="1"]

[node name="Lobby" type="Control"]
script = ExtResource("1")
anchor_right = 1.0
anchor_bottom = 1.0
```

Create `hot-garbage-godot/src/scenes/auctioneer_view.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/scenes/auctioneer_view.gd" id="1"]

[node name="AuctioneerView" type="Control"]
script = ExtResource("1")
anchor_right = 1.0
anchor_bottom = 1.0
```

Create `hot-garbage-godot/src/scenes/bidder_view.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/scenes/bidder_view.gd" id="1"]

[node name="BidderView" type="Control"]
script = ExtResource("1")
anchor_right = 1.0
anchor_bottom = 1.0
```

Create `hot-garbage-godot/src/scenes/bid_reveal.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/scenes/bid_reveal.gd" id="1"]

[node name="BidReveal" type="Control"]
script = ExtResource("1")
anchor_right = 1.0
anchor_bottom = 1.0
```

Create `hot-garbage-godot/src/scenes/final_scores.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/scenes/final_scores.gd" id="1"]

[node name="FinalScores" type="Control"]
script = ExtResource("1")
anchor_right = 1.0
anchor_bottom = 1.0
```

- [ ] **Step 4: Create stub .gd files for all scenes so Godot doesn't error**

Create `hot-garbage-godot/src/scenes/main_menu.gd`:
```gdscript
extends Control
func _ready() -> void:
	pass
```

Repeat the same stub content for `lobby.gd`, `auctioneer_view.gd`, `bidder_view.gd`, `bid_reveal.gd`, `final_scores.gd`.

Create `hot-garbage-godot/src/network/network_manager.gd`:
```gdscript
extends Node
```

Create `hot-garbage-godot/src/server/game_server.gd`:
```gdscript
extends Node
```

- [ ] **Step 5: Open in Godot editor and verify project loads**

```bash
cd hot-garbage-godot
godot --editor .
# OR: open Godot 4, Import Project, select hot-garbage-godot/project.godot
```

Expected: project opens, no errors in the Output panel, main_menu scene is the run target.

- [ ] **Step 6: Commit**

```bash
cd hot-garbage-godot
git add .
git commit -m "feat: scaffold Godot project structure"
```

---

## Task 2: scoring.gd

**Files:**
- Create: `src/logic/scoring.gd`
- Create: `src/logic/test_scoring.gd`

**Interfaces:**
- Produces:
  - `Scoring.score_player(artifacts: Array, cash: int, categories: Dictionary) -> Dictionary`
    - returns `{total: int, cash: int, breakdown: {cat: {count, raw, multiplier, completed, scored}}}`
  - `Scoring.rank_players(players: Dictionary, categories: Dictionary) -> Array`
    - players map: `{player_id: {artifacts: Array, cash: int}}`
    - returns Array of `{id, total, cash, breakdown}`, sorted highest total first
  - `Scoring.SET_THRESHOLD: int = 3`

- [ ] **Step 1: Write the failing test**

Create `hot-garbage-godot/src/logic/test_scoring.gd`:

```gdscript
extends SceneTree

func _init() -> void:
	var passed := 0
	var failed := 0

	# Test 1: no artifacts, just cash
	var r1 = Scoring.score_player([], 500, {})
	assert(r1.total == 500, "FAIL test1: expected 500 got %d" % r1.total)
	assert(r1.breakdown.is_empty(), "FAIL test1: breakdown should be empty")
	print("PASS test1: cash only")
	passed += 1

	# Test 2: two artifacts of same category — no set bonus (below threshold)
	var r2 = Scoring.score_player(
		[{"category": "antiquities", "value": 100}, {"category": "antiquities", "value": 200}],
		0,
		{"antiquities": {"setBonus": 2.0}}
	)
	assert(r2.total == 300, "FAIL test2: expected 300 got %d" % r2.total)
	assert(r2.breakdown["antiquities"].completed == false, "FAIL test2: should not complete set")
	assert(r2.breakdown["antiquities"].multiplier == 1.0, "FAIL test2: multiplier should be 1.0")
	print("PASS test2: incomplete set, no bonus")
	passed += 1

	# Test 3: three artifacts of same category — set bonus applies
	var r3 = Scoring.score_player(
		[
			{"category": "antiquities", "value": 100},
			{"category": "antiquities", "value": 200},
			{"category": "antiquities", "value": 300},
		],
		500,
		{"antiquities": {"setBonus": 2.0}}
	)
	# raw = 600, scored = 600 * 2.0 = 1200, total = 1200 + 500 = 1700
	assert(r3.total == 1700, "FAIL test3: expected 1700 got %d" % r3.total)
	assert(r3.breakdown["antiquities"].completed == true, "FAIL test3: set should complete")
	assert(r3.breakdown["antiquities"].multiplier == 2.0, "FAIL test3: multiplier should be 2.0")
	assert(r3.breakdown["antiquities"].scored == 1200, "FAIL test3: scored should be 1200")
	print("PASS test3: completed set with bonus")
	passed += 1

	# Test 4: mixed categories
	var r4 = Scoring.score_player(
		[
			{"category": "antiquities", "value": 100},
			{"category": "junk", "value": 50},
		],
		200,
		{"antiquities": {"setBonus": 2.0}, "junk": {"setBonus": 1.5}}
	)
	# antiquities: 1 item, raw=100, mult=1.0, scored=100
	# junk: 1 item, raw=50, mult=1.0, scored=50
	# total = 200 + 100 + 50 = 350
	assert(r4.total == 350, "FAIL test4: expected 350 got %d" % r4.total)
	print("PASS test4: mixed categories, no bonuses")
	passed += 1

	# Test 5: rank_players — higher total wins
	var players = {
		"alice": {"artifacts": [{"category": "antiquities", "value": 1000}, {"category": "antiquities", "value": 500}, {"category": "antiquities", "value": 500}], "cash": 0},
		"bob":   {"artifacts": [], "cash": 100},
	}
	var cats = {"antiquities": {"setBonus": 2.0}}
	var ranking = Scoring.rank_players(players, cats)
	# alice: (1000+500+500)*2.0 = 4000; bob: 100
	assert(ranking[0].id == "alice", "FAIL test5: alice should win")
	assert(ranking[0].total == 4000, "FAIL test5: alice total should be 4000 got %d" % ranking[0].total)
	assert(ranking[1].id == "bob", "FAIL test5: bob should be second")
	print("PASS test5: rank_players")
	passed += 1

	print("\n%d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd hot-garbage-godot
godot --headless --script src/logic/test_scoring.gd
```

Expected: error about `Scoring` not found or similar.

- [ ] **Step 3: Implement scoring.gd**

Create `hot-garbage-godot/src/logic/scoring.gd`:

```gdscript
class_name Scoring

const SET_THRESHOLD := 3

static func score_player(artifacts: Array, cash: int, categories: Dictionary) -> Dictionary:
	var by_cat: Dictionary = {}
	for a in artifacts:
		if not by_cat.has(a.category):
			by_cat[a.category] = []
		by_cat[a.category].append(a)

	var breakdown: Dictionary = {}
	var total: int = cash

	for cat in by_cat:
		var items: Array = by_cat[cat]
		var raw: int = 0
		for a in items:
			raw += a.value
		var completed: bool = items.size() >= SET_THRESHOLD
		var mult: float = categories[cat].setBonus if (completed and categories.has(cat)) else 1.0
		var scored: int = roundi(raw * mult)
		breakdown[cat] = {
			"count": items.size(),
			"raw": raw,
			"multiplier": mult,
			"completed": completed,
			"scored": scored,
		}
		total += scored

	return {"total": total, "cash": cash, "breakdown": breakdown}

static func rank_players(players: Dictionary, categories: Dictionary) -> Array:
	var result: Array = []
	for id in players:
		var p = players[id]
		var scored: Dictionary = score_player(p.artifacts, p.cash, categories)
		scored["id"] = id
		result.append(scored)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.total > b.total)
	return result
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd hot-garbage-godot
godot --headless --script src/logic/test_scoring.gd
```

Expected output:
```
PASS test1: cash only
PASS test2: incomplete set, no bonus
PASS test3: completed set with bonus
PASS test4: mixed categories, no bonuses
PASS test5: rank_players

5 passed, 0 failed
```

- [ ] **Step 5: Commit**

```bash
git add src/logic/scoring.gd src/logic/test_scoring.gd
git commit -m "feat: add scoring.gd — pure set-bonus scoring logic"
```

---

## Task 3: game_engine.gd

**Files:**
- Create: `src/logic/game_engine.gd`
- Create: `src/logic/test_game_engine.gd`

**Interfaces:**
- Consumes: `Scoring.rank_players`, `Scoring.SET_THRESHOLD`
- Produces:
  - `GameEngine.new(opts: Dictionary, artifact_data: Dictionary) -> GameEngine`
    - opts keys: `seed: int, player_ids: Array[String], startingCash: int, chaosChance: float, bankFloor: int, rounds: int`
  - `engine.start_auction(auctioneer_id: String) -> Dictionary` — public artifact `{id, name, category, flavor}`
  - `engine.get_auctioneer_artifact() -> Dictionary` — full artifact including `value`
  - `engine.submit_bid(player_id: String, amount: int) -> void`
  - `engine.all_bids_received() -> bool` — true when all non-auctioneer players have submitted
  - `engine.resolve_auction() -> Dictionary` — `{artifact, winner, price, seller_gain}` where winner is player_id or "BANK"
  - `engine.maybe_chaos(last_result: Dictionary) -> Dictionary` — `{}` if no chaos, else `{type, text, extra}`
  - `engine.get_final_scores() -> Array` — calls Scoring.rank_players with game flags applied
  - `engine.get_rounds() -> int`
  - `engine.get_order() -> Array[String]`

- [ ] **Step 1: Write the failing tests**

Create `hot-garbage-godot/src/logic/test_game_engine.gd`:

```gdscript
extends SceneTree

func _init() -> void:
	var passed := 0
	var failed := 0

	var artifact_data := {
		"categories": {
			"antiquities": {"name": "Antiquities", "setBonus": 2.0},
			"junk": {"name": "Junk", "setBonus": 1.5},
		},
		"artifacts": [
			{"id": "a1", "name": "Old Vase", "category": "antiquities", "value": 500, "tag": "solid", "flavor": "Nice pot."},
			{"id": "a2", "name": "Old Coin", "category": "antiquities", "value": 200, "tag": "modest", "flavor": "Round."},
			{"id": "a3", "name": "Junk Box", "category": "junk", "value": 50, "tag": "trash", "flavor": "Trash."},
			{"id": "a4", "name": "Old Cup", "category": "antiquities", "value": 300, "tag": "solid", "flavor": "Cup."},
			{"id": "a5", "name": "More Junk", "category": "junk", "value": 30, "tag": "trash", "flavor": "Junk."},
			{"id": "a6", "name": "Rock", "category": "junk", "value": 10, "tag": "trash", "flavor": "Rock."},
		]
	}

	# Test 1: start_auction returns public artifact (no value)
	var engine1 = GameEngine.new({"seed": 1, "player_ids": ["alice", "bob"]}, artifact_data)
	var pub = engine1.start_auction("alice")
	assert(pub.has("name"), "FAIL test1: public artifact missing name")
	assert(pub.has("category"), "FAIL test1: public artifact missing category")
	assert(pub.has("flavor"), "FAIL test1: public artifact missing flavor")
	assert(not pub.has("value"), "FAIL test1: public artifact must NOT have value")
	print("PASS test1: start_auction public artifact has no value")
	passed += 1

	# Test 2: get_auctioneer_artifact returns full artifact with value
	var full = engine1.get_auctioneer_artifact()
	assert(full.has("value"), "FAIL test2: auctioneer artifact must have value")
	assert(full.value > 0, "FAIL test2: value should be positive")
	print("PASS test2: get_auctioneer_artifact has value")
	passed += 1

	# Test 3: all_bids_received — false until all non-auctioneers submit
	# alice is auctioneer, bob must submit
	assert(engine1.all_bids_received() == false, "FAIL test3: should be false before bob submits")
	engine1.submit_bid("bob", 100)
	assert(engine1.all_bids_received() == true, "FAIL test3: should be true after bob submits")
	print("PASS test3: all_bids_received tracks correctly")
	passed += 1

	# Test 4: resolve_auction — bob wins
	var result = engine1.resolve_auction()
	assert(result.winner == "bob", "FAIL test4: bob should win")
	assert(result.price == 100, "FAIL test4: price should be 100")
	assert(result.seller_gain == 100, "FAIL test4: alice gains 100")
	print("PASS test4: resolve_auction winner + price correct")
	passed += 1

	# Test 5: bank floor if no bids
	var engine2 = GameEngine.new({"seed": 42, "player_ids": ["alice", "bob"], "bankFloor": 25}, artifact_data)
	engine2.start_auction("alice")
	engine2.submit_bid("bob", 0)  # bob passes
	var result2 = engine2.resolve_auction()
	assert(result2.winner == "BANK", "FAIL test5: bank should win with zero bids")
	assert(result2.price == 25, "FAIL test5: bank floor should be 25")
	print("PASS test5: bank floor purchase")
	passed += 1

	# Test 6: get_rounds respects cap of 6
	var engine3 = GameEngine.new({"seed": 1, "player_ids": ["a","b","c","d","e","f","g","h"]}, artifact_data)
	assert(engine3.get_rounds() == 6, "FAIL test6: rounds should be capped at 6 got %d" % engine3.get_rounds())
	print("PASS test6: rounds capped at 6")
	passed += 1

	# Test 7: auctioneer cannot bid on their own auction
	var engine4 = GameEngine.new({"seed": 1, "player_ids": ["alice", "bob"]}, artifact_data)
	engine4.start_auction("alice")
	engine4.submit_bid("alice", 9999)  # should be ignored
	engine4.submit_bid("bob", 50)
	assert(engine4.all_bids_received() == true, "FAIL test7: should be ready after bob submits")
	var result4 = engine4.resolve_auction()
	assert(result4.winner == "bob", "FAIL test7: alice's self-bid should be ignored")
	print("PASS test7: auctioneer cannot bid on own auction")
	passed += 1

	print("\n%d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd hot-garbage-godot
godot --headless --script src/logic/test_game_engine.gd
```

Expected: error about `GameEngine` not found.

- [ ] **Step 3: Implement game_engine.gd**

Create `hot-garbage-godot/src/logic/game_engine.gd`:

```gdscript
class_name GameEngine

const EVENTS := [
	{"id": "market_crash",      "text": "MARKET CRASH — Forgeries score double this game."},
	{"id": "museum_heist",      "text": "MUSEUM HEIST — a random player loses their priciest artifact to the Bank."},
	{"id": "bidding_frenzy",    "text": "BIDDING FRENZY — next auction, everyone must bid at least 50."},
	{"id": "insider_tip",       "text": "INSIDER TIP — a random bidder secretly learns the next true band."},
	{"id": "counterfeit_scare", "text": "COUNTERFEIT SCARE — next Forgery is halved at reveal."},
]

var _rng_state: int
var _deck: Array
var _deck_ptr: int
var _categories: Dictionary
var _players: Dictionary
var _order: Array
var _flags: Dictionary
var _rounds: int
var _starting_cash: int
var _chaos_chance: float
var _bank_floor: int

var _current_artifact: Dictionary
var _current_auctioneer: String
var _submitted_bids: Dictionary

func _init(opts: Dictionary, artifact_data: Dictionary) -> void:
	_init_rng(opts.get("seed", 1))
	_categories = artifact_data.categories
	_deck = _shuffle(artifact_data.artifacts.duplicate(true))
	_deck_ptr = 0

	_starting_cash = opts.get("startingCash", 1000)
	_chaos_chance = opts.get("chaosChance", 0.25)
	_bank_floor = opts.get("bankFloor", 25)
	var player_ids: Array = opts.player_ids
	_rounds = mini(opts.get("rounds", player_ids.size()), 6)

	_players = {}
	for id in player_ids:
		_players[id] = {"id": id, "cash": _starting_cash, "artifacts": []}
	_order = player_ids.duplicate()
	_flags = {"forgeriesDouble": false}
	_submitted_bids = {}

func start_auction(auctioneer_id: String) -> Dictionary:
	_current_auctioneer = auctioneer_id
	_current_artifact = _draw()
	_submitted_bids = {}
	return {
		"id": _current_artifact.id,
		"name": _current_artifact.name,
		"category": _current_artifact.category,
		"flavor": _current_artifact.flavor,
	}

func get_auctioneer_artifact() -> Dictionary:
	return _current_artifact.duplicate()

func submit_bid(player_id: String, amount: int) -> void:
	if player_id == _current_auctioneer:
		return
	if not _players.has(player_id):
		return
	if _submitted_bids.has(player_id):
		return
	var player: Dictionary = _players[player_id]
	_submitted_bids[player_id] = clampi(amount, 0, player.cash)

func all_bids_received() -> bool:
	for id in _players:
		if id != _current_auctioneer and not _submitted_bids.has(id):
			return false
	return true

func resolve_auction() -> Dictionary:
	var seller: Dictionary = _players[_current_auctioneer]
	var bids: Array = []
	for id in _submitted_bids:
		bids.append({"id": id, "bid": _submitted_bids[id]})
	bids.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.bid > b.bid)

	var result: Dictionary
	if bids.is_empty() or bids[0].bid <= 0:
		seller.cash += _bank_floor
		result = {
			"artifact": _current_artifact.duplicate(),
			"winner": "BANK",
			"price": _bank_floor,
			"seller_gain": _bank_floor,
		}
	else:
		var top: Dictionary = bids[0]
		var winner: Dictionary = _players[top.id]
		winner.cash -= top.bid
		winner.artifacts.append(_current_artifact.duplicate())
		seller.cash += top.bid
		result = {
			"artifact": _current_artifact.duplicate(),
			"winner": top.id,
			"price": top.bid,
			"seller_gain": top.bid,
		}
	return result

func maybe_chaos(last_result: Dictionary) -> Dictionary:
	if _rng() >= _chaos_chance:
		return {}
	if _rng() < 0.5:
		if last_result.winner != "BANK":
			var artifact: Dictionary = last_result.artifact
			var verdict := "A STEAL" if artifact.value > last_result.price else "ROBBED"
			return {
				"type": "appraiser",
				"text": '"%s" truly worth %d — %s got %s.' % [artifact.name, artifact.value, last_result.winner, verdict],
				"extra": {},
			}
	else:
		var ev: Dictionary = _pick(EVENTS)
		var extra: Dictionary = {}
		if ev.id == "market_crash":
			_flags.forgeriesDouble = true
		elif ev.id == "museum_heist":
			var victim: String = _pick(_order)
			var arts: Array = _players[victim].artifacts
			if not arts.is_empty():
				var idx := 0
				for i in range(1, arts.size()):
					if arts[i].value > arts[idx].value:
						idx = i
				var lost: Dictionary = arts[idx]
				arts.remove_at(idx)
				extra = {"victim": victim, "lost_name": lost.name}
		return {"type": "event", "text": ev.text, "extra": extra}
	return {}

func get_final_scores() -> Array:
	var cats: Dictionary = _categories.duplicate(true)
	if _flags.forgeriesDouble and cats.has("forgeries"):
		cats.forgeries.setBonus *= 2.0
	return Scoring.rank_players(_players, cats)

func get_rounds() -> int:
	return _rounds

func get_order() -> Array:
	return _order.duplicate()

# --- RNG (mulberry32, matches JS engine exactly) ---

func _init_rng(seed_val: int) -> void:
	_rng_state = seed_val & 0xFFFFFFFF

func _rng() -> float:
	_rng_state = (_rng_state + 0x6D2B79F5) & 0xFFFFFFFF
	var t: int = ((_rng_state ^ (_rng_state >> 15)) * (1 | _rng_state)) & 0xFFFFFFFF
	t = (t + ((t ^ (t >> 7)) * (61 | t))) & 0xFFFFFFFF
	t = (t ^ (t >> 14)) & 0xFFFFFFFF
	return float(t) / 4294967296.0

func _shuffle(arr: Array) -> Array:
	var a: Array = arr.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j: int = int(_rng() * (i + 1))
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp
	return a

func _draw() -> Dictionary:
	if _deck_ptr >= _deck.size():
		_deck = _shuffle(_deck)
		_deck_ptr = 0
	var a: Dictionary = _deck[_deck_ptr]
	_deck_ptr += 1
	return a

func _pick(arr: Array):
	return arr[int(_rng() * arr.size())]
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd hot-garbage-godot
godot --headless --script src/logic/test_game_engine.gd
```

Expected:
```
PASS test1: start_auction public artifact has no value
PASS test2: get_auctioneer_artifact has value
PASS test3: all_bids_received tracks correctly
PASS test4: resolve_auction winner + price correct
PASS test5: bank floor purchase
PASS test6: rounds capped at 6
PASS test7: auctioneer cannot bid on own auction

7 passed, 0 failed
```

- [ ] **Step 5: Commit**

```bash
git add src/logic/game_engine.gd src/logic/test_game_engine.gd
git commit -m "feat: add game_engine.gd — async bid collection port of JS engine"
```

---

## Task 4: network_manager.gd

**Files:**
- Modify: `src/network/network_manager.gd`

**Interfaces:**
- Consumes: nothing (bottom of dependency graph)
- Produces (signals):
  - `player_registered(peer_id: int, player_name: String)`
  - `player_disconnected(peer_id: int)`
  - `connection_failed()`
  - `server_disconnected()`
  - `bid_received(peer_id: int, amount: int)` — emitted on host when a client's bid arrives
- Produces (methods):
  - `NetworkManager.host(player_name: String) -> void`
  - `NetworkManager.join(ip: String, player_name: String) -> void`
  - `NetworkManager.is_host() -> bool`
  - `NetworkManager.get_peer_ids() -> Array` — all connected peers (not including self)
  - `NetworkManager.player_names: Dictionary` — peer_id (int) -> name (String); peer_id 1 = host
- Produces (RPCs called by GameServer — defined here so all multiplayer calls stay in one file):
  - `NetworkManager.rpc_reveal_to_auctioneer(auctioneer_peer_id: int, artifact: Dictionary)`
  - `NetworkManager.rpc_start_bidding(artifact: Dictionary)`
  - `NetworkManager.rpc_show_bid_result(result: Dictionary)`
  - `NetworkManager.rpc_show_chaos(chaos: Dictionary)`
  - `NetworkManager.rpc_show_final_scores(ranking: Array)`
  - `NetworkManager.rpc_advance_scene(scene_path: String)`

- [ ] **Step 1: Replace stub with full implementation**

Replace `hot-garbage-godot/src/network/network_manager.gd` with:

```gdscript
extends Node

signal player_registered(peer_id: int, player_name: String)
signal player_disconnected(peer_id: int)
signal connection_failed()
signal server_disconnected()
signal bid_received(peer_id: int, amount: int)

const PORT := 7777
const MAX_PEERS := 8

var player_names: Dictionary = {}  # int -> String
var _local_name: String = ""

# --- Transport (Steam GodotSteam replaces these three methods only) ---

func host(player_name: String) -> void:
	_local_name = player_name
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PEERS)
	assert(err == OK, "Failed to create server: %d" % err)
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	player_names[1] = player_name

func join(ip: String, player_name: String) -> void:
	_local_name = player_name
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	assert(err == OK, "Failed to connect: %d" % err)
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func is_host() -> bool:
	return multiplayer.is_server()

func get_peer_ids() -> Array:
	return multiplayer.get_peers()

# --- Peer lifecycle ---

func _on_peer_connected(_peer_id: int) -> void:
	pass  # client registers themselves via RPC

func _on_peer_disconnected(peer_id: int) -> void:
	player_names.erase(peer_id)
	player_disconnected.emit(peer_id)

func _on_connected_to_server() -> void:
	_register_self.rpc_id(1, _local_name)

func _on_connection_failed() -> void:
	connection_failed.emit()

func _on_server_disconnected() -> void:
	server_disconnected.emit()

# --- Registration ---

@rpc("any_peer", "reliable")
func _register_self(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	player_names[sender_id] = player_name
	# Tell everyone (including sender) about the new player
	_sync_player_joined.rpc(sender_id, player_name)
	# Send existing players to new client
	for id in player_names:
		if id != sender_id:
			_sync_player_joined.rpc_id(sender_id, id, player_names[id])

@rpc("authority", "reliable", "call_local")
func _sync_player_joined(peer_id: int, player_name: String) -> void:
	player_names[peer_id] = player_name
	player_registered.emit(peer_id, player_name)

# --- Game RPCs (called by GameServer on host; received and acted on by all clients) ---

# Reveal full artifact to one auctioneer peer only
func rpc_reveal_to_auctioneer(auctioneer_peer_id: int, artifact: Dictionary) -> void:
	_recv_reveal_to_auctioneer.rpc_id(auctioneer_peer_id, artifact)

@rpc("authority", "reliable")
func _recv_reveal_to_auctioneer(artifact: Dictionary) -> void:
	get_tree().get_root().propagate_call("on_auctioneer_reveal", [artifact], true)

# Broadcast public artifact to all bidders
func rpc_start_bidding(artifact: Dictionary) -> void:
	_recv_start_bidding.rpc(artifact)

@rpc("authority", "reliable", "call_local")
func _recv_start_bidding(artifact: Dictionary) -> void:
	get_tree().get_root().propagate_call("on_start_bidding", [artifact], true)

# Broadcast auction result
func rpc_show_bid_result(result: Dictionary) -> void:
	_recv_show_bid_result.rpc(result)

@rpc("authority", "reliable", "call_local")
func _recv_show_bid_result(result: Dictionary) -> void:
	get_tree().get_root().propagate_call("on_show_bid_result", [result], true)

# Broadcast chaos event (may be empty dict = no chaos)
func rpc_show_chaos(chaos: Dictionary) -> void:
	_recv_show_chaos.rpc(chaos)

@rpc("authority", "reliable", "call_local")
func _recv_show_chaos(chaos: Dictionary) -> void:
	get_tree().get_root().propagate_call("on_show_chaos", [chaos], true)

# Broadcast final scores
func rpc_show_final_scores(ranking: Array) -> void:
	_recv_show_final_scores.rpc(ranking)

@rpc("authority", "reliable", "call_local")
func _recv_show_final_scores(ranking: Array) -> void:
	get_tree().get_root().propagate_call("on_show_final_scores", [ranking], true)

# Host drives all scene transitions
func rpc_advance_scene(scene_path: String) -> void:
	_recv_advance_scene.rpc(scene_path)

@rpc("authority", "reliable", "call_local")
func _recv_advance_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

# --- Bid submission (client → host) ---

func submit_bid(amount: int) -> void:
	_recv_bid.rpc_id(1, amount)

@rpc("any_peer", "reliable")
func _recv_bid(amount: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	bid_received.emit(sender_id, amount)
```

- [ ] **Step 2: Verify the autoload is registered**

Open the Godot editor (or check `project.godot`) and confirm `NetworkManager` appears in Project → Project Settings → Autoload pointing to `res://src/network/network_manager.gd`.

- [ ] **Step 3: Commit**

```bash
git add src/network/network_manager.gd
git commit -m "feat: add NetworkManager autoload — ENet + all RPC definitions"
```

---

## Task 5: game_server.gd

**Files:**
- Modify: `src/server/game_server.gd`

**Interfaces:**
- Consumes: `GameEngine`, `Scoring`, `NetworkManager`
- Produces: drives the full game loop on the host; all scene transitions via NetworkManager RPCs

The host-only game flow:
1. `start_game(player_ids)` — create engine, begin round 1
2. For each round, for each player in order: run one auction turn
3. Each auction turn: start_auction → rpc reveal + bidding → collect bids → auto-resolve → rpc result + chaos → next turn
4. After all rounds: rpc final scores → advance to final_scores scene

- [ ] **Step 1: Replace stub with full implementation**

Replace `hot-garbage-godot/src/server/game_server.gd` with:

```gdscript
extends Node

var _engine: GameEngine = null
var _artifact_data: Dictionary = {}
var _current_round: int = 0
var _current_turn_idx: int = 0  # index into _order for this round
var _order: Array = []
var _pending_force_resolve: bool = false

func _ready() -> void:
	if not NetworkManager.is_host():
		return
	NetworkManager.bid_received.connect(_on_bid_received)
	var file := FileAccess.open("res://data/artifacts.json", FileAccess.READ)
	_artifact_data = JSON.parse_string(file.get_as_text())

func start_game(player_ids: Array) -> void:
	if not NetworkManager.is_host():
		return
	_engine = GameEngine.new(
		{"seed": randi(), "player_ids": player_ids},
		_artifact_data
	)
	_order = _engine.get_order()
	_current_round = 1
	_current_turn_idx = 0
	_begin_turn()

func _begin_turn() -> void:
	if _current_round > _engine.get_rounds():
		_end_game()
		return

	var auctioneer_id: String = _order[_current_turn_idx]
	var auctioneer_peer_id: int = _peer_id_for_player(auctioneer_id)

	var public_artifact: Dictionary = _engine.start_auction(auctioneer_id)
	var full_artifact: Dictionary = _engine.get_auctioneer_artifact()

	# Send full artifact (with value) only to the auctioneer
	NetworkManager.rpc_reveal_to_auctioneer(auctioneer_peer_id, full_artifact)
	# Send public artifact (no value) to everyone — call_local means host client also receives
	NetworkManager.rpc_start_bidding(public_artifact)

func _on_bid_received(peer_id: int, amount: int) -> void:
	if _engine == null:
		return
	var player_id: String = _player_id_for_peer(peer_id)
	_engine.submit_bid(player_id, amount)
	if _engine.all_bids_received():
		_resolve_current_auction()

# Host can force-resolve (escape hatch for dropped clients)
func force_resolve() -> void:
	if _engine == null or not NetworkManager.is_host():
		return
	_resolve_current_auction()

func _resolve_current_auction() -> void:
	var result: Dictionary = _engine.resolve_auction()
	var chaos: Dictionary = _engine.maybe_chaos(result)
	NetworkManager.rpc_show_bid_result(result)
	NetworkManager.rpc_show_chaos(chaos)
	# Advance turn pointer
	_current_turn_idx += 1
	if _current_turn_idx >= _order.size():
		_current_turn_idx = 0
		_current_round += 1
	# Small delay so players can read the result before moving on
	await get_tree().create_timer(3.0).timeout
	_begin_turn()

func _end_game() -> void:
	var ranking: Array = _engine.get_final_scores()
	NetworkManager.rpc_show_final_scores(ranking)
	await get_tree().create_timer(1.0).timeout
	NetworkManager.rpc_advance_scene("res://src/scenes/final_scores.tscn")

# --- Peer ↔ Player ID mapping ---
# player_ids in the engine are strings matching NetworkManager.player_names values.
# Map by position: _order[i] corresponds to sorted peer_ids[i].

func _peer_id_for_player(player_id: String) -> int:
	for peer_id in NetworkManager.player_names:
		if NetworkManager.player_names[peer_id] == player_id:
			return peer_id
	return 1  # fallback to host

func _player_id_for_peer(peer_id: int) -> String:
	return NetworkManager.player_names.get(peer_id, "unknown")
```

- [ ] **Step 2: Verify autoload in project.godot**

Confirm `GameServer="*res://src/server/game_server.gd"` is in `[autoload]` in `project.godot`.

- [ ] **Step 3: Commit**

```bash
git add src/server/game_server.gd
git commit -m "feat: add GameServer autoload — host-only game loop orchestration"
```

---

## Task 6: MainMenu Scene

**Files:**
- Modify: `src/scenes/main_menu.gd`

**Interfaces:**
- Consumes: `NetworkManager.host()`, `NetworkManager.join()`, `NetworkManager.player_registered` signal
- On host: after hosting, advances to `res://src/scenes/lobby.tscn`
- On client: after `player_registered` fires, advances to `res://src/scenes/lobby.tscn`

- [ ] **Step 1: Implement main_menu.gd**

Replace `hot-garbage-godot/src/scenes/main_menu.gd` with:

```gdscript
extends Control

var _name_field: LineEdit
var _ip_field: LineEdit
var _status_label: Label

func _ready() -> void:
	_build_ui()
	NetworkManager.player_registered.connect(_on_registered)
	NetworkManager.connection_failed.connect(_on_connection_failed)

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(400, 300)
	add_child(vbox)

	var title := Label.new()
	title.text = "HOT GARBAGE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_name_field = LineEdit.new()
	_name_field.placeholder_text = "Your name"
	vbox.add_child(_name_field)

	_ip_field = LineEdit.new()
	_ip_field.placeholder_text = "Host IP (leave blank to host)"
	vbox.add_child(_ip_field)

	var host_btn := Button.new()
	host_btn.text = "Host Game"
	host_btn.pressed.connect(_on_host_pressed)
	vbox.add_child(host_btn)

	var join_btn := Button.new()
	join_btn.text = "Join Game"
	join_btn.pressed.connect(_on_join_pressed)
	vbox.add_child(join_btn)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status_label)

func _on_host_pressed() -> void:
	var name := _name_field.text.strip_edges()
	if name.is_empty():
		_status_label.text = "Enter your name first."
		return
	_status_label.text = "Hosting..."
	NetworkManager.host(name)
	get_tree().change_scene_to_file("res://src/scenes/lobby.tscn")

func _on_join_pressed() -> void:
	var name := _name_field.text.strip_edges()
	var ip := _ip_field.text.strip_edges()
	if name.is_empty():
		_status_label.text = "Enter your name first."
		return
	if ip.is_empty():
		ip = "127.0.0.1"
	_status_label.text = "Connecting to %s..." % ip
	NetworkManager.join(ip, name)

func _on_registered(_peer_id: int, _name: String) -> void:
	# Only the local client fires this on a successful join
	if not NetworkManager.is_host():
		get_tree().change_scene_to_file("res://src/scenes/lobby.tscn")

func _on_connection_failed() -> void:
	_status_label.text = "Connection failed."
```

- [ ] **Step 2: Run the game and verify**

```bash
cd hot-garbage-godot
godot .
```

Expected: window opens showing "HOT GARBAGE", name field, IP field, Host/Join buttons. Clicking Host with a name advances to the Lobby scene (stub). Clicking Join without a name shows the error message.

- [ ] **Step 3: Commit**

```bash
git add src/scenes/main_menu.gd
git commit -m "feat: main menu — host/join UI with name entry"
```

---

## Task 7: Lobby Scene

**Files:**
- Modify: `src/scenes/lobby.gd`

**Interfaces:**
- Consumes: `NetworkManager.player_names`, `NetworkManager.player_registered` signal, `NetworkManager.player_disconnected` signal
- Host only: Start button calls `GameServer.start_game(player_ids)` then `NetworkManager.rpc_advance_scene`
- Clients: wait for `rpc_advance_scene` from host

- [ ] **Step 1: Implement lobby.gd**

Replace `hot-garbage-godot/src/scenes/lobby.gd` with:

```gdscript
extends Control

var _player_list: VBoxContainer
var _start_btn: Button
var _status_label: Label

func _ready() -> void:
	_build_ui()
	NetworkManager.player_registered.connect(_on_player_changed)
	NetworkManager.player_disconnected.connect(_on_player_changed)
	_refresh_player_list()

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(400, 400)
	add_child(vbox)

	var title := Label.new()
	title.text = "Lobby"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_player_list = VBoxContainer.new()
	vbox.add_child(_player_list)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status_label)

	if NetworkManager.is_host():
		_start_btn = Button.new()
		_start_btn.text = "Start Game"
		_start_btn.pressed.connect(_on_start_pressed)
		vbox.add_child(_start_btn)

func _refresh_player_list() -> void:
	for child in _player_list.get_children():
		child.queue_free()
	for peer_id in NetworkManager.player_names:
		var lbl := Label.new()
		lbl.text = "• %s" % NetworkManager.player_names[peer_id]
		_player_list.add_child(lbl)
	var count := NetworkManager.player_names.size()
	if NetworkManager.is_host():
		_status_label.text = "%d player(s) — need 4 to start (or start anyway for testing)" % count

func _on_player_changed(_a = null, _b = null) -> void:
	_refresh_player_list()

func _on_start_pressed() -> void:
	var player_ids: Array = []
	for peer_id in NetworkManager.player_names:
		player_ids.append(NetworkManager.player_names[peer_id])
	GameServer.start_game(player_ids)
	# GameServer will drive scene transitions from here
```

- [ ] **Step 2: Run and verify**

Start two Godot instances. In instance 1: enter a name, click Host — should see the Lobby with your name listed. In instance 2: enter a name, enter `127.0.0.1`, click Join — should also arrive at the Lobby, both names visible.

- [ ] **Step 3: Commit**

```bash
git add src/scenes/lobby.gd
git commit -m "feat: lobby scene — player list with host start button"
```

---

## Task 8: AuctioneerView + BidderView Scenes

**Files:**
- Modify: `src/scenes/auctioneer_view.gd`
- Modify: `src/scenes/bidder_view.gd`

The two scenes are shown simultaneously on different clients for the same auction. AuctioneerView is shown only on the auctioneer's peer; BidderView on everyone else. NetworkManager's propagate_call routes `on_auctioneer_reveal` and `on_start_bidding` to whichever scene is currently loaded.

**Interfaces:**
- `AuctioneerView.on_auctioneer_reveal(artifact: Dictionary)` — called by NetworkManager RPC handler
- `BidderView.on_start_bidding(artifact: Dictionary)` — called by NetworkManager RPC handler
- Both scenes show bid count ticking up; auto-advance is driven by GameServer (it calls `rpc_show_bid_result` when done)

- [ ] **Step 1: Implement auctioneer_view.gd**

Replace `hot-garbage-godot/src/scenes/auctioneer_view.gd` with:

```gdscript
extends Control

var _artifact_label: Label
var _value_label: Label
var _bid_count_label: Label
var _force_btn: Button
var _expected_bids: int = 0
var _received_bids: int = 0

func _ready() -> void:
	_build_ui()
	# Count expected bids = all peers minus self
	_expected_bids = NetworkManager.get_peer_ids().size()

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(500, 400)
	add_child(vbox)

	var role_lbl := Label.new()
	role_lbl.text = "YOU ARE THE AUCTIONEER"
	role_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(role_lbl)

	_artifact_label = Label.new()
	_artifact_label.text = "Waiting for auction to start..."
	_artifact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_artifact_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_artifact_label)

	_value_label = Label.new()
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_value_label)

	_bid_count_label = Label.new()
	_bid_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_bid_count_label)

	if NetworkManager.is_host():
		_force_btn = Button.new()
		_force_btn.text = "Force Resolve (host escape hatch)"
		_force_btn.pressed.connect(func(): GameServer.force_resolve())
		vbox.add_child(_force_btn)

func on_auctioneer_reveal(artifact: Dictionary) -> void:
	_received_bids = 0
	_artifact_label.text = "%s\n%s\n\n\"%s\"" % [artifact.name, artifact.category.to_upper(), artifact.flavor]
	_value_label.text = "TRUE VALUE: §%d" % artifact.value
	_bid_count_label.text = "Bids received: 0 / %d" % _expected_bids
	NetworkManager.bid_received.connect(_on_bid_count_update)

func _on_bid_count_update(_peer_id: int, _amount: int) -> void:
	_received_bids += 1
	_bid_count_label.text = "Bids received: %d / %d" % [_received_bids, _expected_bids]
```

- [ ] **Step 2: Implement bidder_view.gd**

Replace `hot-garbage-godot/src/scenes/bidder_view.gd` with:

```gdscript
extends Control

var _artifact_label: Label
var _cash_label: Label
var _bid_input: SpinBox
var _submit_btn: Button
var _status_label: Label

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(500, 400)
	add_child(vbox)

	_artifact_label = Label.new()
	_artifact_label.text = "Waiting for auction..."
	_artifact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_artifact_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_artifact_label)

	_cash_label = Label.new()
	_cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_cash_label)

	var bid_row := HBoxContainer.new()
	vbox.add_child(bid_row)

	var bid_lbl := Label.new()
	bid_lbl.text = "Your bid: §"
	bid_row.add_child(bid_lbl)

	_bid_input = SpinBox.new()
	_bid_input.min_value = 0
	_bid_input.max_value = 99999
	_bid_input.step = 1
	bid_row.add_child(_bid_input)

	_submit_btn = Button.new()
	_submit_btn.text = "Submit Bid"
	_submit_btn.pressed.connect(_on_submit_pressed)
	vbox.add_child(_submit_btn)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status_label)

func on_start_bidding(artifact: Dictionary) -> void:
	_artifact_label.text = "%s\n%s\n\n\"%s\"" % [artifact.name, artifact.category.to_upper(), artifact.flavor]
	var my_name := NetworkManager.player_names.get(multiplayer.get_unique_id(), "?")
	# Show cash if we can find it — GameServer holds this; for now show a placeholder
	_cash_label.text = "Place your bid"
	_bid_input.value = 0
	_submit_btn.disabled = false
	_status_label.text = ""

func _on_submit_pressed() -> void:
	_submit_btn.disabled = true
	_status_label.text = "Bid submitted. Waiting for others..."
	NetworkManager.submit_bid(int(_bid_input.value))
```

- [ ] **Step 3: Wire scene routing in GameServer**

The auctioneer needs AuctioneerView; everyone else needs BidderView. Two changes required:

**First**, add a targeted scene-advance helper to `src/network/network_manager.gd` (append after `rpc_advance_scene`):

```gdscript
func rpc_advance_scene_to_peer(peer_id: int, scene_path: String) -> void:
	_recv_advance_scene.rpc_id(peer_id, scene_path)
```

**Second**, replace the `_begin_turn` function in `src/server/game_server.gd`:

```gdscript
func _begin_turn() -> void:
	if _current_round > _engine.get_rounds():
		_end_game()
		return

	var auctioneer_id: String = _order[_current_turn_idx]
	var auctioneer_peer_id: int = _peer_id_for_player(auctioneer_id)

	# Route each non-host peer to the correct scene
	for peer_id in NetworkManager.get_peer_ids():
		var scene := "res://src/scenes/auctioneer_view.tscn" \
			if peer_id == auctioneer_peer_id \
			else "res://src/scenes/bidder_view.tscn"
		NetworkManager.rpc_advance_scene_to_peer(peer_id, scene)

	# Route the host's own display
	var host_scene := "res://src/scenes/auctioneer_view.tscn" \
		if auctioneer_peer_id == 1 \
		else "res://src/scenes/bidder_view.tscn"
	get_tree().change_scene_to_file(host_scene)

	# Brief wait for scene load, then send artifact data
	await get_tree().create_timer(0.5).timeout

	var public_artifact: Dictionary = _engine.start_auction(auctioneer_id)
	var full_artifact: Dictionary = _engine.get_auctioneer_artifact()

	NetworkManager.rpc_reveal_to_auctioneer(auctioneer_peer_id, full_artifact)
	NetworkManager.rpc_start_bidding(public_artifact)
```

- [ ] **Step 4: Commit**

```bash
git add src/scenes/auctioneer_view.gd src/scenes/bidder_view.gd src/server/game_server.gd src/network/network_manager.gd
git commit -m "feat: auctioneer and bidder views — per-role auction screens"
```

---

## Task 9: BidReveal Scene

**Files:**
- Modify: `src/scenes/bid_reveal.gd`

Both `on_show_bid_result` and `on_show_chaos` are called on this scene by NetworkManager's propagate_call. The scene displays both, then GameServer's timer advances to the next turn automatically.

- [ ] **Step 1: Implement bid_reveal.gd**

Replace `hot-garbage-godot/src/scenes/bid_reveal.gd` with:

```gdscript
extends Control

var _result_label: Label
var _chaos_label: Label

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(500, 400)
	add_child(vbox)

	_result_label = Label.new()
	_result_label.text = "Auction resolving..."
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_result_label)

	_chaos_label = Label.new()
	_chaos_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chaos_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_chaos_label)

func on_show_bid_result(result: Dictionary) -> void:
	if result.winner == "BANK":
		_result_label.text = "No takers. Bank paid §%d." % result.price
	else:
		var winner_name := NetworkManager.player_names.get(
			_peer_id_for_name(result.winner), result.winner)
		_result_label.text = "%s won for §%d!" % [winner_name, result.price]

func on_show_chaos(chaos: Dictionary) -> void:
	if chaos.is_empty():
		return
	if chaos.type == "appraiser":
		_chaos_label.text = "APPRAISER: %s" % chaos.text
	else:
		_chaos_label.text = "EVENT: %s" % chaos.text
		if chaos.extra.has("victim") and chaos.extra.has("lost_name"):
			_chaos_label.text += "\n%s loses \"%s\"!" % [chaos.extra.victim, chaos.extra.lost_name]

func _peer_id_for_name(player_name: String) -> int:
	for pid in NetworkManager.player_names:
		if NetworkManager.player_names[pid] == player_name:
			return pid
	return -1
```

- [ ] **Step 2: Route bid reveal in GameServer**

Modify `_resolve_current_auction` in `game_server.gd` to advance all clients to bid_reveal before broadcasting the result. Add before the rpc calls:

```gdscript
func _resolve_current_auction() -> void:
	var result: Dictionary = _engine.resolve_auction()
	var chaos: Dictionary = _engine.maybe_chaos(result)
	# Route everyone to bid_reveal scene first
	NetworkManager.rpc_advance_scene("res://src/scenes/bid_reveal.tscn")
	await get_tree().create_timer(0.3).timeout
	NetworkManager.rpc_show_bid_result(result)
	NetworkManager.rpc_show_chaos(chaos)
	# Advance turn pointer
	_current_turn_idx += 1
	if _current_turn_idx >= _order.size():
		_current_turn_idx = 0
		_current_round += 1
	await get_tree().create_timer(3.0).timeout
	_begin_turn()
```

- [ ] **Step 3: Commit**

```bash
git add src/scenes/bid_reveal.gd src/server/game_server.gd
git commit -m "feat: bid reveal scene — result + chaos display"
```

---

## Task 10: FinalScores Scene

**Files:**
- Modify: `src/scenes/final_scores.gd`

`on_show_final_scores(ranking: Array)` is called by NetworkManager after GameServer calls `rpc_show_final_scores`. The ranking is already sorted (highest first) and includes full breakdown.

- [ ] **Step 1: Implement final_scores.gd**

Replace `hot-garbage-godot/src/scenes/final_scores.gd` with:

```gdscript
extends Control

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.name = "ScoreList"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "GRAND REVEAL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var waiting := Label.new()
	waiting.name = "WaitingLabel"
	waiting.text = "Waiting for final scores..."
	waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(waiting)

func on_show_final_scores(ranking: Array) -> void:
	var vbox: VBoxContainer = $ScrollContainer/ScoreList if has_node("ScrollContainer/ScoreList") else _find_vbox()
	# Remove waiting label
	for child in vbox.get_children():
		if child.name == "WaitingLabel":
			child.queue_free()

	var medals := ["🏆", "2.", "3.", "4.", "5.", "6.", "7.", "8."]
	for i in range(ranking.size()):
		var p: Dictionary = ranking[i]
		var medal: String = medals[i] if i < medals.size() else "%d." % (i + 1)

		var player_vbox := VBoxContainer.new()
		vbox.add_child(player_vbox)

		var header := Label.new()
		header.text = "%s %s — %d pts  (cash §%d)" % [medal, p.id, p.total, p.cash]
		player_vbox.add_child(header)

		for cat in p.breakdown:
			var b: Dictionary = p.breakdown[cat]
			var set_str := "  SET x%.1f" % b.multiplier if b.completed else ""
			var line := Label.new()
			line.text = "    %s: %d items, raw §%d → §%d%s" % [cat, b.count, b.raw, b.scored, set_str]
			player_vbox.add_child(line)

		var sep := HSeparator.new()
		vbox.add_child(sep)

func _find_vbox() -> VBoxContainer:
	for child in get_children():
		if child is ScrollContainer:
			for grandchild in child.get_children():
				if grandchild is VBoxContainer:
					return grandchild
	return VBoxContainer.new()
```

- [ ] **Step 2: Commit**

```bash
git add src/scenes/final_scores.gd
git commit -m "feat: final scores scene — ranked breakdown with set multipliers"
```

---

## Task 11: Integration Smoke Test

No new files. Run two Godot instances and play through a complete game.

- [ ] **Step 1: Open two terminal windows in `hot-garbage-godot/`**

Window 1 (host):
```bash
godot .
```

Window 2 (second player):
```bash
godot .
```

- [ ] **Step 2: Connect**

In window 1: enter name "Alice", click Host → should land on Lobby showing "Alice".
In window 2: enter name "Bob", enter `127.0.0.1`, click Join → should land on Lobby showing both names.

- [ ] **Step 3: Start game**

In window 1 (host/Alice), click Start Game.

Expected:
- One window shows AuctioneerView with an artifact name, category, flavor, and TRUE VALUE
- Other window shows BidderView with only name, category, flavor — no value visible
- Both windows show the correct role label

- [ ] **Step 4: Submit a bid**

In the BidderView window: enter a bid amount, click Submit Bid.

Expected:
- AuctioneerView bid count increments to "1 / 1"
- Game auto-resolves (all bids in)
- Both windows advance to BidReveal showing winner and price
- After 3 seconds, advances to next turn

- [ ] **Step 5: Play through to final scores**

Continue until all rounds complete. Both windows should arrive at FinalScores with ranked breakdown.

- [ ] **Step 6: Verify privacy invariant**

In the BidderView scene, confirm the UI never shows a `value` field. Use Godot's Remote debugger (Debugger → Remote → Scene tree) to inspect the scene tree during an auction and confirm no Label text contains the true value from the auctioneer's artifact.

- [ ] **Step 7: Final commit**

```bash
git add .
git commit -m "feat: complete Hot Garbage Godot prototype — full networked game loop"
```
