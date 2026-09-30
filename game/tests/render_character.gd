extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.player.set_physics_process(false)
	game.hud.visible = false
	game.camera.size = 2.3
	game.camera.position = game.player.position + Vector3(2.0, 1.7, -3.0)
	game.camera.look_at(game.player.position + Vector3(0, 0.7, 0))
	var clips := {"idle": 0.4, "walk": 0.4, "run": 0.2, "attack_branch": 0.6}
	for clip in clips:
		game.player.animation_player.play(clip)
		game.player.animation_player.seek(clips[clip], true)
		game.player.animation_player.pause()
		for frame in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/character-%s.png" % clip)
	print("Actual character GPU close views: idle / walk / run / attack_branch")
	game.queue_free()
	await process_frame
	quit()
