extends SceneTree
## Pure recipe contract. No actors, world, director, or saved run is instantiated.

const RECIPE_PATH := "res://scripts/cornfield/encounter_recipe.gd"
const Rooms = preload("res://scripts/cornfield/room_catalog.gd")
const Catalog = preload("res://scripts/cornfield/enemy_catalog.gd")
const MELEE: Array[String] = ["beetle", "locust", "mouse", "rooster"]
const RANGED: Array[String] = ["snail", "corn_borer"]
const INTRO: Array[String] = ["beetle", "beetle", "mouse", "beetle", "mouse", "beetle", "mouse", "beetle"]

var checks := 0
var failures: Array[String] = []
var recipe: Script
var template_cases := 0
var repetition_cases := 0
var table: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func room_with(pool: Array, fallback: String = "beetle") -> Dictionary:
	return {"template_id":"test_room", "species":pool, "melee_fallback":fallback,
		"nested":{"untouched":[1, {"marker":"original"}]}}

func ranged_count(roster: Array[String]) -> int:
	var total := 0
	for id in roster:
		if id in RANGED:
			total += 1
	return total

func run_tests() -> void:
	check(ResourceLoader.exists(RECIPE_PATH), "pure EncounterRecipe module exists")
	if not failures.is_empty():
		finish()
		return
	recipe = load(RECIPE_PATH)
	check(recipe != null and recipe.has_method("roster"), "EncounterRecipe exposes static roster API")
	if not failures.is_empty():
		finish()
		return
	test_weighted_rotation()
	test_ranged_cap_and_explicit_fallback()
	test_intro_is_fixed_identity()
	test_malformed_data()
	test_all_templates()
	test_integer_indices_and_readonly_input()
	test_random_state_is_untouched()
	test_return_arrays_are_independent()
	write_table_if_requested()
	finish()

func test_weighted_rotation() -> void:
	var definition := room_with(["beetle", "locust"])
	var original := var_to_str(definition)
	check(recipe.roster(definition, 1, 0, 0, 8, false) == ["beetle", "beetle", "beetle", "locust", "beetle", "beetle", "beetle", "locust"], "ordinary primary/secondary species have exact 3:1 cycle")
	check(recipe.roster(definition, 1, 1, 0, 4, false) == ["beetle", "beetle", "locust", "beetle"], "segment index advances deterministic weighted rotation")
	check(recipe.roster(definition, 1, 0, 1, 4, false) == ["beetle", "beetle", "locust", "beetle"], "group index advances deterministic weighted rotation")
	check(recipe.roster(definition, 2, 2, 3, 4, false) == ["beetle", "beetle", "locust", "beetle"], "segment and group index compose without instance state")
	check(recipe.roster(room_with(["mouse"]), 3, 9, 11, 12, false) == ["mouse", "mouse", "mouse", "mouse", "mouse", "mouse", "mouse", "mouse", "mouse", "mouse", "mouse", "mouse"], "single legal species remains legal and fills the requested count")
	check(recipe.roster(room_with(["mouse", "rooster", "locust"]), 2, 0, 0, 10, false) == ["mouse", "mouse", "mouse", "rooster", "locust", "mouse", "mouse", "mouse", "rooster", "locust"], "additional authored secondaries each have weight one")
	check(var_to_str(definition) == original, "ordinary rotation does not mutate caller dictionary or nested data")

func test_ranged_cap_and_explicit_fallback() -> void:
	var local := room_with(["snail", "mouse"], "locust")
	check(recipe.roster(local, 1, 0, 0, 8, false) == ["snail", "snail", "mouse", "mouse", "mouse", "mouse", "mouse", "mouse"], "over-cap ranged slots use this room's melee instead of explicit foreign fallback")
	for count in range(1, 13):
		for segment in range(4):
			for group in range(4):
				for pool in [["snail"], ["snail", "corn_borer"], ["corn_borer", "rooster"], ["snail", "mouse", "rooster"]]:
					var definition := room_with(pool, "locust")
					var roster: Array[String] = recipe.roster(definition, 2, segment, group, count, false)
					var label := "ranged pool=%s count=%d segment=%d group=%d" % [str(pool), count, segment, group]
					check(roster.size() == count, label + " fills every requested slot")
					check(ranged_count(roster) <= floori(float(count) / 4.0), label + " respects floor(count/4) cap")
					var has_local_melee := false
					for id in pool:
						has_local_melee = has_local_melee or id in MELEE
					for id in roster:
						check(id in pool or (not has_local_melee and id == "locust"), label + " only explicit fallback when no local melee exists")
	for fallback in MELEE:
		var roster: Array[String] = recipe.roster(room_with(["snail"], fallback), 2, 0, 0, 3, false)
		check(roster == [fallback, fallback, fallback], "each of four explicit melee fallbacks supports zero ranged quota")

