extends "res://tests/test_input.gd"

func right_button(pressed: bool, point := Vector2(640, 400)) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.position = root.get_final_transform() * point
	event.global_position = event.position
	event.pressed = pressed
	Input.parse_input_event(event)

func run_checks() -> void:
	root.size = Vector2i(960, 600)
	var game = load("res://levels/full.tscn").instantiate()
	root.add_child(game)
	for frame in 3:
		await physics_frame
	await tap_key(KEY_F6)
	check(game.weather == "rain" and not game.night, "F6 changes sunny to rain without changing day")
	await tap_key(KEY_TAB)
	check(game.weather == "rain" and game.night, "Tab switches night independently of weather")
	await tap_key(KEY_ESCAPE)
	check(paused and game.hud.pause_overlay.visible, "Esc opens pause menu")
	var stopped: float = game.progress.elapsed
	await tap_key(KEY_F6)
	await tap_key(KEY_E)
	await tap_key(KEY_SPACE)
	check(game.weather == "rain" and game.progress.elapsed == stopped and game.player.attack.remaining == 0, "paused weather key E and attack do not leak")
	await click_control(game.hud.weather_row.get_child(2))
	check(game.weather == "snow" and game.night and paused, "pause menu selects snow while retaining night")
	await click_control(game.hud.resume_button)
	for frame in 3:
		await physics_frame
	check(not paused and game.player.attack.remaining == 0, "resume pointer click cannot swing branch")
	game.player.position = game.chicken.position + Vector3(0, 0.05, 1)
	for frame in 3:
		await physics_frame
	game.player.position = Vector3(-5, 0.05, 31.8)
	await tap_key(KEY_E)
	check(game.progress.tin_taken, "real E input picks tin after chicken clue")
	await tap_key(KEY_Q)
	check(not game.gun_equipped, "Q cannot equip unfinished launcher")
	game.progress.boss_active = true
	game.progress.corn_spilled = true
	game.progress.corn_gun = true
	game.boss.active = true
	game.boss.set_physics_process(false)
	game.boss.position = Vector3(0, 0, -34)
	game.player.position = Vector3(0, 0.05, -30)
	game.player.facing = Vector3(0, 0, -1)
	await tap_key(KEY_Q)
	check(game.gun_equipped and game.gun_model.visible, "real Q input equips visible corn gun")
	game.update_camera(1.0)
	var boss_screen: Vector2 = game.camera.unproject_position(game.boss.position + Vector3.UP)
	right_button(true, boss_screen)
	for frame in 60:
		await physics_frame
	check(game.charge_time >= 0.8 and game.hud.charge_label.text.contains("就绪"), "holding right click reaches readable charge threshold")
	right_button(false, boss_screen)
	await process_frame
	await process_frame
	await physics_frame
	check(game.progress.boss_hp == 9 and not game.charging, "right release fires one charged shot for three damage")
	await tap_key(KEY_ESCAPE)
	right_button(true)
	for frame in 10:
		await physics_frame
	check(not game.charging and paused, "paused right click cannot start stale charge")
	right_button(false)
	await process_frame
	await process_frame
	await tap_key(KEY_R)
	check(game.progress.outcome == "playing" and not paused and game.weather == "sunny" and not game.night and not game.gun_equipped, "R from pause resets weather night and weapon")
	game.boss.set_physics_process(true)
	for damage in game.progress.max_health:
		game.on_player_hurt()
		game.progress.tick(2)
	check(game.progress.outcome == "lost" and paused, "input path reaches failure menu")
	await process_frame
	await process_frame
	var retry_clicks := [0]
	game.hud.retry_button.pressed.connect(func(): retry_clicks[0] += 1)
	await click_control(game.hud.retry_button)
	for frame in 3:
		await physics_frame
	check(retry_clicks[0] == 1, "failure retry button receives actual pointer click")
	check(game.progress.outcome == "playing" and not paused and game.progress.health == game.progress.max_health and game.player.attack.remaining == 0, "failure retry click starts clean without attack")
	print("Full input pipeline: %d failures" % failures)
	paused = false
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
