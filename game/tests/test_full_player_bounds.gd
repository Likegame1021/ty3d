extends SceneTree

const Player = preload("res://scripts/player.gd")
var failed := 0

func check(ok: bool, name: String) -> void:
	if not ok:
		failed += 1
		printerr("FAIL: ", name)
	else:
		print("PASS: ", name)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down", "run"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var original = Player.new()
	root.add_child(original)
	var wide = Player.new()
	wide.world_min = Vector2(-27.5, -47.5)
	wide.world_max = Vector2(27.5, 47.5)
	wide.spawn_position = Vector3(0, 0.05, 40)
	root.add_child(wide)
	await physics_frame
	check(original.world_min == Vector2(-13.5, -15.5) and original.world_max == Vector2(13.5, 15.5), "M0/M1 keep original bounds")
	wide.position = Vector3(26, 0.05, -40)
	await physics_frame
	check(wide.position.x > 25 and wide.position.z < -39, "full-scene player can reach outer zones")
	wide.position = Vector3(40, 0.05, -60)
	await physics_frame
	check(wide.position.x <= 27.5 and wide.position.z >= -47.5, "full-scene player remains within world")
	print("Full player bounds: %d failures" % failed)
	original.queue_free()
	wide.queue_free()
	await process_frame
	quit(1 if failed else 0)