func test_intro_is_fixed_identity() -> void:
	var definition := room_with(["locust", "corn_borer"])
	var original := var_to_str(definition)
	check(recipe.roster(definition, 1, 0, 0, 8, true) == INTRO, "floor 1 fixed segment0/group0 teaching roster is exact 5 beetles and 3 mice")
	for repetition in range(100):
		check(recipe.roster(definition, 1, 0, 0, 8, true) == INTRO, "cancel/retry cannot advance teaching roster repeat=%d" % repetition)
		# Later identities can be requested first; the pure recipe still owns no cursor.
		recipe.roster(definition, 1, 1, 0, 8, false)
		recipe.roster(definition, 1, 0, 1, 8, false)
	check(recipe.roster(definition, 1, 0, 0, 8, false) != INTRO, "intro flag is explicit, never inferred from first successful request")
	for identity in [[1, 0, 1], [1, 1, 0], [2, 0, 0], [3, 0, 0]]:
		var roster: Array[String] = recipe.roster(definition, identity[0], identity[1], identity[2], 8, true)
		check(roster == recipe.roster(definition, identity[0], identity[1], identity[2], 8, false), "stale intro flag cannot teach a later group or floor: " + str(identity))
	for count in [1, 7, 9, 12]:
		check(recipe.roster(definition, 1, 0, 0, count, true) == recipe.roster(definition, 1, 0, 0, count, false), "teaching override is only the exact eight-enemy group count=%d" % count)
	check(var_to_str(definition) == original, "teaching override does not alter room pool or caller data")
	check(recipe.roster(room_with(["boss_borer"]), 3, 0, 0, 1, false).is_empty(), "Boss cannot enter ordinary recipe pool")

func test_malformed_data() -> void:
	for count in [-2147483648, -1, 0, 13, 2147483647]:
		check(recipe.roster(room_with(["beetle", "mouse"]), 1, 0, 0, count, false).is_empty(), "count outside 1..12 is rejected: %d" % count)
	var invalid_rooms: Array[Dictionary] = [
		{}, {"template_id":"no_pool", "melee_fallback":"beetle"},
		room_with([]), room_with(["unknown"]), room_with(["beetle", "unknown"]),
		room_with(["boss_borer"]), room_with(["beetle", "boss_borer"]),
		room_with([1]), room_with([null]), room_with([{"id":"beetle"}]),
		{"template_id":"wrong_pool_type", "species":"beetle", "melee_fallback":"beetle"},
		{"template_id":"wrong_pool_type", "species":null, "melee_fallback":"beetle"},
		{"template_id":"missing_fallback", "species":["beetle"]},
		{"template_id":"invalid_fallback_type", "species":["beetle"], "melee_fallback":null},
		{"template_id":"invalid_fallback_type", "species":["beetle"], "melee_fallback":1},
	]
	for fallback in ["", "unknown", "snail", "corn_borer", "boss_borer"]:
		invalid_rooms.append(room_with(["beetle", "mouse"], fallback))
	for index in range(invalid_rooms.size()):
		var definition: Dictionary = invalid_rooms[index]
		var original := var_to_str(definition)
		check(recipe.roster(definition, 2, 0, 0, 8, false).is_empty(), "malformed room returns empty without filtering bad authored entries case=%d" % index)
		check(recipe.roster(definition, 1, 0, 0, 8, true).is_empty(), "intro does not bypass malformed-data rejection case=%d" % index)
		check(var_to_str(definition) == original, "malformed room remains untouched case=%d" % index)

