extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	for frame in 35:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/playable-day.png")
	game.set_night(true)
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/playable-night.png")
	game.set_paused(true)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/playable-pause.png")
	game.set_paused(false)
	game.set_night(false)
	game.player.position = Vector3(0, 0.05, -3.8)
	game.player.facing = Vector3(0, 0, -1)
	game.player.visual.rotation.y = PI
	game.camera_focus = Vector3(0, 0.7, -4)
	game.update_camera(1.0)
	for frame in 8:
		await process_frame
	var hit_count_before: int = game.target.hit_count
	var attack_key := InputEventKey.new()
	attack_key.physical_keycode = KEY_SPACE
	attack_key.keycode = KEY_SPACE
	attack_key.pressed = true
	Input.parse_input_event(attack_key)
	for frame in 120:
		await physics_frame
		if game.target.hit_count > hit_count_before:
			break
	var release_key := InputEventKey.new()
	release_key.physical_keycode = KEY_SPACE
	release_key.keycode = KEY_SPACE
	Input.parse_input_event(release_key)
	if game.target.hit_count == hit_count_before:
		printerr("FAIL: actual Space input did not hit before capture")
		quit(1)
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/playable-hit.png")
	root.size = Vector2i(960, 600)
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/playable-resized.png")
	game.queue_free()
	await process_frame
	print("Rendered day / night / pause / hit / resized screenshots saved in game/tests/")
	quit()
