extends SceneTree

# Real GPU captures at a safe spawn. This is a visual/performance sample,
# not a substitute for a first-time player or a whole-level benchmark.
var game: Node3D
var failures := 0
var evidence: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("capture_weather")

func settle(seconds: float) -> void:
	await create_timer(seconds).timeout

func capture_weather() -> void:
	game = load("res://levels/full.tscn").instantiate()
	root.add_child(game)
	await settle(1.0)
	if not game.has_method("set_weather") or not game.has_method("set_night"):
		printerr("FAIL: full level must expose weather and night controls")
		game.queue_free()
		await process_frame
		quit(1)
		return
	for weather in ["sunny", "rain", "snow"]:
		for is_night in [false, true]:
			game.set_night(is_night)
			game.set_weather(weather)
			await settle(1.8)
			var frame_times: Array[float] = []
			var previous_usec := Time.get_ticks_usec()
			for sample in 45:
				await process_frame
				var current_usec := Time.get_ticks_usec()
				frame_times.append(float(current_usec - previous_usec) / 1000.0)
				previous_usec = current_usec
			var filename := "full-weather-%s-%s.png" % [weather, "night" if is_night else "day"]
			await RenderingServer.frame_post_draw
			var screenshot := root.get_texture().get_image()
			var saved := screenshot.save_png("res://tests/" + filename)
			if saved != OK or screenshot.get_width() < 640 or screenshot.get_height() < 400:
				failures += 1
				printerr("FAIL: weather capture " + filename)
			frame_times.sort()
			var total := 0.0
			for duration in frame_times:
				total += duration
			evidence.append({
				"weather": weather, "night": is_night, "file": filename,
				"capture_ok": saved == OK,
				"width": screenshot.get_width(), "height": screenshot.get_height(),
				"sample_frames": frame_times.size(),
				"mean_wall_frame_ms": total / frame_times.size(),
				"p95_wall_frame_ms": frame_times[int(frame_times.size() * 0.95)],
				"rendered_objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				"rendered_primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			})
			print("CAPTURE: ", filename)
	var file := FileAccess.open("res://tests/full-weather-evidence.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"kind": "real GPU six weather/day-night captures at entrance",
		"renderer": RenderingServer.get_video_adapter_name(),
		"display_server": DisplayServer.get_name(),
		"engine": Engine.get_version_info().string,
		"limits": "Short spawn samples with automated weather selection; not whole-level minimum FPS, human audio evaluation, or first-play duration.",
		"captures": evidence, "failures": failures
	}, "  "))
	file.close()
	game.queue_free()
	await process_frame
	await process_frame
	print("Full weather GPU capture: %d failures" % failures)
	quit(1 if failures else 0)
