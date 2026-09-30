extends SceneTree

var game: Node3D

func _initialize() -> void:
	call_deferred("capture")

func settle(frames := 5) -> void:
	for frame in frames:
		await process_frame

func stand_at(location: Vector3) -> void:
	game.player.position = location
	game.player.velocity = Vector3.ZERO
	game.player.facing = Vector3(0, 0, -1)
	game.player.visual.rotation.y = PI
	game.camera_focus = location + Vector3(0, 0.7, -2.8)
	game.update_camera(1.0)

func key_tap(key: Key) -> void:
	var pressed := InputEventKey.new()
	pressed.physical_keycode = key
	pressed.keycode = key
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await physics_frame
	await physics_frame
	var released := InputEventKey.new()
	released.physical_keycode = key
	released.keycode = key
	Input.parse_input_event(released)
	await process_frame

func screenshot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var code := root.get_texture().get_image().save_png("res://tests/entry-%s.png" % name)
	if code != OK:
		printerr("Failed to save M1 GPU image: ", name)
		quit(1)
	else:
		print("CAPTURE: entry-", name)

func collect_box() -> void:
	stand_at(game.chicken.position + Vector3(0, 0.05, 1.0))
	await physics_frame
	await physics_frame
	stand_at(Vector3(-5.5, 0.05, 1.7))
	await key_tap(KEY_E)

func capture() -> void:
	game = load("res://levels/entry.tscn").instantiate()
	root.add_child(game)
	await settle(18)
	await screenshot("entrance")
	stand_at(game.chicken.position + Vector3(0, 0.05, 1.0))
	await settle(6)
	await screenshot("chicken")
	stand_at(Vector3(-5.5, 0.05, 1.7))
	await settle(6)
	await screenshot("box")
	await key_tap(KEY_E)
	stand_at(game.creature.position + Vector3(0, 0, 0.8))
	game.creature.mode = "chase"
	await settle(6)
	await screenshot("danger")
	# Record a safe route without attacking or killing the creature.
	stand_at(Vector3(5.0, 0.05, -5))
	await settle(5)
	stand_at(Vector3(0, 0.05, -13))
	await key_tap(KEY_E)
	await settle(3)
	await screenshot("complete-bypass")
	if game.progress.outcome != "won" or game.creature.hit_count != 0:
		printerr("FAIL: M1 render route did not finish without attacking")
		quit(1)
		return
	root.size = Vector2i(960, 600)
	await settle(5)
	await screenshot("complete-960")
	if not menu_fits_window():
		printerr("FAIL: M1 victory menu falls outside 960x600 window")
		quit(1)
		return
	root.size = Vector2i(1280, 800)
	await settle(3)
	game.reset_run()
	await settle(4)
	await screenshot("retry-after-win")
	game.creature.set_physics_process(false)
	stand_at(game.creature.position + Vector3(0, 0, 0.8))
	for damage in 3:
		game.progress.tick(1.3, false)
		game.on_enemy_strike()
	await settle(3)
	await screenshot("failure")
	if game.progress.outcome != "lost":
		printerr("FAIL: M1 failure fixture did not fail")
		quit(1)
		return
	root.size = Vector2i(960, 600)
	await settle(5)
	await screenshot("failure-960")
	if not menu_fits_window():
		printerr("FAIL: M1 failure menu falls outside 960x600 window")
		quit(1)
		return
	root.size = Vector2i(1280, 800)
	await settle(3)
	await key_tap(KEY_R)
	game.creature.set_physics_process(true)
	await settle(4)
	await screenshot("retry-after-failure")
	root.size = Vector2i(960, 600)
	await settle(6)
	await screenshot("resized")
	await key_tap(KEY_TAB)
	await settle(5)
	await screenshot("night")
	game.queue_free()
	await process_frame
	print("ENTRY_GPU_CAPTURE_OK")
	quit()

func menu_fits_window() -> bool:
	var panel: Control = game.hud.pause_overlay.find_children("*", "PanelContainer", true, false)[0]
	var rect := panel.get_global_rect()
	var transform := root.get_final_transform()
	var top_left: Vector2 = transform * rect.position
	var bottom_right: Vector2 = transform * rect.end
	return top_left.x >= 0.0 and top_left.y >= 0.0 and bottom_right.x <= root.size.x and bottom_right.y <= root.size.y