func test_all_templates() -> void:
	check(Rooms.TEMPLATE_COUNT == 24, "matrix covers exactly 24 current templates")
	for template_index in range(Rooms.TEMPLATE_COUNT):
		var definition: Dictionary = Rooms.make_template(template_index)
		# Task 1 adds this metadata to revision-3 dungeon definitions. The pure
		# package must not change RoomCatalog or silently default missing metadata.
		definition.melee_fallback = "beetle"
		var original := var_to_str(definition)
		var samples: Dictionary = {}
		for floor_number in range(1, 4):
			for segment in range(4):
				for group in range(4):
					for count in range(1, 13):
						var roster: Array[String] = recipe.roster(definition, floor_number, segment, group, count, false)
						var label := "%s floor=%d segment=%d group=%d count=%d" % [definition.template_id, floor_number, segment, group, count]
						template_cases += 1
						check(roster.size() == count, label + " never takes malformed-data branch")
						check(ranged_count(roster) <= floori(float(count) / 4.0), label + " ranged quota")
						for id in roster:
							check(Catalog.SPECIES.has(id) and id != "boss_borer", label + " only ordinary Catalog species")
							check(id in definition.species or id == definition.melee_fallback, label + " only authored pool or explicit fallback")
						check(var_to_str(definition) == original, label + " never mutates room definition")
			var stable: Array[String] = recipe.roster(definition, floor_number, 5, 7, 12, false)
			for repetition in range(100):
				repetition_cases += 1
				check(recipe.roster(definition, floor_number, 5, 7, 12, false) == stable, "%s floor=%d repeats identically %d/100" % [definition.template_id, floor_number, repetition + 1])
			var count: int = [8, 10, 12][floor_number - 1]
			samples["floor_%d_count_%d_s0_g0" % [floor_number, count]] = recipe.roster(definition, floor_number, 0, 0, count, false)
		table.append({"template_id":definition.template_id, "title":definition.title,
			"species":definition.species.duplicate(), "melee_fallback":definition.melee_fallback, "samples":samples})

func test_integer_indices_and_readonly_input() -> void:
	var definition := room_with(["beetle", "locust"])
	var maximum: int = 9223372036854775807
	var minimum: int = -9223372036854775807 - 1
	check(recipe.roster(definition, 2, maximum, maximum, 12, false) == recipe.roster(definition, 2, 3, 3, 12, false), "int64 maximum indices rotate without overflowing their sum")
	check(recipe.roster(definition, 2, minimum, minimum, 12, false) == recipe.roster(definition, 2, 0, 0, 12, false), "int64 minimum indices are normalized deterministically")
	check(recipe.roster(definition, 2, -1, 0, 12, false) == recipe.roster(definition, 2, 3, 0, 12, false), "negative integer phase is stable rather than negative array indexing")
	definition.species.make_read_only()
	definition.nested.make_read_only()
	definition.make_read_only()
	check(recipe.roster(definition, 2, 1, 2, 8, false) == ["locust", "beetle", "beetle", "beetle", "locust", "beetle", "beetle", "beetle"], "read-only room dictionary and pool need no mutable preparation")
	var duplicates := room_with(["mouse", "mouse", "rooster"])
	check(recipe.roster(duplicates, 2, 0, 0, 10, false) == ["mouse", "mouse", "mouse", "mouse", "rooster", "mouse", "mouse", "mouse", "mouse", "rooster"], "legal duplicate entries preserve authored weight instead of being silently deduplicated")

func test_random_state_is_untouched() -> void:
	seed(998177)
	var expected: Array[int] = []
	for _index in range(8):
		expected.append(randi())
	seed(998177)
	var actual: Array[int] = []
	for index in range(8):
		actual.append(randi())
		recipe.roster(room_with(["snail", "mouse"]), 2, 3, index, 12, false)
	check(actual == expected, "roster never advances or reseeds global random state")

func test_return_arrays_are_independent() -> void:
	var definition := room_with(["beetle", "mouse"])
	var first: Array[String] = recipe.roster(definition, 1, 0, 0, 8, false)
	check(first.size() == 8, "ordinary return array supports mutation-isolation check")
	if first.size() != 8:
		return
	var expected := first.duplicate()
	first[0] = "rooster"
	check(recipe.roster(definition, 1, 0, 0, 8, false) == expected, "caller mutation cannot contaminate later ordinary rosters")
	var intro: Array[String] = recipe.roster(definition, 1, 0, 0, 8, true)
	check(intro.size() == 8, "intro return array supports mutation-isolation check")
	if intro.size() != 8:
		return
	intro[0] = "rooster"
	check(recipe.roster(definition, 1, 0, 0, 8, true) == INTRO, "caller mutation cannot contaminate teaching constant")

func write_table_if_requested() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--table="):
			var path := argument.trim_prefix("--table=")
			var file := FileAccess.open(path, FileAccess.WRITE)
			check(file != null, "recipe table evidence destination is writable")
			if file != null:
				file.store_string(JSON.stringify({"template_count":table.size(), "templates":table}, "\t") + "\n")
				file.close()

func finish() -> void:
	print("CORNFIELD_ENCOUNTER_RECIPE: %s (%d checks; %d template/count/index cases; %d repeated-input cases)" % ["PASS" if failures.is_empty() else "FAIL", checks, template_cases, repetition_cases])
	quit(0 if failures.is_empty() else 1)
