extends SceneTree

const Minion = preload("res://scripts/full_minion.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
	else:
		print("PASS: ", message)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var game = load("res://levels/full.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	game.progress.corn_gun = true
	game.gun_equipped = true
	game.update_weapon_visual()
	game.player.position = Vector3(0, 0.05, -31)
	game.player.facing = Vector3.FORWARD
	game.boss.active = false
	game.pursuer.active = false
	var side = Minion.new()
	side.position = Vector3(3.0, 0.05, -35)
	game.add_child(side)
	side.set_physics_process(false)
	await physics_frame
	game.fire_gun(false)
	check(side.active, "normal shot does not hit a target far outside the aiming line")
	if is_instance_valid(side) and not side.is_queued_for_deletion():
		side.queue_free()
	await physics_frame
	var aligned = Minion.new()
	aligned.position = Vector3(0, 0.05, -35)
	game.add_child(aligned)
	aligned.set_physics_process(false)
	await physics_frame
	game.fire_cooldown = 0
	game.fire_gun(false)
	check(not aligned.active, "normal shot hits the target on the aiming line")
	await physics_frame
	var blocked = Minion.new()
	blocked.position = Vector3(0, 0.05, -35)
	game.add_child(blocked)
	blocked.set_physics_process(false)
	var wall := StaticBody3D.new()
	wall.position = Vector3(0, 0.7, -33)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2, 1.4, 0.3)
	collider.shape = shape
	wall.add_child(collider)
	game.add_child(wall)
	await physics_frame
	game.fire_cooldown = 0
	game.fire_gun(false)
	check(blocked.active, "normal shot cannot damage an enemy behind a solid wall")
	game.fire_cooldown = 0
	game.fire_gun(true)
	check(blocked.active, "scatter cannot damage an enemy behind a solid wall")
	paused = false
	game.queue_free()
	await process_frame
	root.size = Vector2i(1280, 800)
	var lab = load("res://levels/corn_lab.tscn").instantiate()
	root.add_child(lab)
	lab.player.position = Vector3(-1, 0.05, -33)
	await physics_frame
	await physics_frame
	lab.camera.position = Vector3(15, 19, -19)
	lab.camera.look_at(Vector3(0, 0, -34))
	lab.set_process(false)
	var dummy = lab.practice_targets[0]
	var hp: int = dummy.health
	var aim: Vector2 = lab.camera.unproject_position(Vector3(0, 0.95, -33.83))
	lab.aim_screen = aim
	lab.mouse_aim_active = true
	lab.update_corn_aim()
	lab.fire_gun(false)
	check(dummy.health == hp - 1, "aiming at the visible wooden bullseye hits from a close diagonal")
	lab.cancel_gun_input(true)
	lab.player.facing = Vector3.RIGHT
	lab.fire_cooldown = 0
	hp = dummy.health
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.position = root.get_final_transform() * aim
	press.global_position = press.position
	press.pressed = true
	Input.parse_input_event(press)
	for frame in 45:
		await physics_frame
		await process_frame
	var release = press.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame
	await process_frame
	await physics_frame
	check(dummy.health == hp - 3, "first right click aims at its pointer without requiring prior mouse movement")
	lab.queue_free()
	await process_frame
	await process_frame
	print("Corn aiming: %d failures" % failures)
	quit(1 if failures else 0)
