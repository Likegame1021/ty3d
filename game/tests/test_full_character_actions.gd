extends SceneTree

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
	var game = load("res://levels/full.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	var player = game.player
	# Count the nine source GLB clips, excluding private derived runtime libraries.
	var clips = player.animation_player.get_animation_library("").get_animation_list()
	check(clips.size() == 9, "v004 GLB imports four original and five context clips")
	var old_lengths := {"idle":4.0416667, "walk":4.2083333, "run":0.75, "attack_branch":1.5416667}
	for key in old_lengths:
		check(absf(player.animation_player.get_animation(key).length - old_lengths[key]) < 0.005, "original imported clip duration unchanged: " + key)
	if not player.has_method("play_context_action"):
		check(false, "optional context action API exists")
		game.queue_free()
		await process_frame
		quit(1)
		return
	check(player.extra_animation_names.size() == 5, "five optional clips are discovered without changing core four mapping")
	check(absf(player.animation_player.get_animation("pick_up").length - 1.64) < 0.04, "trimmed pickup clip imports at roughly 1.6 seconds")
	check(player.play_context_action("pick_up") and player.current_animation == "pick_up", "pickup clip starts on demand")
	await physics_frame
	check(player.context_remaining > 0 and player.current_animation == "pick_up", "pickup is not immediately overwritten by idle")
	player.request_attack()
	check(player.attack.remaining == 0, "branch cannot interrupt active pickup")
	player.context_remaining = 0
	for frame in 3:
		await physics_frame
	check(player.current_animation == "idle", "completed action returns to idle")
	player.request_attack()
	check(player.attack.remaining > 0, "original branch attack remains available")
	check(player.play_context_action("hurt") and player.attack.remaining > 0 and player.current_animation == "attack_branch", "damage during committed branch preserves its hit window")
	check(player.pending_context_action == "hurt", "reaction is queued behind committed branch")
	game.set_paused(true)
	var paused_attack: float = player.attack.remaining
	await physics_frame
	check(player.pending_context_action == "hurt" and player.attack.remaining == paused_attack, "pause freezes pending reaction and attack window")
	game.set_paused(false)
	player.attack.remaining = 0.0
	await physics_frame
	check(player.current_animation == "hurt", "queued damage reaction plays after branch completes")
	player.request_attack()
	check(player.attack.remaining > 0 and player.current_animation == "attack_branch", "combat input can recover from hurt without being swallowed")
	player.reset_player()
	check(player.context_remaining == 0 and player.context_action == "" and player.attack.remaining == 0, "reset clears one-shot state")
	game.progress.chicken_seen = true
	player.position = game.TIN + Vector3.UP * 0.05
	game.interact()
	check(game.progress.tin_taken and player.current_animation == "pick_up", "collecting the tin triggers pickup clip")
	game.reset_run()
	game.progress.tin_taken = true
	player.position = game.MOUTH + Vector3.UP * 0.05
	game.interact()
	check(game.progress.mouth_cleared and player.current_animation == "interact", "clearing the water mouth triggers interaction clip")
	game.reset_run()
	game.progress.dense_entered = true
	player.position = game.FENCE + Vector3(0, 0.05, 1.0)
	game.interact()
	check(game.progress.fence_vaulted and player.current_animation == "vault", "crossing fence triggers vault clip")
	game.reset_run()
	game.progress.board_taken = true
	player.position = game.CART + Vector3.UP * 0.05
	game.interact()
	check(game.progress.cart_moved and player.current_animation == "push", "moving cart triggers push clip")
	game.reset_run()
	game.on_player_hurt()
	check(game.progress.health == 4 and player.current_animation == "hurt", "accepted damage triggers reaction clip")
	game.reset_run()
	player.request_attack()
	game.on_player_hurt()
	check(player.attack.remaining > 0.0 and player.pending_context_action == "hurt", "scene damage queues reaction during branch")
	game.progress.outcome = "lost"
	game.finish_run()
	check(player.attack.remaining == 0.0 and player.pending_context_action == "" and player.context_action == "", "loss clears queued and active character actions")
	game.reset_run()
	check(player.context_action == "" and player.context_remaining == 0.0 and player.pending_context_action == "", "full retry clears contextual animation")
	print("Full character actions: %d failures" % failed)
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
