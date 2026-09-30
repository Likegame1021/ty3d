extends SceneTree

# Walks the real CharacterBody across the real map through Input actions.
var game: Node3D
var failures := 0
var route_evidence := []
var creature_modes := []

func _initialize() -> void:
	call_deferred("run_route")

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + description)
	else:
		print("PASS: " + description)

func stop_moving() -> void:
	for action in ["move_up", "move_down", "move_left", "move_right", "run"]:
		Input.action_release(action)

func steer(direction: Vector3) -> void:
	var normalized := direction.normalized()
	var horizontal := (normalized.x - normalized.z) / sqrt(2.0)
	var vertical := (normalized.x + normalized.z) / sqrt(2.0)
	Input.action_press("move_right", maxf(0.0, horizontal))
	Input.action_press("move_left", maxf(0.0, -horizontal))
	Input.action_press("move_down", maxf(0.0, vertical))
	Input.action_press("move_up", maxf(0.0, -vertical))

func walk_to(destination: Vector3) -> bool:
	for frame in 900:
		var offset: Vector3 = destination - game.player.position
		offset.y = 0
		if offset.length() < 0.24:
			stop_moving()
			route_evidence.append({"x": game.player.position.x, "z": game.player.position.z, "seconds": game.progress.elapsed})
			return true
		steer(offset)
		await physics_frame
		if not creature_modes.has(game.creature.mode):
			creature_modes.append(game.creature.mode)
		if game.progress.outcome != "playing":
			stop_moving()
			return false
	stop_moving()
	return false

func tap(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await physics_frame
	await physics_frame
	var release := InputEventKey.new()
	release.keycode = key
	release.physical_keycode = key
	Input.parse_input_event(release)

func run_route() -> void:
	game = load("res://levels/entry.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	check(await walk_to(Vector3(-1.8, 0, 9.2)), "walk from spawn to side path")
	check(await walk_to(Vector3(-3.8, 0, 7)), "walk to harmless chicken")
	check(game.progress.chicken_discovered, "walking route reveals chicken without teleport")
	check(await walk_to(Vector3(-5.5, 0, 1.6)), "walk cleared side path to box")
	await tap(KEY_E)
	check(game.progress.item_collected, "walking route picks box through E input")
	check(await walk_to(Vector3(-1.7, 0, -2.7)), "walk back toward central road")
	check(await walk_to(Vector3(3.2, 0, -3.0)), "take bypass to the east of creature")
	check(await walk_to(Vector3(3.2, 0, -9.8)), "bypass passes creature patrol zone")
	check(await walk_to(Vector3(0, 0, -12.6)), "walk back to northern exit")
	await tap(KEY_E)
	check(game.progress.outcome == "won" and game.progress.health == 3 and game.creature.hit_count == 0, "real movement route completes without combat or damage")
	var file := FileAccess.open("res://tests/entry-route-evidence.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"route": "non-combat real movement", "points": route_evidence, "creature_modes": creature_modes, "outcome": game.progress.outcome, "health": game.progress.health, "creature_hits": game.creature.hit_count, "elapsed": game.progress.elapsed}, "  "))
	print("Entry physical route: %d failures; %.2f seconds of direct automated walking" % [failures, game.progress.elapsed])
	paused = false
	stop_moving()
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
