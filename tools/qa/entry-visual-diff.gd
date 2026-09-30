extends SceneTree

const OUTPUT_DIR := "G:/Game/vallage/docs/qa/entry-visual"
const FAR := Vector3(1000.0, 0.0, 1000.0)
const CHICKEN_HOME := Vector3(-3.8, 0.0, 7.0)
const CREATURE_HOME := Vector3(-1.8, 0.0, -6.0)
const PLAYER_NEAR_CORN := Vector3(-6.0, 0.0, 1.0)

var field
var camera: Camera3D
var results: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run_visual_checks")

func run_visual_checks() -> void:
	var dir_error := DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	if dir_error != OK:
		fail("Cannot create QA output directory: %s" % error_string(dir_error))
		return
	var field_script = load("res://environment/entry_field.gd")
	if field_script == null:
		fail("Entry environment script is missing")
		return
	field = field_script.new()
	root.size = Vector2i(960, 600)
	root.add_child(field)
	await process_frame
	field.set_process(false)
	if field._corn_materials.is_empty() or field.corn_instance_count == 0:
		fail("Entry corn field has no renderable plots")
		return
	camera = Camera3D.new()
	camera.fov = 58.0
	root.add_child(camera)
	camera.current = true

	# 1. Wind only: identical camera and sources, different fixed shader time.
	await compare_state("wind", Vector3(-7.0, 3.6, 11.5), Vector3(-3.8, 1.0, 7.0),
		0.0, FAR, FAR, FAR, false,
		0.8, FAR, FAR, FAR, false)

	# 2. Harmless chicken cue: fixed time and camera, only chicken position changes.
	await compare_state("chicken", Vector3(-7.0, 3.6, 11.5), Vector3(-3.8, 1.0, 7.0),
		0.8, FAR, FAR, FAR, false,
		0.8, FAR, CHICKEN_HOME, FAR, false)

	# 3. Creature cue: frame the north-side corn edge; only active story source changes.
	await compare_state("creature", Vector3(-4.8, 3.8, -1.2), Vector3(-1.8, 1.0, -6.0),
		0.8, FAR, FAR, CREATURE_HOME, false,
		0.8, FAR, FAR, CREATURE_HOME, true)

	# 4. Player proximity: identical time and story sources, player moves beside the stalks.
	await compare_state("player", Vector3(-8.0, 3.8, 5.8), Vector3(-5.5, 1.0, 1.0),
		0.8, FAR, FAR, FAR, false,
		0.8, PLAYER_NEAR_CORN, FAR, FAR, false)

	var failed := false
	var lines := PackedStringArray(["case,pixel_diff,changed_green_pixels,passed"])
	for result in results:
		var passed: bool = result.changed_green_pixels >= 50
		lines.append("%s,%d,%d,%s" % [result.case, result.pixel_diff, result.changed_green_pixels, str(passed)])
		print("ENTRY_VISUAL ", result.case, " changed_green_pixels=", result.changed_green_pixels,
			" pixel_diff=", result.pixel_diff, " passed=", passed)
		failed = failed or not passed
	var file := FileAccess.open(OUTPUT_DIR.path_join("summary.csv"), FileAccess.WRITE)
	if file == null:
		fail("Cannot write QA summary")
		return
	file.store_string("\n".join(lines) + "\n")
	file.close()
	if failed:
		fail("At least one wind/story source comparison changed fewer than 50 corn pixels")
	else:
		print("ENTRY_VISUAL_DIFF_OK")
		quit(0)

func compare_state(case_name: String, camera_position: Vector3, look_at_position: Vector3,
		before_time: float, before_player: Vector3, before_chicken: Vector3, before_creature: Vector3, before_active: bool,
		after_time: float, after_player: Vector3, after_chicken: Vector3, after_creature: Vector3, after_active: bool) -> void:
	camera.position = camera_position
	camera.look_at(look_at_position, Vector3.UP)
	set_shader_state(before_time, before_player, before_chicken, before_creature, before_active)
	var before := await capture_frame()
	set_shader_state(after_time, after_player, after_chicken, after_creature, after_active)
	var after := await capture_frame()
	var changed := count_changed_corn_pixels(before, after)
	var total := count_changed_pixels(before, after)
	var pair := Image.create(before.get_width() * 2, before.get_height(), false, Image.FORMAT_RGBA8)
	pair.blit_rect(before, Rect2i(0, 0, before.get_width(), before.get_height()), Vector2i.ZERO)
	pair.blit_rect(after, Rect2i(0, 0, after.get_width(), after.get_height()), Vector2i(before.get_width(), 0))
	var save_error := pair.save_png(OUTPUT_DIR.path_join("entry-%s-before-after.png" % case_name))
	if save_error != OK:
		fail("Could not save %s pair: %s" % [case_name, error_string(save_error)])
	results.append({"case": case_name, "pixel_diff": total, "changed_green_pixels": changed})

func set_shader_state(animation_time: float, player_position: Vector3, chicken_position: Vector3,
		creature_position: Vector3, creature_active: bool) -> void:
	for material in field._corn_materials:
		material.set_shader_parameter("animation_time", animation_time)
		material.set_shader_parameter("player_position", player_position)
		material.set_shader_parameter("chicken_position", chicken_position)
		material.set_shader_parameter("creature_position", creature_position)
		material.set_shader_parameter("creature_active", 1.0 if creature_active else 0.0)

func capture_frame() -> Image:
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func count_changed_pixels(before: Image, after: Image) -> int:
	var changed := 0
	for y in range(before.get_height()):
		for x in range(before.get_width()):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.075:
				changed += 1
	return changed

func count_changed_corn_pixels(before: Image, after: Image) -> int:
	var changed := 0
	for y in range(before.get_height()):
		for x in range(before.get_width()):
			var a := before.get_pixel(x, y)
			if a.g < 0.055 or a.g < a.r * 1.08 or a.g < a.b * 1.08:
				continue
			var b := after.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.075:
				changed += 1
	return changed

func fail(message: String) -> void:
	printerr("ENTRY_VISUAL_DIFF_FAIL: ", message)
	quit(1)
