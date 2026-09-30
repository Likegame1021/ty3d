extends "res://tests/test_input.gd"

func run_checks() -> void:
	var game = load("res://levels/entry.tscn").instantiate()
	root.add_child(game)
	for frame in 3:
		await physics_frame
	game.player.position = game.chicken.position + Vector3(0, 0.05, 1)
	for frame in 3:
		await physics_frame
	game.player.position = Vector3(-5.5, 0.05, 1.7)
	await tap_key(KEY_ESCAPE)
	await tap_key(KEY_E)
	check(paused and not game.progress.item_collected, "E input cannot pick box through pause overlay")
	await tap_key(KEY_ESCAPE)
	await tap_key(KEY_E)
	check(game.progress.item_collected and game.progress.pickup_count == 1, "real E input collects marble box")
	await tap_key(KEY_E)
	check(game.progress.pickup_count == 1, "repeated E input never duplicates item")
	game.creature.receive_hit(Vector3(0, 0, -1))
	await tap_key(KEY_ESCAPE)
	check(paused and game.hud.pause_overlay.visible and game.paused_menu, "Esc opens M1 pause menu")
	var frozen_time: float = game.progress.elapsed
	var frozen_enemy: Vector3 = game.creature.position
	await tap_key(KEY_SPACE)
	await tap_key(KEY_E)
	check(game.player.attack.remaining == 0 and game.progress.elapsed == frozen_time and game.creature.position == frozen_enemy, "paused attack interaction enemy and timer stay frozen")
	await click_control(game.hud.resume_button)
	for frame in 3:
		await physics_frame
	check(not paused and game.player.attack.remaining == 0, "resume pointer click continues without leaking attack")
	await tap_key(KEY_ESCAPE)
	await tap_key(KEY_R)
	check(not paused and game.progress.stage == 0 and not game.progress.item_collected and game.progress.health == 3, "R from pause retries complete quest")
	check(game.creature.health == 2 and game.creature.mode == "patrol" and game.creature.active, "paused retry removes creature stun and restores health")
	check(game.player.attack.remaining == 0 and game.player.position.distance_to(Vector3(0, 0.05, 12)) < 0.08, "paused retry clears attack and restores entry spawn")
	await tap_key(KEY_ESCAPE)
	await click_control(game.hud.retry_button)
	for frame in 3:
		await physics_frame
	check(not paused and game.player.attack.remaining == 0 and game.progress.pickup_count == 0, "pause retry button resets without click-through attack")
	game.player.position = game.chicken.position + Vector3(0, 0.05, 0.7)
	for frame in 3:
		await physics_frame
	game.player.position = Vector3(-5.5, 0.05, 1.6)
	await tap_key(KEY_E)
	game.player.position = Vector3(4, 0.05, -5)
	for frame in 3:
		await physics_frame
	game.player.position = Vector3(0, 0.05, -13)
	await tap_key(KEY_E)
	check(game.progress.outcome == "won" and paused, "E at exit completes non-combat route")
	await tap_key(KEY_ESCAPE)
	check(paused and game.progress.outcome == "won", "Esc cannot unfreeze danger after victory")
	await click_control(game.hud.retry_button)
	for frame in 3:
		await physics_frame
	check(game.progress.outcome == "playing" and not paused and game.progress.health == 3 and game.player.attack.remaining == 0, "victory retry button starts clean without attack")
	game.player.position = game.creature.position + Vector3(0, 0, 0.8)
	for damage in 3:
		game.progress.tick(1.3, false)
		game.on_enemy_strike()
	check(game.progress.outcome == "lost" and paused, "failure overlay reached for input retry")
	await tap_key(KEY_R)
	check(game.progress.outcome == "playing" and game.progress.health == 3 and not paused and not game.progress.item_collected, "R from failure restarts all progress")
	game.creature.set_physics_process(false)
	game.player.position = game.creature.position + Vector3(0, 0, 0.8)
	for damage in 3:
		game.progress.tick(1.3, false)
		game.on_enemy_strike()
	await click_control(game.hud.retry_button)
	for frame in 3:
		await physics_frame
	check(game.progress.outcome == "playing" and game.progress.health == 3 and not paused and game.player.attack.remaining == 0, "failure retry button starts clean without click-through attack")
	game.creature.set_physics_process(true)
	await tap_key(KEY_TAB)
	check(game.night, "M1 Tab retains night preview")
	await tap_key(KEY_TAB)
	check(not game.night, "M1 Tab restores day")
	print("Entry input pipeline: %d failures" % failures)
	paused = false
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
