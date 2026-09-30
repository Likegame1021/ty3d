extends SceneTree

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
	else:
		print("PASS: ", message)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	if not ResourceLoader.exists("res://levels/corn_lab.tscn"):
		check(false, "corn trial is available without replaying adventure unlock steps")
		quit(1)
		return
	var game = load("res://levels/corn_lab.tscn").instantiate()
	root.add_child(game)
	for frame in 4:
		await physics_frame
	check(game.gun_equipped and game.progress.corn_gun, "trial starts with corn gun equipped")
	check(game.practice_targets.size() >= 3, "trial provides several real damageable targets")
	var target = game.practice_targets[0]
	var before: int = target.health
	game.player.facing = (target.global_position - game.player.global_position).normalized()
	game.player.facing.y = 0
	game.player.facing = game.player.facing.normalized()
	game.fire_gun(false)
	check(target.health < before, "trial target receives an actual corn shot")
	game.start_combat_trial()
	await physics_frame
	check(game.lab_mode == 1 and game.minions.size() > 0, "combat trial spawns moving enemies")
	var safe_spawns := true
	for enemy in game.minions:
		safe_spawns = safe_spawns and enemy.position.distance_to(game.player.position) >= 4.0
	check(safe_spawns, "trial enemies spawn with room to react")
	game.player.position = Vector3(-6, 0.05, -39)
	game.spawn_lab_wave()
	safe_spawns = true
	for enemy in game.minions:
		safe_spawns = safe_spawns and enemy.position.distance_to(game.player.position) >= 4.0
	check(safe_spawns, "later waves keep clear of the player's current position")
	game.reset_run()
	await physics_frame
	check(game.gun_equipped and game.progress.health == 5 and game.lab_mode == 0, "retry returns to clean armed practice mode")
	check(game.minions.is_empty() and not game.boss.active, "retry removes trial enemies and boss")
	check(get_nodes_in_group("corn_tracers").is_empty(), "retry removes old projectile effects")
	game.start_boss_trial()
	await physics_frame
	check(game.lab_mode == 2 and game.boss.active and game.progress.boss_hp == 36, "boss trial starts a fresh sustained weapon challenge")
	game.reset_run()
	await physics_frame
	check(not game.boss.active and game.gun_equipped, "boss trial can be reset directly to practice")
	paused = false
	game.queue_free()
	await process_frame
	await process_frame
	print("Corn trial: %d failures" % failures)
	quit(1 if failures else 0)
