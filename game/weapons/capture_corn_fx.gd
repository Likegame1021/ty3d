extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1280, 800)
	var world := Node3D.new()
	root.add_child(world)
	var visual = load("res://weapons/corn_gun_visual.gd").new()
	world.add_child(visual)
	visual.rotation.y = 0.3
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.85
	camera.position = Vector3(1.4, 1.5, 1.2)
	camera.look_at(Vector3(0, 0.06, -0.2))
	var sun := DirectionalLight3D.new()
	world.add_child(sun)
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.1
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("596541")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("efe0be")
	env.environment.ambient_light_energy = 0.55
	world.add_child(env)
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://weapons/corn-visual-review.png")
	print("CORN_VISUAL_CAPTURE_OK")
	world.free()
	quit(0)
