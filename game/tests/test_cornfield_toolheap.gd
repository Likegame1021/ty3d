extends SceneTree
## Pure state transitions: no scenes, disk state, or global RNG are involved.
var checks := 0
var failures := 0
var Catalog
var Heap

func _initialize() -> void:
	call_deferred("run_checks")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func blank_ranks() -> Dictionary:
	return {"builds_by_weapon": {"stick": {}, "corn": {}}, "global_builds": {}}

func full_ranks() -> Dictionary:
	return {
		"builds_by_weapon": {
			"stick": {"damage": 2, "arc": 2, "reach": 2, "knockback": 2, "recovery": 2},
			"corn": {"damage": 2, "knockback": 2},
		},
		"global_builds": {"clear_heal": 2},
	}

func stored_rank(ranks: Dictionary, id: String, weapon: String = "stick") -> int:
	if id == "clear_heal":
		return int(ranks.get("global_builds", {}).get(id, 0))
	return int(ranks.get("builds_by_weapon", {}).get(weapon, {}).get(id, 0))

func check_rejected(result: Dictionary, heap: Dictionary, dice: int, ranks: Dictionary, label: String) -> void:
	check(not bool(result.get("ok", true)), label + " is rejected")
	check(result.get("heap", {}) == heap and result.get("dice", -999) == dice and result.get("ranks", {}) == ranks, label + " changes no state")
	check(not str(result.get("error", "")).is_empty(), label + " returns an explanation")

func run_checks() -> void:
	for path in ["res://scripts/cornfield/build_catalog.gd", "res://scripts/cornfield/toolheap_state.gd"]:
		check(ResourceLoader.exists(path), "required pure module exists: " + path)
	if failures:
		finish()
		return
	Catalog = load("res://scripts/cornfield/build_catalog.gd")
	Heap = load("res://scripts/cornfield/toolheap_state.gd")
	catalog_checks()
	transition_checks()
	validation_checks()
	edge_checks()
	determinism_checks()
	route_checks()
	finish()

func catalog_checks() -> void:
	var ranks := blank_ranks()
	var before := ranks.duplicate(true)
	check(Catalog.allowed_ids("stick", ranks) == ["damage", "arc", "reach", "knockback", "recovery", "clear_heal"], "stick offers six stable original upgrade IDs")
	check(Catalog.allowed_ids("corn", ranks) == ["damage", "knockback", "clear_heal"], "corn offers only effects its receiver can apply")
	check(Catalog.allowed_ids("unknown", ranks).is_empty(), "unknown weapons cannot receive upgrades")
	check(ranks == before, "catalog reads do not mutate ranks")
	ranks.builds_by_weapon.stick.damage = 2
	ranks.global_builds.clear_heal = 2
	check(not Catalog.allowed_ids("stick", ranks).has("damage"), "maxed weapon rank is excluded")
	check(Catalog.allowed_ids("corn", ranks).has("damage"), "other weapon damage rank remains available")
	check(not Catalog.allowed_ids("corn", ranks).has("clear_heal"), "global max rank is excluded on every weapon")
	check(Catalog.allowed_ids("stick", full_ranks()).is_empty(), "all maxed ranks leave an empty pool")
	for id in ["damage", "arc", "reach", "knockback", "recovery", "clear_heal"]:
		var definition: Dictionary = Catalog.get_definition(id)
		check(definition.get("id", "") == id and not str(definition.get("name", "")).is_empty() and not str(definition.get("description", "")).is_empty(), "readable original catalog metadata: " + id)
		check(definition.get("max_rank", 0) == 2, "catalog caps two ranks: " + id)
		definition.name = "changed by caller"
		check(Catalog.get_definition(id).get("name", "") != "changed by caller", "definition is an independent snapshot: " + id)
	check(Catalog.get_definition("missing").is_empty(), "unknown catalog definition is empty")
	var description: Dictionary = Catalog.describe("damage", blank_ranks(), "stick")
	check(description.get("current_rank", -1) == 0 and description.get("next_rank", -1) == 1, "UI describes actual current and next rank")
	check(is_equal_approx(float(description.get("current_value", 0)), 1.0) and is_equal_approx(float(description.get("next_value", 0)), 1.15), "UI damage values use the same additive multiplier as combat")
	check(str(description.get("change_text", "")).contains("100%") and str(description.get("change_text", "")).contains("115%"), "UI includes a numerical damage transition")
	check(Catalog.describe("arc", blank_ranks(), "corn").is_empty(), "UI does not describe an inapplicable corn upgrade")
	check(Catalog.describe("unknown", blank_ranks(), "stick").is_empty(), "UI rejects unknown upgrade IDs")
	var recovery := blank_ranks()
	recovery.builds_by_weapon.stick.recovery = 1
	var recovery_description: Dictionary = Catalog.describe("recovery", recovery, "stick")
	check(is_equal_approx(float(recovery_description.get("next_value", 0)), 0.8464), "UI recovery rank two is 0.92 squared")
	check(str(recovery_description.get("description", "")).contains("有效命中"), "UI explains that recovery leaves the active hit window unchanged")

