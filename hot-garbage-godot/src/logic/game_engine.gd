class_name GameEngine
extends RefCounted

const _Scoring = preload("res://src/logic/scoring.gd")

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
	return _Scoring.rank_players(_players, cats)

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
