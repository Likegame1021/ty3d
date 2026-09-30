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

func run_checks() -> void:
	var game = load("res://levels/full.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	if not game.hud.get("boss_meter"):
		check(false, "boss health meter is present")
		game.queue_free()
		await process_frame
		quit(1)
		return
	check(not game.hud.boss_meter.visible, "boss meter stays out of early zone")
	game.progress.boss_active = true
	game.hud.update_full(game.progress, "", "sunny", false, false)
	check(game.hud.boss_meter.visible and game.hud.boss_meter.value == 12, "boss meter appears with twelve health")
	game.progress.boss_hp = 6
	game.progress.corn_spilled = true
	game.progress.corn_gun = true
	game.hud.update_full(game.progress, "", "snow", true, true, 0.8)
	check(game.hud.boss_meter.value == 6 and game.hud.charge_meter.visible and game.hud.charge_meter.value == 100, "half health and full charge are readable")
	check(game.hud.charge_label.text.contains("就绪"), "ready charge has explicit release prompt")
	game.hud.update_full(game.progress, "", "rain", false, true, -1)
	check(not game.hud.charge_meter.visible and game.hud.detail_label.text.contains("雨"), "charge feedback clears and weather label updates")
	print("Full HUD: %d failures" % failed)
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
