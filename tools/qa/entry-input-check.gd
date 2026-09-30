extends SceneTree

var failures := 0

func check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		printerr("FAIL: ", description)

func _initialize() -> void:
	call_deferred("run_checks")

func tap_key(key: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = key
	down.physical_keycode = key
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	await physics_frame
	await physics_frame
	var up := InputEventKey.new()
	up.keycode = key
	up.physical_keycode = key
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame

func click_control(control: Control) -> void:
	# Convert UI coordinates to physical window coordinates for Godot viewport dispatch.
	var location: Vector2 = root.get_final_transform() * control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = location
	motion.global_position = location
	Input.parse_input_event(motion)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = location
	down.global_position = location
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = location
	up.global_position = location
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame

func run_checks() -> void:
	var packed: PackedScene = load("res://levels/entry.tscn")
	if packed == null:
		check(false, "entry scene loads")
		quit(1)
		return
	var game = packed.instantiate()
	root.add_child(game)
	for frame in range(4):
		await physics_frame
	await tap_key(KEY_ESCAPE)
	check(paused and game.paused_menu and game.hud.pause_overlay.visible, "Esc opens the M1 pause menu")
	var before_position: Vector3 = game.player.position
	var before_stage: int = game.progress.stage
	await tap_key(KEY_SPACE)
	await tap_key(KEY_W)
	await tap_key(KEY_E)
	check(game.player.attack.remaining == 0.0 and game.player.position == before_position and game.progress.stage == before_stage,
		"paused keys cannot attack, move, or advance the quest")
	check(game.hud.resume_button.visible and not game.hud.retry_button.visible, "pause menu shows Continue only")
	await click_control(game.hud.resume_button)
	check(not paused and not game.hud.pause_overlay.visible, "Continue button resumes gameplay")
	for frame in range(3):
		await physics_frame
	check(game.player.attack.remaining == 0.0, "Continue click does not leak into attack")
	await tap_key(KEY_ESCAPE)
	await tap_key(KEY_R)
	check(not paused and game.progress.outcome == "playing" and game.progress.stage == 0 and game.progress.health == 3,
		"R restarts from the paused state and unpauses")

	# Put the game into a failed result through its real outcome handler, then route
	# a pointer event through the actual retry Button and check it does not attack.
	game.progress.health = 1
	game.player.position = game.creature.position + Vector3(0, 0.05, 0.8)
	game.on_enemy_strike()
	check(game.progress.outcome == "lost" and paused and game.hud.retry_button.visible,
		"failure exposes a retry button and freezes gameplay")
	await click_control(game.hud.retry_button)
	check(not paused and game.progress.outcome == "playing" and game.progress.health == 3 and game.progress.stage == 0,
		"Retry button restores the initial quest and unpauses")
	check(game.player.attack.remaining == 0.0 and game.player.position.distance_to(Vector3(0, 0.05, 12)) < 0.08,
		"Retry click does not leak into attack and returns the player to spawn")
	print("Entry input routing: %d failures" % failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
