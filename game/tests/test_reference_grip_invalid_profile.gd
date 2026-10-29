extends SceneTree
## Malformed numbers must reject before conversion and retain valid active data.
const INPUTS := "res://assets/characters/boy/normal_grip/v4/"
var failures := 0
var checks := 0
func _initialize(): call_deferred("run_checks")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", label)
func finish(helper):
	helper.free()
	print("REFERENCE_GRIP_INVALID_PROFILE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func run_checks():
	var helper = load("res://weapons/melee_hold_pose.gd").new()
	helper._source_attack = Animation.new(); helper._source_attack.length = 1.5416666269302368
	var carry = JSON.parse_string(FileAccess.get_file_as_string(INPUTS + "carry-reference.json"))
	var attack = JSON.parse_string(FileAccess.get_file_as_string(INPUTS + "attack-reference.json"))
	check(helper.load_reference_data(carry, attack), "valid paired profile initializes")
	var before_carry: Dictionary = helper.records.duplicate(true)
	var before_attack: Array = helper.attack_records.duplicate(true)
	var bad: Dictionary = attack.duplicate(true)
	bad.duration_s = str(attack.duration_s)
	check(not helper.load_reference_data(carry, bad), "numeric-string duration rejects rather than coercing")
	bad = attack.duplicate(true); bad.records[1].time = str(bad.records[1].time)
	check(not helper.load_reference_data(carry, bad), "numeric-string key time rejects rather than coercing")
	# Keep the initial RED focused on wrong acceptance, not conversion exceptions.
	if failures: finish(helper); return
	for malformed in [[], {}, "not a number", null, NAN, INF]:
		bad = attack.duplicate(true); bad.duration_s = malformed
		check(not helper.load_reference_data(carry, bad), "malformed duration rejects without engine error")
		bad = attack.duplicate(true); bad.records[1].time = malformed
		check(not helper.load_reference_data(carry, bad), "malformed key time rejects without engine error")
		check(helper.records == before_carry and helper.attack_records == before_attack, "malformed input preserves valid active carry and attack data")
	finish(helper)
