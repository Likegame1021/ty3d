extends SceneTree

const Boss = preload("res://scripts/full_boss.gd")
const Pursuer = preload("res://scripts/full_pursuer.gd")
const Minion = preload("res://scripts/full_minion.gd")
var failed := 0

func check(ok: bool, name: String) -> void:
	if not ok:
		failed += 1
		printerr("FAIL: ", name)
	else:
		print("PASS: ", name)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var boss = Boss.new()
	root.add_child(boss)
	boss.active = true
	var counts := [0, 0]
	boss.strike_attempt.connect(func(): counts[0] += 1)
	boss.summon_requested.connect(func(): counts[1] += 1)
	boss.player_position = Vector3(0, 0, -32)
	boss.advance(2.1)
	check(boss.mode == "sweep_windup", "boss telegraphs sweep before hit")
	boss.advance(0.8)
	check(counts[0] == 1 and boss.mode == "recover", "sweep damages only after windup")
	boss.advance(3.0)
	check(boss.mode == "burrow_windup" and boss.warning_position.distance_to(boss.player_position) < 0.1, "burrow warns at target position")
	var before_burrow: Vector3 = boss.position
	boss.advance(0.35)
	check(boss.position.distance_to(before_burrow) > 0.5 and boss.mode == "burrow_windup", "burrow physically travels through corn before eruption")
	check(not boss.body.visible and boss.moving_mound.visible and boss.warning_ring.visible, "buried figure becomes moving mound with visible destination warning")
	boss.advance(0.75)
	check(counts[0] == 2 and boss.mode == "recover", "burrow erupts once")
	boss.advance(3.0)
	check(boss.mode == "summon_windup", "third skill is summon telegraph")
	boss.advance(1.1)
	check(counts[1] == 1 and boss.mode == "recover", "summon emits one group request")
	boss.active = false
	boss.advance(10)
	check(counts[1] == 1 and counts[0] == 2, "inactive boss cannot act")
	boss.reset_boss()
	check(boss.skill_index == 0 and boss.mode == "idle" and not boss.active, "retry clears boss timers and attack cycle")
	var rat = Pursuer.new()
	root.add_child(rat)
	rat.active = true
	rat.player_position = rat.position + Vector3(0, 0, 2)
	rat.advance(0.1)
	check(rat.mode == "chase", "pursuer notices nearby player")
	rat.distract(Vector3(-8, 0, 8))
	check(rat.mode == "distracted", "stone redirects pursuer")
	rat.advance(3.0)
	check(rat.mode == "return", "distraction expires into return")
	rat.reset_pursuer()
	check(rat.mode == "patrol" and rat.active, "retry clears pursuer state")
	var child = Minion.new()
	var bait := Node3D.new()
	root.add_child(bait)
	root.add_child(child)
	child.player = bait
	child.set_physics_process(false)
	child.position = Vector3.ZERO
	bait.position = Vector3(0, 0, 0.8)
	var child_strikes := [0]
	child.strike_attempt.connect(func(): child_strikes[0] += 1)
	if not child.has_method("advance"):
		check(false, "summoned minion telegraph routine exists")
		boss.queue_free()
		rat.queue_free()
		child.queue_free()
		bait.queue_free()
		await process_frame
		quit(1)
		return
	child.advance(0.1)
	check(child.mode == "windup" and child_strikes[0] == 0 and child.warning_ring.visible, "summoned minion shows readable windup before contact")
	child.advance(0.65)
	check(child_strikes[0] == 1, "summoned minion strikes once after windup")
	print("Full combat: %d failures" % failed)
	boss.queue_free()
	rat.queue_free()
	child.queue_free()
	bait.queue_free()
	await process_frame
	quit(1 if failed else 0)