func transition_checks() -> void:
	var ranks := blank_ranks()
	var before := ranks.duplicate(true)
	var heap: Dictionary = Heap.create("run-a", 730027, 1, "stick", ranks)
	check(Heap.STARTING_DICE == 2, "new runs have a shared two-dice starting value")
	check(heap.get("heap_id", "") == "run-a:1:toolheap", "heap identity includes run and floor and source")
	check(heap.get("reroll_index", -1) == 0 and not bool(heap.get("resolved", true)), "new heap is one unresolved candidate at cursor zero")
	check(Catalog.allowed_ids("stick", ranks).has(str(heap.get("candidate_id", ""))), "new heap selects exactly one legal candidate")
	check(heap.get("floor", -1) == 1 and heap.get("weapon_id", "") == "stick" and heap.has("seed"), "heap persists the deterministic selection context")
	check(ranks == before, "create leaves caller ranks unchanged")
	var heap_before := heap.duplicate(true)
	var result: Dictionary = Heap.act(heap, "reroll", 2, ranks, "stick")
	check(bool(result.get("ok", false)) and result.get("dice", -1) == 1, "reroll spends exactly one of the two dice")
	var next_heap: Dictionary = result.get("heap", {})
	check(next_heap.get("reroll_index", -1) == 1 and not bool(next_heap.get("resolved", true)), "reroll advances the stable cursor without resolving the layer")
	check(next_heap.get("candidate_id", "") != heap.get("candidate_id", ""), "reroll avoids the prior candidate when alternatives exist")
	check(result.get("ranks", {}) == ranks and heap == heap_before and ranks == before, "reroll neither grants an upgrade nor mutates inputs")
	check_rejected(Heap.act(heap, "reroll", 0, ranks, "stick"), heap, 0, ranks, "zero-dice reroll")
	var accepted: Dictionary = Heap.act(heap, "accept", 2, ranks, "stick")
	check(bool(accepted.get("ok", false)) and accepted.get("dice", -1) == 2, "accept costs no dice")
	check(bool(accepted.get("heap", {}).get("resolved", false)), "accept resolves the only layer")
	check(stored_rank(accepted.get("ranks", {}), str(heap.get("candidate_id", ""))) == 1, "accept increases exactly the candidate rank")
	check(heap == heap_before and ranks == before, "accept is a pure value transition")
	if accepted.get("ranks", {}).has("builds_by_weapon"):
		var accepted_snapshot: Dictionary = accepted.ranks.duplicate(true)
		check_rejected(Heap.act(accepted.heap, "accept", accepted.dice, accepted.ranks, "stick"), accepted.heap, accepted.dice, accepted_snapshot, "repeated accept")
		check_rejected(Heap.act(accepted.heap, "reroll", accepted.dice, accepted.ranks, "stick"), accepted.heap, accepted.dice, accepted_snapshot, "reroll after accept")
		accepted.ranks.builds_by_weapon.stick.damage = 2
		check(ranks == before, "result nested ranks do not alias caller ranks")
	var skipped: Dictionary = Heap.act(heap, "skip", 2, ranks, "stick")
	check(bool(skipped.get("ok", false)) and bool(skipped.get("heap", {}).get("resolved", false)) and skipped.get("ranks", {}) == ranks and skipped.get("dice", -1) == 2, "skip resolves the layer without resources or ranks changing")
	var maxed := full_ranks()
	var empty_heap: Dictionary = Heap.create("maxed", 17, 2, "stick", maxed)
	check(str(empty_heap.get("candidate_id", "not-empty")).is_empty(), "an exhausted catalog creates an empty candidate")
	var empty_skip: Dictionary = Heap.act(empty_heap, "skip", 0, maxed, "stick")
	check(bool(empty_skip.get("ok", false)) and bool(empty_skip.get("heap", {}).get("resolved", false)), "fully maxed heap remains skippable with zero dice")
	check_rejected(Heap.act(empty_heap, "accept", 2, maxed, "stick"), empty_heap, 2, maxed, "empty-candidate accept")
	check_rejected(Heap.act(empty_heap, "reroll", 2, maxed, "stick"), empty_heap, 2, maxed, "empty-candidate reroll")
	var single := full_ranks()
	single.global_builds.clear_heal = 1
	var single_heap: Dictionary = Heap.create("single", 6, 1, "stick", single)
	check(single_heap.get("candidate_id", "") == "clear_heal", "one remaining legal rank produces that candidate")
	var single_reroll: Dictionary = Heap.act(single_heap, "reroll", 2, single, "stick")
	check(bool(single_reroll.get("ok", false)) and single_reroll.get("dice", 0) == 1 and single_reroll.get("heap", {}).get("candidate_id", "") == "clear_heal", "single-candidate reroll spends one die and may repeat")
	var last_rank: Dictionary = Heap.act(single_heap, "accept", 2, single, "stick")
	check(stored_rank(last_rank.get("ranks", {}), "clear_heal") == 2, "accept reaches rank two without exceeding it")
	check(Catalog.allowed_ids("stick", last_rank.get("ranks", {})).is_empty(), "new pool omits the newly maxed rank")
	check(last_rank.get("ranks", {}).get("builds_by_weapon", {}) == single.builds_by_weapon, "global upgrade does not modify either weapon's ranks")

