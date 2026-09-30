extends SceneTree

const Progress = preload("res://scripts/full_progress.gd")
var failed := 0

func check(ok: bool, name: String) -> void:
	if not ok:
		failed += 1
		printerr("FAIL: ", name)
	else:
		print("PASS: ", name)

func _initialize() -> void:
	var p = Progress.new()
	check(not p.take_board() and not p.open_canal() and not p.take_launcher(), "later zones cannot be skipped")
	check(not p.take_tin(), "chicken clue is required")
	check(p.see_chicken() and p.take_tin() and not p.take_tin(), "chicken and tin happen once")
	check(not p.open_canal() and p.clear_mouth() and p.open_canal(), "water mouth precedes gate")
	check(p.enter_dense() and p.throw_stone() and p.vault_fence(), "pursuit tools are usable")
	check(not p.move_cart() and p.take_board() and p.move_cart() and p.take_launcher(), "board-cart-launcher order")
	check(not p.take_launcher() and p.enter_boss(), "launcher is unique and opens boss")
	check(not p.make_corn_gun() and not p.win(), "gun and win cannot be skipped")
	check(p.hurt_boss(6) and p.corn_spilled and p.make_corn_gun(), "half health reveals corn gun")
	check(p.hurt_boss(6) and p.win() and p.outcome == "won", "boss defeat ends run")
	var early = Progress.new()
	early.see_chicken()
	early.take_tin()
	early.clear_mouth()
	early.open_canal()
	early.enter_dense()
	early.take_board()
	early.move_cart()
	early.take_launcher()
	early.enter_boss()
	early.hurt_boss(early.max_boss_hp)
	check(early.boss_hp == 1 and not early.boss_defeated and not early.win(), "branch alone cannot finish before gun combination")
	var stopped: float = p.elapsed
	p.tick(3)
	check(p.elapsed == stopped and not p.take_damage(), "outcome freezes time and damage")
	p.reset()
	check(p.health == p.max_health and p.outcome == "playing" and not p.tin_taken and not p.canal_open and not p.launcher_taken and not p.corn_gun and p.boss_hp == p.max_boss_hp, "retry restores complete progress")
	for i in p.max_health:
		check(p.take_damage(), "separate hit accepted")
		p.tick(2)
	check(p.outcome == "lost" and not p.win(), "zero hearts loses and cannot win")
	print("Full progress: %d failures" % failed)
	quit(1 if failed else 0)
