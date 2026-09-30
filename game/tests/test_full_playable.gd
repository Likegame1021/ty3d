extends SceneTree

var failed := 0
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

func go(game: Node, point: Vector3) -> void:
	game.player.position = point + Vector3.UP * 0.05
	await settle()

func run_checks() -> void:
	var game = load("res://levels/full.tscn").instantiate()
	root.add_child(game)
	await settle()
	check(game.player.has_real_model and game.player.world_max == Vector2(27.5, 47.5), "real character uses full-scene bounds")
	check(game.weather == "sunny" and not game.night and game.progress.health == 5, "fresh run starts sunny daytime with five hearts")
	check(game.context_text().contains("小鸡"), "initial guidance matches chicken objective")
	await go(game, Vector3(16, 0, -13))
	game.interact()
	check(not game.progress.cart_moved, "cart cannot move before board")
	await go(game, Vector3(-5, 0, 31))
	game.interact()
	check(not game.progress.tin_taken, "tin requires chicken clue")
	await go(game, Vector3(-3.5, 0, 36))
	check(game.progress.chicken_seen, "chicken discovery is stable")
	check(game.context_text().contains("铁盒"), "post-chicken guidance points to tin")
	await go(game, Vector3(-5, 0, 31))
	game.interact()
	game.interact()
	check(game.progress.tin_taken and not game.tin.visible, "tin is collected exactly once")
	check(game.context_text().contains("水渠"), "post-tin guidance points to canal")
	await go(game, Vector3(5, 0, 20))
	game.interact()
	check(not game.progress.canal_open, "gate needs mouth clearing")
	await go(game, Vector3(0, 0, 22))
	game.interact()
	await go(game, Vector3(5, 0, 20))
	game.interact()
	check(game.progress.mouth_cleared and game.progress.canal_open, "mouth then gate opens canal")
	check(game.context_text().contains("木板"), "post-canal guidance points to board")
	await go(game, Vector3(-7, 0, 9))
	game.throw_stone()
	check(game.progress.dense_entered and game.progress.stones_thrown == 1 and game.pursuer.mode == "distracted", "stone redirects active pursuer")
	await go(game, Vector3(-5, 0, 4))
	game.interact()
	check(game.progress.fence_vaulted and game.player.position.z < 3, "E vaults fence to north side")
	await go(game, Vector3(12, 0, -9))
	game.interact()
	check(game.context_text().contains("板车"), "post-board guidance points to cart")
	await go(game, Vector3(16, 0, -13))
	game.interact()
	check(game.context_text().contains("棚") or game.context_text().contains("发射器"), "post-cart guidance points to launcher")
	await go(game, Vector3(17, 0, -18))
	game.interact()
	check(game.progress.board_taken and game.progress.cart_moved and game.progress.launcher_taken, "board cart and launcher form ordered route")
	await go(game, Vector3(0, 0, -27))
	check(game.progress.boss_active and game.boss.active, "boss starts only after launcher")
	game.boss.mode = "recover"
	game.boss.phase_remaining = 99
	game.player.position = Vector3(0, 0.05, -32.8)
	game.player.facing = Vector3(0, 0, -1)
	game.player.attack.begin(false)
	game.player.attack.tick(0.60, false)
	game.player.check_hits()
	game.player.check_hits()
	check(game.progress.boss_hp == 11, "real branch hit window damages recovering boss once")
	game.player.attack.reset()
	for i in 5:
		game.boss.hit_cooldown = 0
		game.boss.receive_hit(Vector3.FORWARD)
	check(game.progress.corn_spilled and not game.progress.corn_gun and game.boss.mode == "stagger", "half health drops gun material and gives safe window")
	await go(game, Vector3(5, 0, -33))
	game.interact()
	game.interact()
	check(game.progress.corn_gun and game.gun_equipped and game.progress.boss_hp == 6, "gun combines once without extra boss damage")
	game.boss.hit_cooldown = 0
	game.boss.receive_projectile(6)
	check(game.progress.boss_defeated and game.progress.outcome == "won" and paused, "gun defeats boss and victory freezes scene")
	game.reset_run()
	check(not paused and game.progress.outcome == "playing" and game.progress.health == 5 and not game.progress.tin_taken and not game.progress.canal_open and not game.progress.boss_active and game.weather == "sunny", "victory retry restores all stages and weather")
	game.set_weather("rain")
	game.set_night(true)
	game.set_paused(true)
	game.interact()
	check(paused and not game.progress.tin_taken and game.weather == "rain" and game.night, "pause blocks interaction and keeps weather/night independent")
	game.set_paused(false)
	for i in game.progress.max_health:
		game.on_player_hurt()
		game.progress.tick(2)
	check(game.progress.outcome == "lost" and paused, "five separated hits show failure")
	game.reset_run()
	check(game.progress.outcome == "playing" and not paused and game.weather == "sunny" and not game.night and game.pursuer.mode == "patrol" and game.boss.mode == "idle", "failure retry resets enemies and sky")
	print("Full playable: %d failures" % failed)
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
