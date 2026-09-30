extends SceneTree

var failures := 0

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var creature = load("res://scripts/entry_creature.gd").new()
	var player := CharacterBody3D.new()
	root.add_child(player)
	root.add_child(creature)
	creature.player = player
	creature.position = Vector3(-1.8, 0.05, -6)
	player.position = Vector3(-1.8, 0.05, -4)
	creature.update_behaviour(0.02)
	check(creature.mode == "chase", "nearby north player starts short pursuit")
	player.position = Vector3(-1.8, 0.05, -5.3)
	creature.update_behaviour(0.02)
	check(creature.mode == "windup", "close creature telegraphs before damage")
	var attempts := [0]
	creature.strike_attempt.connect(func(): attempts[0] += 1)
	creature.update_behaviour(0.50)
	check(attempts[0] == 0 and creature.mode == "windup", "first half second windup cannot damage")
	player.position = Vector3(2.0, 0.05, -5.3)
	creature.update_behaviour(0.25)
	check(attempts[0] == 0, "sidestepping readable telegraph avoids attack")
	creature.reset_creature()
	creature.mode = "chase"
	player.position = Vector3(0, 0.05, 12)
	creature.update_behaviour(0.02)
	check(creature.mode == "return", "creature disengages before reaching spawn")
	creature.reset_creature()
	player.position = Vector3(-1.8, 0.05, -3.5)
	creature.mode = "chase"
	creature.update_behaviour(4.6)
	check(creature.mode == "return", "pursuit times out after a short chase")
	creature.reset_creature()
	creature.receive_hit(Vector3(0, 0, -1))
	check(creature.hit_count == 1 and creature.mode == "stunned" and creature.health == 1, "branch hit interrupts and knocks creature back")
	creature.receive_hit(Vector3(0, 0, -1))
	check(not creature.active and creature.health == 0, "second distinct swing drives creature away")
	creature.reset_creature()
	check(creature.active and creature.health == 2 and creature.hit_count == 0 and creature.mode == "patrol", "retry restores enemy state and health")
	print("Entry creature: %d failures" % failures)
	creature.queue_free()
	player.queue_free()
	await process_frame
	quit(1 if failures else 0)
