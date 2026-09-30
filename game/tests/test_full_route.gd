extends SceneTree

var failed := 0
var reached: Array[String] = []
func check(ok: bool, name: String) -> void:
	if not ok:
		failed += 1
		printerr("FAIL: ", name)
	else:
		print("PASS: ", name)

func _initialize() -> void:
	call_deferred("run_checks")

func settle() -> void:
	await physics_frame
	await physics_frame

func walk_to(game: Node, target: Vector3) -> bool:
	var destination := Vector3(target.x, 0.05, target.z)
	for step in 180:
		var difference: Vector3 = destination - game.player.position
		difference.y = 0
		if difference.length() < 0.16:
			return true
		var movement: Vector3 = difference.normalized() * minf(0.55, difference.length())
		var contact = game.player.move_and_collide(movement)
		if contact:
			print("ROUTE_BLOCK: ", contact.get_collider().name, " at ", game.player.position, " to ", destination)
			return false
	return false

func run_checks() -> void:
	var game = load("res://levels/full.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.player.set_physics_process(false)
	game.pursuer.set_physics_process(false)
	game.boss.set_physics_process(false)
	check(walk_to(game, Vector3(-3.5, 0, 36)), "spawn physically reaches chicken")
	await settle()
	check(game.progress.chicken_seen, "route actually observes harmless chicken")
	check(walk_to(game, Vector3(-5, 0, 31)), "chicken path reaches tin")
	game.interact()
	check(game.progress.tin_taken, "route carries tin")
	check(walk_to(game, Vector3(0, 0, 22)), "main route reaches water mouth")
	game.interact()
	check(game.progress.mouth_cleared, "route clears mouth")
	check(walk_to(game, Vector3(5, 0, 21.5)), "route can stand on south side of gate")
	check(not walk_to(game, Vector3(5, 0, 16.5)) and game.player.position.z > 20.7, "closed center gate physically blocks crossing")
	game.player.position = Vector3(-24, 0.05, 22)
	check(not walk_to(game, Vector3(-24, 0, 16)) and game.player.position.z > 20.7, "closed west bank prevents bypass")
	game.player.position = Vector3(24, 0.05, 22)
	check(not walk_to(game, Vector3(24, 0, 16)) and game.player.position.z > 20.7, "closed east bank prevents bypass")
	game.player.position = Vector3(5, 0.05, 21.5)
	game.interact()
	check(game.progress.canal_open, "route opens gate from reachable south bank")
	check(walk_to(game, Vector3(5, 0, 16)), "open bridge physically crosses canal")
	reached.append("bridge")
	check(walk_to(game, Vector3(-7, 0, 9)), "route enters dense corn and reaches stone point")
	await settle()
	game.throw_stone()
	check(game.progress.stones_thrown == 1 and game.pursuer.mode == "distracted", "physical route uses stone distraction")
	check(walk_to(game, Vector3(-5, 0, 4.2)), "route reaches south side of low fence")
	check(not walk_to(game, Vector3(-5, 0, 1.8)), "low fence physically requires vault at its center")
	game.interact()
	check(game.progress.fence_vaulted and game.player.position.z < 3, "route vaults low fence")
	check(walk_to(game, Vector3(12, 0, -9)), "route reaches farm board")
	game.interact()
	check(game.progress.board_taken, "route picks board")
	check(walk_to(game, Vector3(16, 0, -11.6)), "route reaches south side of solid cart")
	check(not walk_to(game, Vector3(17, 0, -18)), "cart physically blocks shed before moving")
	game.player.position = Vector3(16, 0.05, -11.6)
	game.interact()
	check(game.progress.cart_moved, "route moves cart with board")
	await settle()
	check(walk_to(game, Vector3(17, 0, -18)), "moved cart permits physical entry into shed")
	game.interact()
	check(game.progress.launcher_taken, "route takes old launcher")
	await settle()
	check(walk_to(game, Vector3(17, 0, -14.4)), "route exits shed through open south face")
	check(walk_to(game, Vector3(0, 0, -14.4)), "route clears shed side wall")
	check(walk_to(game, Vector3(0, 0, -25)), "route reaches boss approach")
	check(walk_to(game, Vector3(0, 0, -32.8)), "launcher unlocks physical boss entrance")
	await settle()
	check(game.progress.boss_active and game.boss.active, "physical entry starts boss")
	reached.append("boss")
	print("FULL_ROUTE_EVIDENCE: ", {"waypoints": reached, "canal_open": game.progress.canal_open, "cart_moved": game.progress.cart_moved, "launcher_taken": game.progress.launcher_taken, "boss_active": game.progress.boss_active})
	print("Full route: %d failures" % failed)
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
