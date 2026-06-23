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
