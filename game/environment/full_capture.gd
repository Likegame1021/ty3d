extends SceneTree

var field: Node3D
var camera: Camera3D

func _initialize() -> void:
	call_deferred("_capture_all")

func _settle() -> void:
	for i in 7:
		await process_frame

func _shot(label: String, focus: Vector3, weather_mode: String, night_mode: bool) -> void:
	field.set_player_position(focus)
	field.set_weather(weather_mode)
	field.set_night(night_mode)
	camera.global_position = focus + Vector3(15, 19, 15)
	camera.look_at(focus, Vector3.UP)
	await _settle()
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("res://tests/full-env-%s.png" % label)
	if error != OK:
		printerr("FULL_ENV_CAPTURE_FAILED ", label, " code=", error)
		quit(1)
	else:
		print("CAPTURE full-env-", label)

func _capture_all() -> void:
	root.size = Vector2i(1280, 800)
	field = load("res://environment/full_field.gd").new()
	root.add_child(field)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 16.0
	camera.near = 0.1
	camera.far = 120.0
	root.add_child(camera)
	camera.current = true
	await _shot("entrance", Vector3(0, 0, 36), "sunny", false)
	await _shot("canal", Vector3(3, 0, 20), "sunny", false)
	field.set_progress({"mouth_cleared": true})
	await _shot("canal-cleared", Vector3(0, 0, 22), "sunny", false)
	field.set_progress({"canal_open": true})
	await _shot("canal-open", Vector3(0, 0, 22), "sunny", false)
	field.reset_field()
	await _shot("dense", Vector3(-6, 0, 5), "sunny", false)
	await _shot("farm", Vector3(15, 0, -14), "sunny", false)
	await _shot("farm-inside", Vector3(17, 0, -18), "sunny", false)
	await _shot("farm-rain", Vector3(15, 0, -14), "rain", false)
	await _shot("farm-snow", Vector3(15, 0, -14), "snow", false)
	await _shot("boss", Vector3(0, 0, -34), "sunny", false)
	await _shot("entrance-night", Vector3(0, 0, 36), "sunny", true)
	await _shot("canal-night", Vector3(5, 0, 20), "sunny", true)
	await _shot("farm-night", Vector3(15, 0, -14), "sunny", true)
	await _shot("boss-night", Vector3(0, 0, -34), "sunny", true)
	for mode in ["sunny", "rain", "snow"]:
		for dark in [false, true]:
			await _shot("%s-%s" % [mode, "night" if dark else "day"], Vector3(-6, 0, 5), mode, dark)
	field.queue_free()
	await process_frame
	print("FULL_ENV_GPU_CAPTURE_OK")
	quit()
