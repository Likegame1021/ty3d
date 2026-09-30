extends SceneTree

var failures := 0

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

func _initialize() -> void:
	var attack = load("res://scripts/attack_state.gd").new()
	check(not attack.claim_hit(42, false), "idle cannot hit")
	check(attack.begin(false), "attack starts while unpaused")
	check(not attack.claim_hit(42, false), "windup cannot hit")
	attack.tick(0.15, false)
	check(attack.claim_hit(42, false), "active window hits target")
	check(not attack.claim_hit(42, false), "same swing cannot hit twice")
	check(not attack.claim_hit(43, true), "paused attack cannot hit")
	var previous: float = attack.remaining
	attack.tick(3.0, true)
	check(is_equal_approx(attack.remaining, previous), "pause freezes attack timer")
	check(not attack.begin(false), "attack cannot restart during swing")
	attack.tick(0.5, false)
	check(not attack.claim_hit(43, false), "finished swing cannot hit")
	check(not attack.begin(true), "paused player cannot start attack")
	check(attack.begin(false), "next swing starts")
	attack.tick(0.15, false)
	check(attack.claim_hit(42, false), "next swing can hit same target")
	attack.reset()
	check(not attack.claim_hit(42, false), "reset cancels attack")
	check(attack.remaining == 0.0, "reset clears attack clock")
	print("Attack behavior: %d failures" % failures)
	quit(1 if failures else 0)
