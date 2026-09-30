extends SceneTree

var game: Node3D
const OUT := "res://tests/corn-"

func _initialize() -> void:
	call_deferred("capture")

func settle(frames: int) -> void:
	for frame in frames:
		await process_frame
		await physics_frame

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(OUT + label + ".png")
	if error != OK:
		printerr("FAIL: corn capture ", label)
		quit(1)

func capture() -> void:
	root.size = Vector2i(1280, 800)
	game = load("res://levels/corn_lab.tscn").instantiate()
	root.add_child(game)
	await settle(15)
	# Warm the renderer's effect materials before capturing short-lived flashes.
	game.player.facing = Vector3.FORWARD
	game.fire_gun(true)
	await settle(20)
	game.reset_run()
	await settle(8)
	game.hud.message_time = 0
	game.hud.message_label.visible = false
	await shot("practice")
	game.player.facing = Vector3.FORWARD
	game.aim_screen = game.camera.unproject_position(Vector3(0, 0.45, -34))
	game.mouse_aim_active = true
	game.charging = true
	game.charge_time = 0.8
	await settle(3)
	await shot("charge")
	# PNG encoding can lengthen the next delta enough to age out a muzzle flash.
	# Let that frame pass before triggering the short effect under inspection.
	await settle(3)
	game.charging = false
	game.charge_time = 0
	game.fire_cooldown = 0
	game.fire_gun(true)
	await process_frame
	await shot("scatter")
	await settle(30)
	game.fire_cooldown = 0
	game.fire_gun(false)
	await process_frame
	await shot("hit")
	await settle(30)
	game.start_combat_trial()
	await settle(55)
	game.fire_cooldown = 0
	game.fire_gun(true)
	await process_frame
	await shot("combat")
	game.reset_run()
	game.set_night(true)
	game.set_weather("rain")
	await settle(20)
	game.charging = true
	game.charge_time = 0.8
	await settle(3)
	await shot("rain-night")
	game.reset_run()
	root.size = Vector2i(960, 600)
	await settle(15)
	game.charging = true
	game.charge_time = 0.6
	await settle(3)
	await shot("960")
	game.cancel_gun_input()
	game.set_process(false)
	game.set_physics_process(false)
	game.camera.size = 3.5
	var center: Vector3 = game.player.global_position + Vector3(0, 0.65, -0.2)
	game.camera.position = center + Vector3(3.0, 2.2, 3.0)
	game.camera.look_at(center)
	game.hud.visible = false
	await settle(5)
	await shot("grip")
	paused = false
	game.queue_free()
	await process_frame
	await process_frame
	print("CORN_GPU_CAPTURE_OK")
	quit()
