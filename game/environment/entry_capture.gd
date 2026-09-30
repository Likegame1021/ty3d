extends SceneTree
func _initialize():
	var field = load("res://environment/entry_field.gd").new()
	root.add_child(field)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 22
	camera.position = Vector3(11,18,22)
	root.add_child(camera)
	await process_frame
	camera.look_at(Vector3(0,0,1))
	camera.current = true
	field.set_player_position(Vector3(0,0,12))
	field.set_story_sources(Vector3(-3.8,0,7),Vector3(-1.8,0,-6),true)
	for i in range(15):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://environment/entry_preview_day.png")
	field.set_night(true)
	for i in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://environment/entry_preview_night.png")
	field.set_night(false)
	field.set_story_stage(1)
	field.set_player_position(Vector3(-4.5,0,4))
	camera.size = 11
	camera.position = Vector3(-4.8,13,17)
	camera.look_at(Vector3(-4.5,0,4))
	for i in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://environment/entry_preview_sidepath.png")
	print("ENTRY_GPU_CAPTURE_OK corn=",field.corn_instance_count)
	field.set_story_stage(3)
	field.queue_free()
	camera.queue_free()
	await process_frame
	await process_frame
	quit()

