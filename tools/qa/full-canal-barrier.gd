extends SceneTree

var failed := 0

func check(ok: bool, name: String) -> void:
	if not ok:
		failed += 1
		printerr("FAIL: ", name)
	else:
		print("PASS: ", name)

func move_north(game: Node, x: float, start_z: float, frames: int = 60) -> float:
	game.player.position = Vector3(x, 0.05, start_z)
	game.player.velocity = Vector3.ZERO
	await physics_frame
	Input.action_press("move_right")
	Input.action_press("move_up")
	for _frame in frames:
		await physics_frame
	Input.action_release("move_right")
	Input.action_release("move_up")
	await physics_frame
	return game.player.position.z

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var game = load("res://levels/full.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	await physics_frame
	var west_z: float = await move_north(game, -10.0, 21.5)
	check(west_z > 20.5, "closed canal blocks physical west-side bypass")
	var east_z: float = await move_north(game, 14.0, 21.5)
	check(east_z > 20.5, "closed canal blocks physical east-side bypass")
	var gate_closed_z: float = await move_north(game, 5.0, 21.5)
	check(gate_closed_z > 20.5, "closed sluice blocks bridge crossing")
	game.progress.mouth_cleared = true
	game.progress.canal_open = true
	game.sync_environment()
	await physics_frame
	var gate_open_z: float = await move_north(game, 5.0, 21.5, 180)
	print("OPEN_CANAL_CROSSING final_z=", gate_open_z)
	check(gate_open_z < 17.0, "opened sluice permits physical bridge crossing")
	print("Full canal physical barriers: %d failures" % failed)
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
