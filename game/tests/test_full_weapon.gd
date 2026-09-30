extends SceneTree

const Minion = preload("res://scripts/full_minion.gd")
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
	var game = load("res://levels/full.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	if not game.has_method("update_weapon_visual"):
		check(false, "gun visual integration exists")
		game.queue_free()
		await process_frame
		quit(1)
		return
	game.progress.see_chicken()
	game.progress.take_tin()
	game.progress.clear_mouth()
	game.progress.open_canal()
	game.progress.enter_dense()
	game.progress.take_board()
	game.progress.move_cart()
	game.progress.take_launcher()
	game.progress.enter_boss()
	game.boss.active = true
	game.progress.hurt_boss(6)
	game.progress.make_corn_gun()
	game.gun_equipped = true
	game.update_weapon_visual()
	check(game.gun_model.visible and not game.player.branch_pivot.get_node("Branch").visible, "equipped gun replaces branch in real hand")
	game.gun_equipped = false
	game.update_weapon_visual()
	check(not game.gun_model.visible and game.player.branch_pivot.get_node("Branch").visible, "Q switching restores visible branch")
	game.gun_equipped = true
	game.update_weapon_visual()
	game.player.position = Vector3(0, 0.05, -31.5)
	game.player.facing = Vector3(0, 0, -1)
	game.boss.position = Vector3(0, 0, -36)
	var left = Minion.new()
	left.player = game.player
	left.position = Vector3(-1.5, 0.05, -35)
	game.add_child(left)
	var right = Minion.new()
	right.player = game.player
	right.position = Vector3(1.5, 0.05, -35)
	game.add_child(right)
	await physics_frame
	game.fire_gun(true)
	check(not left.active and not right.active, "charged cone reaches two separate nearby minions")
	check(game.progress.boss_hp == 3, "charged cone damages boss once for three")
	check(get_nodes_in_group("corn_tracers").size() >= 5, "charged shot draws at least five spread pellets")
	game.fire_cooldown = 0
	game.boss.hit_cooldown = 0
	game.player.position = Vector3(0, 0.05, -27.5)
	game.player.facing = Vector3(0, 0, -1)
	check(game.player.can_reach(game.boss, 9.0), "normal range has clear line to farther boss")
	game.fire_gun(false)
	check(game.progress.boss_hp == 2, "normal shot reaches farther than charged scatter")
	print("Full weapon: %d failures" % failed)
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
