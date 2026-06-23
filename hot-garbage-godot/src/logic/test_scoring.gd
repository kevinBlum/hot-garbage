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