func validation_checks() -> void:
	var ranks := blank_ranks()
	var heap: Dictionary = Heap.create("valid", 11, 1, "stick", ranks)
	check_rejected(Heap.act(heap, "bogus", 2, ranks, "stick"), heap, 2, ranks, "unknown action")
	check_rejected(Heap.act(heap, "accept", -1, ranks, "stick"), heap, -1, ranks, "negative dice")
	check_rejected(Heap.act(heap, "accept", 2, ranks, "corn"), heap, 2, ranks, "different equipped weapon")
	check_rejected(Heap.act({}, "skip", 2, ranks, "stick"), {}, 2, ranks, "missing heap context")
	var malformed := heap.duplicate(true)
	malformed.reroll_index = -1
	check_rejected(Heap.act(malformed, "reroll", 2, ranks, "stick"), malformed, 2, ranks, "negative reroll cursor")
	malformed = heap.duplicate(true)
	malformed.resolved = "false"
	check_rejected(Heap.act(malformed, "accept", 2, ranks, "stick"), malformed, 2, ranks, "non-boolean resolved flag")
	malformed = heap.duplicate(true)
	malformed.candidate_id = "not-an-upgrade"
	check_rejected(Heap.act(malformed, "accept", 2, ranks, "stick"), malformed, 2, ranks, "unrecognized candidate")
	var invalid_ranks := {"builds_by_weapon": {"stick": {"damage": -1}}, "global_builds": {}}
	check_rejected(Heap.act(heap, "accept", 2, invalid_ranks, "stick"), heap, 2, invalid_ranks, "invalid rank value")
	var stale := full_ranks()
	check_rejected(Heap.act(heap, "accept", 2, stale, "stick"), heap, 2, stale, "candidate already maxed elsewhere")
	check(Heap.create("", 11, 1, "stick", ranks).is_empty(), "empty run identity cannot create a heap")
	check(Heap.create("valid", 11, 3, "stick", ranks).is_empty(), "there is no third-node toolheap")
	check(Heap.create("valid", 11, 1, "unknown", ranks).is_empty(), "unsupported weapon cannot create a heap")

