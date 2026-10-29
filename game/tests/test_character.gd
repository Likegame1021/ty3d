extends SceneTree

var failures := 0

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + description)
	else:
		print("PASS: " + description)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	var player = game.player
	check(player.has_real_model, "actual boy GLB loaded")
	check(player.animation_names.size() == 4, "all four actual animation clips discovered")
	var attachment = player.branch_pivot.get_parent()
	check(attachment is BoneAttachment3D and attachment.bone_name == "RightHand", "branch attached to actual RightHand bone")
	var grip = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference-grip-v4-r2/grip-frame.json"))
	var center = Vector3(grip.grip_center_right_hand_local[0],grip.grip_center_right_hand_local[1],grip.grip_center_right_hand_local[2])
	check(player.branch_pivot.position.distance_to(center) < 0.000001, "branch uses independently reviewed anatomical grip center")
	var stick = player.branch_pivot.get_child(0)
	var shaft_axis = Vector3(grip.shaft_axis_toward_tip[0],grip.shaft_axis_toward_tip[1],grip.shaft_axis_toward_tip[2])
	check(player.branch_pivot.basis.y.distance_to(shaft_axis) < 0.000001, "long branch end follows reviewed thumb-side grip axis")
	check(absf(stick.mesh.get_aabb().size.y * stick.global_basis.get_scale().y - 0.7) < 0.01, "reviewed tapered branch stays 0.7 metre despite skeleton scale")
	player.set_physics_process(false)
	var actual_length: float = player.animation_player.get_animation("attack_branch").length
	player.attack.begin(false)
	check(absf(player.attack.remaining - actual_length) < 0.01, "attack state preserves full actual clip duration")
	player.attack.tick(0.2, false)
	check(not player.attack.claim_hit(123, false), "actual back swing cannot cause early hit")
	player.attack.tick(0.38, false)
	check(not player.attack.claim_hit(123, false), "side swing before measured forward contact cannot hit")
	player.attack.tick(0.02, false)
	check(player.attack.claim_hit(123, false), "measured forward strike at 0.60 seconds can hit")
	check(not player.attack.claim_hit(123, false), "actual strike still counts each target only once")
	player.attack.tick(0.07, false)
	check(not player.attack.claim_hit(456, false), "measured side recovery at 0.67 seconds cannot hit")
	player.attack.reset()
	player.set_physics_process(true)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.keycode = KEY_SPACE
	key.pressed = true
	Input.parse_input_event(key)
	for frame in 48:
		await physics_frame
	check(player.current_animation == "attack_branch" and player.attack.remaining > 0.65, "actual attack remains playing past old 0.48 second cutoff")
	var release := InputEventKey.new()
	release.physical_keycode = KEY_SPACE
	release.keycode = KEY_SPACE
	Input.parse_input_event(release)
	for frame in 55:
		await physics_frame
	check(player.attack.remaining == 0.0 and player.current_animation == "idle", "full recovery completes then idle resumes")
	var walk_key := InputEventKey.new()
	walk_key.physical_keycode = KEY_W
	walk_key.keycode = KEY_W
	walk_key.pressed = true
	Input.parse_input_event(walk_key)
	for frame in 5:
		await physics_frame
	check(player.current_animation == "run" and player.animation_player.current_animation == "run", "actual run clip selected by direction input alone")
	var run_key := InputEventKey.new()
	run_key.physical_keycode = KEY_SHIFT
	run_key.keycode = KEY_SHIFT
	run_key.pressed = true
	Input.parse_input_event(run_key)
	for frame in 5:
		await physics_frame
	check(player.current_animation == "run" and player.animation_player.current_animation == "run", "Shift preserves the existing run clip")
	walk_key = InputEventKey.new()
	walk_key.physical_keycode = KEY_W
	Input.parse_input_event(walk_key)
	run_key = InputEventKey.new()
	run_key.physical_keycode = KEY_SHIFT
	Input.parse_input_event(run_key)
	for frame in 3:
		await physics_frame
	check(player.current_animation == "idle", "movement release returns actual character to idle")
	print("Actual character integration: %d failures" % failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
