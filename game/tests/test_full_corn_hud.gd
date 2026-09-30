extends SceneTree

var failed := 0

func check(ok: bool, description: String) -> void:
	if ok:
		print("PASS: ", description)
	else:
		failed += 1
		printerr("FAIL: ", description)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	root.content_scale_size = Vector2i(960, 600)
	root.size = Vector2i(960, 600)
	var hud = load("res://ui/full_hud.gd").new()
	root.add_child(hud)
	var progress = load("res://scripts/full_progress.gd").new()
	progress.corn_gun = true
	hud.update_full(progress, "沿中央小路，向前找到稻草练习桩。", "sunny", false, true, 0.55)
	await process_frame
	check(hud.charge_meter.visible and hud.charge_meter.value == 100, "charge reaches ready at 0.55 seconds outside the boss fight")
	check(hud.charge_label.text.contains("就绪"), "ready charge clearly prompts release")
	hud.update_full(progress, "", "sunny", false, true, 0.54)
	check(hud.charge_meter.value < 100 and not hud.charge_label.text.contains("就绪"), "charge does not announce readiness early")
	var has_aim: bool = hud.has_method("update_corn_aim") and hud.has_method("show_corn_hit")
	check(has_aim, "HUD exposes aim and hit feedback to gameplay")
	var card = hud.get("weapon_panel")
	check(card != null and card.visible, "equipped corn gun has its own visible weapon card")
	if has_aim and card != null:
		hud.update_corn_aim(Vector2(410, 260), true, 0.5)
		var reticle = hud.get("corn_reticle")
		check(reticle != null and reticle.visible and reticle.global_position.is_equal_approx(Vector2(410, 260)), "aim feedback follows the supplied screen position")
		check(reticle.mouse_filter == Control.MOUSE_FILTER_IGNORE and card.mouse_filter == Control.MOUSE_FILTER_IGNORE, "weapon UI leaves pointer input available to gameplay")
		hud.show_corn_hit(true)
		check(reticle.hit_time > 0.0, "a confirmed hit starts brief reticle feedback")
		reticle._process(0.2)
		check(reticle.hit_time == 0.0, "hit feedback clears rather than staying on the aim point")
		hud.show_menu("pause", progress)
		hud.update_corn_aim(Vector2(420, 270), true, 1.0)
		check(not reticle.visible, "pause menu suppresses aim even if gameplay sends another update")
		hud.hide_menu()
		hud.update_corn_aim(Vector2(420, 270), true, 0.0)
		check(reticle.visible, "aim can return after the menu closes")
		hud.update_full(progress, "沿中央小路，向前找到稻草练习桩。", "sunny", false, true, 0.55)
		hud.show_message("玉米枪做好了！试试连射和蓄力散射。")
		await process_frame
		await process_frame
		check(Rect2(Vector2.ZERO, Vector2(960, 600)).encloses(card.get_global_rect()), "weapon card stays inside a 960 by 600 viewport")
		check(not card.get_global_rect().intersects(hud.context_label.get_parent().get_parent().get_global_rect()), "weapon card does not overlap the bottom interaction panel")
		check(not card.get_global_rect().intersects(hud.message_label.get_global_rect()), "weapon card does not overlap transient messages")
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var capture_path := OS.get_environment("TEMP").path_join("corn-hud-960.png")
			var capture_error := root.get_texture().get_image().save_png(capture_path)
			check(capture_error == OK, "GPU HUD evidence is saved")
			print("HUD_CAPTURE=", capture_path)
		hud.update_full(progress, "", "sunny", false, false)
		check(not card.visible and not reticle.visible and not hud.charge_meter.visible, "switching away from the gun removes all corn feedback")
		if hud.has_method("set_corn_lab"):
			hud.set_corn_lab(true)
			hud.update_full(progress, "", "sunny", false, true)
			check(hud.objective_label.text.contains("试枪"), "lab mode provides a shooting objective")
			hud.set_corn_lab(false)
			hud.update_full(progress, "", "sunny", false, true)
			check(hud.objective_label.text.contains("入口"), "leaving lab mode restores normal adventure objectives")
	hud.queue_free()
	await process_frame
	print("Full corn HUD: %d failures" % failed)
	quit(1 if failed else 0)