func edge_checks() -> void:
	var ranks := blank_ranks()
	var heap: Dictionary = Heap.create("first-run", 73, 1, "stick", ranks)
	var another: Dictionary = Heap.create("second-run", 73, 1, "stick", ranks)
	check(heap.candidate_id == another.candidate_id and heap.heap_id != another.heap_id, "seeded choices are independent of random run UUIDs while receipts stay distinct")
	var malformed := heap.duplicate(true)
	for key in ["seed", "floor", "reroll_index"]:
		for value in [-INF, INF, NAN, 0.5, "1", true, null]:
			malformed = heap.duplicate(true)
			malformed[key] = value
			var result: Dictionary = Heap.act(malformed, "reroll", 2, ranks, "stick")
			check(not bool(result.get("ok", true)) and result.get("dice", -1) == 2, "invalid %s numeric type/value cannot consume dice: %s" % [key, str(value)])
	for value in [-1, 3, 0.5, "1", true, INF, NAN]:
		var malformed_ranks := blank_ranks()
		malformed_ranks.builds_by_weapon.stick.damage = value
		check(not Catalog.is_valid_ranks(malformed_ranks), "invalid stored rank is rejected: " + str(value))
		check(Heap.create("invalid-ranks", 73, 1, "stick", malformed_ranks).is_empty(), "invalid stored rank cannot generate a candidate")
	var max_cursor := heap.duplicate(true)
	max_cursor.reroll_index = Heap.MAX_REROLL_INDEX
	check_rejected(Heap.act(max_cursor, "reroll", 2, ranks, "stick"), max_cursor, 2, ranks, "reroll cursor exhausted")
	max_cursor.reroll_index = Heap.MAX_REROLL_INDEX - 1
	var final_reroll: Dictionary = Heap.act(max_cursor, "reroll", 2, ranks, "stick")
	check(bool(final_reroll.get("ok", false)) and final_reroll.get("heap", {}).get("reroll_index", -1) == Heap.MAX_REROLL_INDEX, "last bounded cursor increment does not wrap")
	var minimal: Dictionary = Heap.create("minimal", -73, 2, "corn", {})
	var grant: Dictionary = Heap.act(minimal, "accept", 2, {}, "corn")
	check(bool(grant.get("ok", false)) and stored_rank(grant.get("ranks", {}), str(minimal.get("candidate_id", "")), "corn") == 1, "empty rank dictionaries are populated only at the granted scope")
	check(Heap.act(JSON.parse_string(JSON.stringify(minimal)), "accept", 2, {}, "corn") == grant, "JSON resume preserves an accept transition")
	var json_skipped: Dictionary = Heap.act(JSON.parse_string(JSON.stringify(heap)), "skip", 2, ranks, "stick")
	check(json_skipped == Heap.act(heap, "skip", 2, ranks, "stick"), "JSON resume preserves a skip transition")
	var enriched := blank_ranks()
	enriched.builds_by_weapon.corn.damage = 2
	enriched.builds_by_weapon.stick.unrelated_future_upgrade = 1
	enriched.future_record = {"items": ["retain me"]}
	var enriched_before := enriched.duplicate(true)
	var enriched_heap: Dictionary = Heap.create("preserved", 73, 1, "stick", enriched)
	var enriched_grant: Dictionary = Heap.act(enriched_heap, "accept", 2, enriched, "stick")
	check(enriched == enriched_before and enriched_grant.get("ranks", {}).get("builds_by_weapon", {}).get("corn", {}) == enriched.builds_by_weapon.corn, "accept never removes the inactive weapon's saved ranks")
	check(enriched_grant.get("ranks", {}).get("future_record", {}) == enriched.future_record and enriched_grant.get("ranks", {}).get("builds_by_weapon", {}).get("stick", {}).get("unrelated_future_upgrade", 0) == 1, "accept preserves unrelated data instead of rebuilding the rank store")
	var corn_rank := full_ranks()
	corn_rank.builds_by_weapon.corn.damage = 1
	var corn_heap: Dictionary = Heap.create("corn-damage", 99, 1, "corn", corn_rank)
	var corn_grant: Dictionary = Heap.act(corn_heap, "accept", 2, corn_rank, "corn")
	check(corn_heap.get("candidate_id", "") == "damage" and stored_rank(corn_grant.get("ranks", {}), "damage", "corn") == 2, "corn can grant its own damage rank two")
	check(corn_grant.get("ranks", {}).get("builds_by_weapon", {}).get("stick", {}) == corn_rank.builds_by_weapon.stick, "corn acquisition does not rewrite stick ranks")
	for id in Catalog.IDS:
		var info: Dictionary = Catalog.describe(id, full_ranks(), "stick")
		check(info.get("current_rank", -1) == 2 and info.get("next_rank", -1) == 2 and info.get("current_value", -1) == info.get("next_value", -2), "maxed UI preview never invents rank three: " + id)

