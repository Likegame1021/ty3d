extends SceneTree
func _initialize():
	var field = load("res://environment/cornfield.gd").new()
	root.add_child(field)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20
	camera.position = Vector3(11, 16, 20)
	root.add_child(camera)
	await process_frame
	camera.look_at(Vector3(0, 0, 0))
	camera.current = true
	field.set_player_position(Vector3(-4, 0, 3))
	for i in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://environment/preview_day.png")
	field.set_night(true)
	for i in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://environment/preview_night.png")
	print("ENVIRONMENT_GPU_CAPTURE_OK corn=", field.corn_instance_count)
	quit()

