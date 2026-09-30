extends SceneTree

var game: Node3D

func _initialize() -> void:
	call_deferred("capture")

func settle(frames := 5) -> void:
	for frame in frames:
		await process_frame

func stand_at(point: Vector3, face := Vector3(0, 0, -1)) -> void:
	game.player.position = point + Vector3.UP * 0.05
	game.player.velocity = Vector3.ZERO
	game.player.facing = face
	game.player.visual.rotation.y = atan2(face.x, face.z)
	game.camera_focus = game.player.position + Vector3(0, 0.7, -2.8)
	game.update_camera(1.0)

func shot(name: String) -> bool:
	await RenderingServer.frame_post_draw
	var code := root.get_texture().get_image().save_png("res://tests/full-%s.png" % name)
	if code != OK:
		printerr("FAIL: could not save full scene capture ", name)
		return false
	print("CAPTURE: full-", name)
	return true

func menu_fits_window() -> bool:
	var rect: Rect2 = game.hud.menu_panel.get_global_rect()
	var transform := root.get_final_transform()
	var top_left: Vector2 = transform * rect.position
	var bottom_right: Vector2 = transform * rect.end
	return top_left.x >= 0 and top_left.y >= 0 and bottom_right.x <= root.size.x and bottom_right.y <= root.size.y

func complete_earlier_zones() -> void:
	stand_at(Vector3(-3.5, 0, 36))
	await physics_frame
	await physics_frame
	stand_at(Vector3(-5, 0, 31.8))
	game.interact()
	stand_at(Vector3(0, 0, 22.5))
	game.interact()
	stand_at(Vector3(5, 0, 21.5))
	game.interact()
	await settle(3)

func capture() -> void:
	root.size = Vector2i(1280, 800)
	game = load("res://levels/full.tscn").instantiate()
	root.add_child(game)
	await settle(22)
	if not await shot("entrance"):
		quit(1)
		return
	stand_at(Vector3(5, 0, 21.5))
	await settle(8)
	await shot("canal-closed")
	await complete_earlier_zones()
	await settle(8)
	await shot("canal-open")
	stand_at(Vector3(-7, 0, 9))
	await settle(7)
	game.throw_stone()
	await settle(5)
	await shot("dense-pursuit")
	stand_at(Vector3(12, 0, -9))
	game.interact()
	stand_at(Vector3(16, 0, -13))
	game.interact()
	await settle(6)
	await shot("cart-moved")
	stand_at(Vector3(17, 0, -18))
	game.interact()
	stand_at(Vector3(0, 0, -29))
	await settle(8)
	if not game.progress.boss_active:
		printerr("FAIL: render fixture did not reach boss")
		quit(1)
		return
	await shot("boss-approach")
	game.boss.set_physics_process(false)
	game.boss.skill_index = 1
	game.boss.mode = "idle"
	game.boss.phase_remaining = 0.1
	game.boss.player_position = Vector3(0, 0, -30)
	game.boss.advance(0.2)
	game.boss.advance(0.48)
	await settle(5)
	await shot("boss-burrow")
	game.boss.mode = "recover"
	game.boss.phase_remaining = 99
	game.boss.position = Vector3(0, 0, -34)
	game.boss.collision_layer = 4
	for hit in 6:
		game.boss.hit_cooldown = 0
		game.boss.receive_hit(Vector3.FORWARD)
	stand_at(Vector3(4.4, 0, -31))
	await settle(8)
	await shot("corn-spilled")
	stand_at(Vector3(5, 0, -32))
	game.interact()
	game.camera.size = 11.5
	stand_at(Vector3(0, 0, -31), Vector3(0, 0, -1))
	await settle(7)
	await shot("corn-gun")
	game.fire_gun(true)
	await settle(2)
	await shot("corn-scatter")
	game.boss.hit_cooldown = 0
	game.boss.receive_projectile(6)
	if game.progress.outcome != "won":
		printerr("FAIL: render fixture did not win")
		quit(1)
		return
	root.size = Vector2i(960, 600)
	await settle(7)
	await shot("victory-960")
	if not menu_fits_window():
		printerr("FAIL: victory menu outside 960x600")
		quit(1)
		return
	game.reset_run()
	game.camera.size = 15.0
	for hit in game.progress.max_health:
		game.on_player_hurt()
		game.progress.tick(2)
	if game.progress.outcome != "lost":
		printerr("FAIL: render fixture did not fail")
		quit(1)
		return
	await settle(7)
	await shot("failure-960")
	if not menu_fits_window():
		printerr("FAIL: failure menu outside 960x600")
		quit(1)
		return
	game.queue_free()
	await process_frame
	print("FULL_GPU_CAPTURE_OK")
	quit()