func determinism_checks() -> void:
	var ranks := blank_ranks()
	var coverage: Dictionary = {}
	for seed_value in range(1000):
		check(Heap.create("deterministic", seed_value, 3, "stick", ranks).is_empty(), "third node never generates a toolheap: %d" % seed_value)
		for floor_value in [1, 2]:
			var heap: Dictionary = Heap.create("deterministic", seed_value, floor_value, "stick", ranks)
			check(heap == Heap.create("deterministic", seed_value, floor_value, "stick", ranks), "same seed and node produce identical heap %d/%d" % [seed_value, floor_value])
			check(Catalog.allowed_ids("stick", ranks).has(str(heap.get("candidate_id", ""))), "candidate is legal for seed/node %d/%d" % [seed_value, floor_value])
			coverage[str(heap.get("candidate_id", ""))] = true
			for dice in [2, 1]:
				var restored: Dictionary = JSON.parse_string(JSON.stringify(heap))
				var rerolled: Dictionary = Heap.act(heap, "reroll", dice, ranks, "stick")
				var restored_reroll: Dictionary = Heap.act(restored, "reroll", dice, JSON.parse_string(JSON.stringify(ranks)), "stick")
				check(rerolled == restored_reroll, "JSON restore preserves next reroll %d/%d/%d" % [seed_value, floor_value, dice])
				check(bool(rerolled.get("ok", false)) and rerolled.get("dice", -1) == dice - 1, "valid deterministic reroll spends one die %d/%d/%d" % [seed_value, floor_value, dice])
				check(rerolled.get("heap", {}).get("candidate_id", "") != heap.get("candidate_id", ""), "deterministic reroll avoids repeats %d/%d/%d" % [seed_value, floor_value, dice])
				heap = rerolled.get("heap", {})
	check(coverage.size() == 6, "the sampled seed range reaches every original upgrade")
	var huge_seed: Dictionary = Heap.create("large-seed", 9223372036854775807, 1, "stick", ranks)
	check(int(huge_seed.get("seed", -1)) >= 0 and int(huge_seed.get("seed", 2147483647)) < 2147483647, "saved random seed remains JSON-exact in 31 bits")
	check(Heap.act(huge_seed, "reroll", 2, ranks, "stick") == Heap.act(JSON.parse_string(JSON.stringify(huge_seed)), "reroll", 2, ranks, "stick"), "large source seeds do not lose continuation state through JSON")

func route_checks() -> void:
	var Effects = load("res://scripts/cornfield/build_effects.gd")
	for scenario in [
		{"name": "sweep", "seed": 5, "rerolls": [0, 0], "accepted": ["arc", "reach"], "remaining_dice": 2},
		{"name": "steady", "seed": 12, "rerolls": [1, 1], "accepted": ["knockback", "clear_heal"], "remaining_dice": 0},
	]:
		var ranks := blank_ranks()
		var dice := 2
		for floor_value in [1, 2]:
			var heap: Dictionary = Heap.create("route-proof", scenario.seed, floor_value, "stick", ranks)
			for cursor in range(scenario.rerolls[floor_value - 1]):
				var rolled: Dictionary = Heap.act(heap, "reroll", dice, ranks, "stick")
				check(bool(rolled.get("ok", false)), scenario.name + " route has sufficient dice for its planned reroll")
				heap = rolled.get("heap", {})
				dice = rolled.get("dice", -1)
			check(heap.get("candidate_id", "") == scenario.accepted[floor_value - 1], "%s route node %d selects its documented upgrade" % [scenario.name, floor_value])
			var granted: Dictionary = Heap.act(heap, "accept", dice, ranks, "stick")
			check(bool(granted.get("ok", false)), "%s route node %d accepts successfully" % [scenario.name, floor_value])
			ranks = granted.get("ranks", {})
		var effects: Dictionary = Effects.compile(ranks, "stick")
		check(dice == scenario.remaining_dice, scenario.name + " route spends only its documented dice")
		if scenario.name == "sweep":
			check(is_equal_approx(float(effects.get("arc_bonus_degrees", 0)), 12.0) and is_equal_approx(float(effects.get("reach_multiplier", 0)), 1.10), "sweep route creates wider and longer coverage")
		else:
			check(is_equal_approx(float(effects.get("knockback_multiplier", 0)), 1.25) and is_equal_approx(float(effects.get("clear_heal", 0)), 3.0), "steady route combines knockback and clear healing")
	var corn_coverage := {}
	var corn_ranks := blank_ranks()
	for seed_value in range(1000):
		var heap: Dictionary = Heap.create("corn-coverage", seed_value, 1, "corn", corn_ranks)
		corn_coverage[str(heap.get("candidate_id", ""))] = true
		check(Catalog.allowed_ids("corn", corn_ranks).has(str(heap.get("candidate_id", ""))), "corn seed %d selects only an applicable upgrade" % seed_value)
		var rolled: Dictionary = Heap.act(heap, "reroll", 2, corn_ranks, "corn")
		check(bool(rolled.get("ok", false)) and rolled.get("heap", {}).get("candidate_id", "") != heap.get("candidate_id", ""), "corn seed %d rerolls to a different applicable candidate" % seed_value)
	check(corn_coverage.size() == 3, "corn seed range reaches all three supported upgrade choices")

func finish() -> void:
	print(JSON.stringify({"suite": "cornfield_toolheap", "checks": checks, "failures": failures}))
	quit(1 if failures else 0)
