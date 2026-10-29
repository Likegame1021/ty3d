extends SceneTree
## Pure snapshots are compiled once from ranks, never from last frame's values.
var checks := 0
var failures := 0
var Effects
var Catalog

func _initialize() -> void:
	call_deferred("run_checks")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func near(actual: Dictionary, key: String, expected: float, label: String) -> void:
	check(actual.has(key) and is_equal_approx(float(actual.get(key, -999.0)), expected), label)

func blank_ranks() -> Dictionary:
	return {"builds_by_weapon": {"stick": {}, "corn": {}}, "global_builds": {}}

func run_checks() -> void:
	for path in ["res://scripts/cornfield/build_catalog.gd", "res://scripts/cornfield/build_effects.gd"]:
		check(ResourceLoader.exists(path), "required pure module exists: " + path)
	if failures:
		finish()
		return
	Catalog = load("res://scripts/cornfield/build_catalog.gd")
	Effects = load("res://scripts/cornfield/build_effects.gd")
	var baseline: Dictionary = Effects.compile({}, "stick")
	check(baseline == {"damage_multiplier": 1.0, "arc_bonus_degrees": 0.0, "reach_multiplier": 1.0, "knockback_multiplier": 1.0, "recovery_multiplier": 1.0, "clear_heal": 0.0}, "empty ranks return the exact six-value baseline")
	for id in ["damage", "arc", "reach", "knockback", "recovery", "clear_heal"]:
		for rank_value in [1, 2]:
			var ranks := blank_ranks()
			if id == "clear_heal":
				ranks.global_builds[id] = rank_value
			else:
				ranks.builds_by_weapon.stick[id] = rank_value
			var actual: Dictionary = Effects.compile(ranks, "stick")
			near(actual, "damage_multiplier", 1.0 + 0.15 * rank_value if id == "damage" else 1.0, "%s rank %d damage is additive once" % [id, rank_value])
			near(actual, "arc_bonus_degrees", 12.0 * rank_value if id == "arc" else 0.0, "%s rank %d angle uses degrees" % [id, rank_value])
			near(actual, "reach_multiplier", 1.0 + 0.10 * rank_value if id == "reach" else 1.0, "%s rank %d reach is additive once" % [id, rank_value])
			near(actual, "knockback_multiplier", 1.0 + 0.25 * rank_value if id == "knockback" else 1.0, "%s rank %d knockback is additive once" % [id, rank_value])
			near(actual, "recovery_multiplier", pow(0.92, rank_value) if id == "recovery" else 1.0, "%s rank %d recovery multiplies only its own duration" % [id, rank_value])
			near(actual, "clear_heal", 3.0 * rank_value if id == "clear_heal" else 0.0, "%s rank %d global clear healing is additive" % [id, rank_value])
	var mixed := {"builds_by_weapon": {"stick": {"damage": 2, "arc": 2, "reach": 2, "knockback": 2, "recovery": 2}, "corn": {"damage": 1, "knockback": 1, "arc": 2, "reach": 2, "recovery": 2}}, "global_builds": {"clear_heal": 2}}
	var before := mixed.duplicate(true)
	var stick: Dictionary = Effects.compile(mixed, "stick")
	var corn: Dictionary = Effects.compile(mixed, "corn")
	near(stick, "damage_multiplier", 1.30, "stick two-level damage is 1.30")
	near(stick, "clear_heal", 6.0, "two-level global healing is six")
	near(corn, "damage_multiplier", 1.15, "corn reads only its own damage rank")
	near(corn, "knockback_multiplier", 1.25, "corn reads only its own knockback rank")
	near(corn, "arc_bonus_degrees", 0.0, "corn ignores inapplicable angle ranks")
	near(corn, "reach_multiplier", 1.0, "corn ignores inapplicable reach ranks")
	near(corn, "recovery_multiplier", 1.0, "corn ignores inapplicable recovery ranks")
	near(corn, "clear_heal", 6.0, "global healing persists through a weapon switch")
	check(mixed == before and Effects.compile(mixed, "stick") == stick, "weapon switching preserves all ranks and restores the original snapshot")
	check(Effects.compile(mixed, "stick") == Effects.compile(mixed, "stick"), "recompiling does not compound upgrades")
	var legacy: Dictionary = Effects.compile(mixed, "stick", 0.70)
	near(legacy, "damage_multiplier", 2.0, "legacy additive damage bonus is applied exactly once")
	check(Effects.compile(mixed, "stick", 0.70) == legacy and mixed == before, "legacy compilation has no migration or mutation side effects")
	var clamped := {"builds_by_weapon": {"stick": {"damage": 99, "arc": -4, "reach": "2", "knockback": 1.5, "recovery": 2}}, "global_builds": {"clear_heal": 200}}
	var safe: Dictionary = Effects.compile(clamped, "stick")
	near(safe, "damage_multiplier", 1.30, "out-of-range positive ranks cannot exceed the max effect")
	near(safe, "arc_bonus_degrees", 0.0, "negative ranks contribute nothing")
	near(safe, "reach_multiplier", 1.0, "string ranks are not silently granted")
	near(safe, "knockback_multiplier", 1.0, "fractional ranks are not silently granted")
	near(safe, "clear_heal", 6.0, "global ranks are bounded to two")
	near(Effects.compile(mixed, "stick", -0.5), "damage_multiplier", 1.30, "negative legacy bonus cannot reduce damage")
	near(Effects.compile(mixed, "stick", NAN), "damage_multiplier", 1.30, "non-finite legacy bonus cannot poison damage")
	near(Effects.compile(mixed, "stick", INF), "damage_multiplier", 1.30, "infinite legacy bonus cannot poison damage")
	check(Effects.compile({"builds_by_weapon": "bad", "global_builds": []}, "stick") == baseline, "malformed rank containers compile safely to baseline")
	var json_copy: Dictionary = JSON.parse_string(JSON.stringify(mixed))
	check(Effects.compile(json_copy, "stick") == stick, "integer-valued JSON numbers preserve the exact effect snapshot")
	check(not stick.has("active_start") and not stick.has("active_end") and not stick.has("duration"), "compiler exposes recovery factor without replacing animation hit windows")
	for id in ["damage", "arc", "reach", "knockback", "recovery", "clear_heal"]:
		var current := blank_ranks()
		if id == "clear_heal":
			current.global_builds[id] = 1
		else:
			current.builds_by_weapon.stick[id] = 1
		var info: Dictionary = Catalog.describe(id, current, "stick")
		var next := current.duplicate(true)
		if id == "clear_heal":
			next.global_builds[id] = 2
		else:
			next.builds_by_weapon.stick[id] = 2
		var field: String = {"damage": "damage_multiplier", "arc": "arc_bonus_degrees", "reach": "reach_multiplier", "knockback": "knockback_multiplier", "recovery": "recovery_multiplier", "clear_heal": "clear_heal"}[id]
		check(is_equal_approx(float(info.get("current_value", -999)), float(Effects.compile(current, "stick").get(field, 0))) and is_equal_approx(float(info.get("next_value", -999)), float(Effects.compile(next, "stick").get(field, 0))), "UI and combat use identical current-to-next numerical semantics for " + id)
	finish()

func finish() -> void:
	print(JSON.stringify({"suite": "cornfield_build_effects", "checks": checks, "failures": failures}))
	quit(1 if failures else 0)
