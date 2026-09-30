extends SceneTree

const OUTPUT_DIR := "G:/Game/vallage/docs/qa"
const FAR_POSITION := Vector3(1000.0, 0.0, 1000.0)
const PLOT_CENTER := Vector3(3.7, 0.0, -12.0)

var field
var materials: Array[ShaderMaterial] = []

func _initialize() -> void:
	call_deferred("run_capture")

func run_capture() -> void:
	root.size = Vector2i(960, 600)
	var scene = load("res://environment/cornfield.gd")
	if scene == null:
		fail("Could not load cornfield.gd")
		return
	field = scene.new()
	root.add_child(field)
	await process_frame
	field.set_process(false)
	materials = field._corn_materials
	if materials.is_empty() or field.corn_instance_count == 0:
		fail("Corn material or instances are missing")
		return

	var camera := Camera3D.new()
	camera.name = "CornCloseupCamera"
	camera.fov = 58.0
	field.add_child(camera)
	camera.position = Vector3(3.7, 4.7, -7.0)
	camera.look_at(Vector3(3.7, 1.05, -12.0), Vector3.UP)
	camera.current = true
	await process_frame

	# Keep the moving demo source out of this framing so the comparisons isolate
	# wind time first, then the player-proximity bend.
	set_shader_state(0.0, FAR_POSITION)
	var still_image := await capture("corn-wind-t0.png")
	set_shader_state(0.8, FAR_POSITION)
	var wind_image := await capture("corn-wind-t08.png")
	set_shader_state(0.8, PLOT_CENTER)
	var player_image := await capture("corn-player-push.png")

	var wind_pixels := count_changed_corn_pixels(still_image, wind_image)
	var player_pixels := count_changed_corn_pixels(wind_image, player_image)
	print("Corn wind changed green pixels: ", wind_pixels)
	print("Player proximity changed green pixels: ", player_pixels)
	if wind_pixels < 50:
		fail("Wind comparison changed too few corn pixels: %d" % wind_pixels)
	elif player_pixels < 50:
		fail("Player proximity comparison changed too few corn pixels: %d" % player_pixels)
	else:
		print("CORN_DISTURBANCE_GPU_OK")
		quit(0)

func set_shader_state(animation_time: float, player_position: Vector3) -> void:
	for material in materials:
		material.set_shader_parameter("animation_time", animation_time)
		material.set_shader_parameter("player_position", player_position)
		material.set_shader_parameter("disturbance_position", FAR_POSITION)

func capture(file_name: String) -> Image:
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var error := image.save_png(OUTPUT_DIR.path_join(file_name))
	if error != OK:
		fail("Could not save %s: %s" % [file_name, error_string(error)])
	return image

func count_changed_corn_pixels(before: Image, after: Image) -> int:
	if before.get_size() != after.get_size():
		return 0
	var changed := 0
	for y in range(before.get_height()):
		for x in range(before.get_width()):
			var a := before.get_pixel(x, y)
			# Corn foliage is the green-dominant region of this close framing.
			if a.g < 0.055 or a.g < a.r * 1.08 or a.g < a.b * 1.08:
				continue
			var b := after.get_pixel(x, y)
			var delta := absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			if delta > 0.075:
				changed += 1
	return changed

func fail(message: String) -> void:
	printerr("CORN_DISTURBANCE_GPU_FAIL: ", message)
	quit(1)
