extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1280, 800)
	var world := Node3D.new()
	root.add_child(world)
	var player = load("res://scripts/player.gd").new()
	world.add_child(player)
	player.set_physics_process(false)
	player.position = Vector3.ZERO
	player.visual.rotation = Vector3.ZERO
	player.facing = Vector3.BACK
	player.branch_pivot.get_node("Branch").visible = false
	player.animation_player.play("idle")
	player.animation_player.seek(0.25, true)
	player.animation_player.pause()
	var gun = load("res://weapons/corn_gun_visual.gd").new()
	world.add_child(gun)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.9
	camera.position = Vector3(-2.5, 1.8, 2.5)
	camera.look_at(Vector3(0, 0.65, 0.20))
	var sun := DirectionalLight3D.new()
	world.add_child(sun)
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.1
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("a97543")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("efe0be")
	env.environment.ambient_light_energy = 0.55
	world.add_child(env)
	for pose_name in ["before", "after"]:
		player.ranged_stance = pose_name == "after"
		for frame in 8:
			await process_frame
			gun.global_position = player.branch_pivot.global_position
			gun.global_basis = Basis.looking_at(player.facing, Vector3.UP)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://weapons/corn-hold-%s.png" % pose_name)
		print("CAPTURE_CORNHOLD_", pose_name)
	camera.position = Vector3(-3.5, 1.5, -1.0)
	camera.look_at(Vector3(0, 0.65, 0.20))
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://weapons/corn-hold-side.png")
	player.animation_player.play("walk")
	player.animation_player.seek(0.25, true)
	player.animation_player.pause()
	for frame in 5:
		await process_frame
		gun.global_position = player.branch_pivot.global_position
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://weapons/corn-hold-walk.png")
	world.free()
	quit(0)
