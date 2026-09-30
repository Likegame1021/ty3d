extends SceneTree

# Route events through Godot's Input and viewport dispatch, never call gameplay handlers.
var failures := 0

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + description)
	else:
		print("PASS: " + description)

func _initialize() -> void:
	call_deferred("run_checks")

func key_event(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)

func tap_key(key: Key) -> void:
	key_event(key, true)
	await process_frame
	await physics_frame
	await physics_frame
	key_event(key, false)
	await process_frame

func click_control(button: Control) -> void:
	# Headless windows are 64x64; Input events use physical window coordinates.
	var location := root.get_final_transform() * button.get_global_rect().get_center()
	await click_window_position(location)

func click_window_position(location: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = location
	motion.global_position = location
	Input.parse_input_event(motion)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = location
	press.global_position = location
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = location
	release.global_position = location
	Input.parse_input_event(release)
	await process_frame

func run_checks() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	for frame in 4:
		await physics_frame
	await tap_key(KEY_E)
	check(game.hud.message_label.text.contains("再靠近"), "E key rejects far interaction")
	game.player.position = Vector3(0, 0.05, -3.8)
	game.player.facing = Vector3(0, 0, -1)
	await physics_frame
	await tap_key(KEY_E)
	check(game.hud.message_label.text.contains("稻草练习桩："), "E key opens target instruction within range")
	await tap_key(KEY_SPACE)
	for frame in 100:
		await physics_frame
	check(game.target.hit_count == 1, "Space key drives one complete attack with one hit")
	await tap_key(KEY_ESCAPE)
	check(paused and game.hud.pause_overlay.visible, "Esc key pauses and shows overlay")
	var frozen_position: Vector3 = game.player.position
	var frozen_count: int = game.target.hit_count
	await tap_key(KEY_W)
	await tap_key(KEY_SPACE)
	await tap_key(KEY_R)
	check(game.player.position == frozen_position and game.target.hit_count == frozen_count, "paused key input cannot move attack or reset")
	var buttons: Array = game.hud.pause_overlay.find_children("*", "Button", true, false)
	check(buttons.size() == 1, "pause menu exposes one resume button")
	if buttons.size() == 1:
		await click_control(buttons[0])
	check(not paused and not game.hud.pause_overlay.visible, "pointer click resumes through GUI button")
	for frame in 3:
		await physics_frame
	check(game.player.attack.remaining == 0.0, "resume button click does not leak into gameplay attack")
	await tap_key(KEY_R)
	check(game.target.hit_count == 0, "R key clears hit counter")
	check(game.player.position.distance_to(Vector3(0, 0.05, 8)) < 0.08, "R key returns player to spawn")
	game.player.position = Vector3(0, 0.05, -3.8)
	game.player.facing = Vector3(0, 0, -1)
	await click_window_position(root.get_final_transform() * Vector2(640, 400))
	for frame in 100:
		await physics_frame
	check(game.target.hit_count == 1, "left pointer click outside GUI performs one real attack")
	await tap_key(KEY_R)
	await tap_key(KEY_TAB)
	check(game.night, "Tab key switches to night")
	await tap_key(KEY_TAB)
	check(not game.night, "second Tab key restores day")
	await tap_key(KEY_ESCAPE)
	check(paused, "Esc can pause again after clicking resume")
	await tap_key(KEY_ESCAPE)
	check(not paused, "second Esc resumes without GUI click")
	var start: Vector3 = game.player.position
	key_event(KEY_W, true)
	key_event(KEY_D, true)
	key_event(KEY_SHIFT, true)
	for frame in 30:
		await physics_frame
	key_event(KEY_W, false)
	key_event(KEY_D, false)
	key_event(KEY_SHIFT, false)
	check(game.player.position.distance_to(start) > 1.8, "physical W D Shift events produce running movement")
	paused = false
	print("Input pipeline: %d failures" % failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
