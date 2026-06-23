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
