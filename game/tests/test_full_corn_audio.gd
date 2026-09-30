extends SceneTree

var failed := 0

func check(ok: bool, description: String) -> void:
	if ok:
		print("PASS: ", description)
	else:
		failed += 1
		printerr("FAIL: ", description)

func voices_in(fx: Node) -> Array[AudioStreamPlayer3D]:
	var result: Array[AudioStreamPlayer3D] = []
	for child in fx.get_children():
		if child is AudioStreamPlayer3D:
			result.append(child)
	return result

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var audible := AudioServer.get_driver_name() != "Dummy"
	print("CORN_AUDIO_DRIVER=", AudioServer.get_driver_name())
	var fx = load("res://weapons/corn_gun_fx.gd").new()
	root.add_child(fx)
	fx.muzzle_flash(Vector3.ZERO, Vector3.FORWARD, true)
	var scatter_voice: AudioStreamPlayer3D = voices_in(fx)[0]
	var scatter_stream: AudioStream = scatter_voice.stream
	for index in 8:
		fx.impact(Vector3(float(index), 0, -4), Vector3.FORWARD, true)
	check(scatter_voice.stream == scatter_stream and (scatter_voice.playing or not audible), "eight simultaneous impacts preserve the scatter muzzle sample and active output playback")
	check(scatter_voice.global_position == Vector3.ZERO, "crowd impacts do not move the muzzle sound to an impact point")
	fx.clear_effects()
	fx.muzzle_flash(Vector3.ZERO, Vector3.FORWARD, false)
	var first_shot: AudioStreamPlayer3D = voices_in(fx)[0]
	# A rapid follow-up should get its own voice; valid shots can overlap the
	# previous sample tail because the normal-shot pitch varies below 1.0.
	fx.muzzle_flash(Vector3(1, 0, 0), Vector3.FORWARD, false)
	for index in 24:
		fx.impact(Vector3(float(index), 0, -4), Vector3.FORWARD, false)
	check(first_shot.stream == fx._shot_sound and (first_shot.playing or not audible), "repeated impacts preserve the preceding rapid-fire sample tail")
	fx.set_charge(Vector3.ZERO, 0.75)
	var voices := voices_in(fx)
	check(voices.size() <= 9, "saturated shots, impacts and charge remain within nine total voices")
	# AudioStreamPlayer3D starts pending playback on the physics tick.
	await physics_frame
	await process_frame
	check(not audible or fx._charge_audio.playing, "an active audio output backend starts the charge loop")
	paused = true
	await process_frame
	var all_paused := true
	for voice in voices:
		all_paused = all_paused and (not voice.playing or voice.stream_paused)
	check(all_paused, "pausing freezes muzzle, impact and charge streams together")
	paused = false
	var all_resumed := true
	for voice in voices:
		all_resumed = all_resumed and not voice.stream_paused
	check(all_resumed, "resuming releases every audio pool")
	fx.clear_effects()
	check(fx.get_child_count() == 0, "retry cleanup removes all effect and audio nodes synchronously")
	fx.muzzle_flash(Vector3.ZERO, Vector3.FORWARD, true)
	fx.impact(Vector3(0, 0, -3), Vector3.FORWARD, true)
	fx.set_charge(Vector3.ZERO, 1.0)
	check(voices_in(fx).size() == 3, "audio can re-arm after cleanup without stale pool entries")
	var exit_voices := voices_in(fx)
	paused = true
	fx.free()
	var all_freed := true
	for voice in exit_voices:
		all_freed = all_freed and not is_instance_valid(voice)
	check(all_freed, "freeing the weapon while paused releases every playing voice")
	paused = false
	voices.clear()
	exit_voices.clear()
	scatter_stream = null
	await create_timer(0.15).timeout
	print("Full corn audio: %d failures" % failed)
	quit(1 if failed else 0)
