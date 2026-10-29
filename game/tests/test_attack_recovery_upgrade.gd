extends SceneTree
## The hook may shorten recovery only. Real imported pose and physical attack clocks
## are compared with the preserved run-only baseline before the contact window ends.
const DT := 1.0 / 120.0
const CURRENT = preload("res://scripts/player.gd")
const IDLE_CALIBRATION = preload("res://scripts/idle_body_calibration.gd")
var failures := 0
var checks := 0
var baseline: GDScript

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	call_deferred("run_checks")

func actor(script: GDScript):
	var p = script.new()
	root.add_child(p)
	p.set_physics_process(false)
	p.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	p.position = Vector3.ZERO
	# Recovery comparison starts from the same reviewed body size on both actors.
	# Playing the source master's name would bypass the runtime alias/blend path.
	IDLE_CALIBRATION.apply(p)
	p.configure_animation_transitions()
	p.animation_player.play(p.animation_names["idle"], 0.0)
	p.current_animation = "idle"
	p.animation_player.advance(0.0)
	p.melee_hold_pose._process_modification() # Establish the same actually displayed idle on both actors.
	return p

func pose(p) -> Array:
	var skeleton: Skeleton3D = p.find_children("*", "Skeleton3D", true, false)[0]
	p.melee_hold_pose._process_modification()
	var rotations := []
	for i in skeleton.get_bone_count():
		rotations.append(skeleton.get_bone_pose_rotation(i))
	return rotations

func pose_difference(a: Array, b: Array) -> float:
	var worst := 0.0
	for i in a.size():
		worst = maxf(worst, rad_to_deg(a[i].normalized().angle_to(b[i].normalized())))
	return worst

func step(p, seconds := DT) -> void:
	# Physical movement is irrelevant here; keep the imported actor above the kill plane.
	p.position.y = 0.0
	p.velocity.y = 0.0
	p._physics_process(seconds)
	# The frozen pre-hook player needs the same once-per-tick carry-state update.
	if p.get_script() == baseline:p.melee_hold_pose.advance_state(seconds)
	p.animation_player.advance(seconds)

func scenario(multiplier: float) -> void:
	var p = actor(CURRENT)
	var old = actor(baseline)
	p.set_attack_recovery_multiplier(multiplier)
	var original_duration: float = old.attack.duration
	var expected_duration: float = 0.63 + (original_duration - 0.63) * multiplier
	check(absf(p.attack.duration - expected_duration) < 0.00001, "rank duration uses only the post-hit segment")
	check(p.attack.active_start == old.attack.active_start and p.attack.active_end == old.attack.active_end, "rank leaves both hit-window edges unchanged")
	p.request_attack()
	old.request_attack()
	var maximum_hit_difference := 0.0
	var peak := {}
	var maximum_protected := 0.0
	var maximum_default_difference := 0.0
	var maximum_time_error := 0.0
	var maximum_mapped_pose_error := 0.0
	var maximum_playback_rate_error := 0.0
	var source_clip: Animation = old.animation_player.get_animation(old.animation_names["attack_branch"])
	var active_clip: Animation = p.animation_player.get_animation(p.animation_names["attack_branch"])
	var frames := 0
	while p.attack.remaining > 0.0 and frames < 240:
		step(old)
		step(p)
		var current_pose := pose(p)
		var old_pose := pose(old)
		for bone in current_pose.size():
			var difference := rad_to_deg(current_pose[bone].normalized().angle_to(old_pose[bone].normalized()))
			if bone < 21: maximum_protected = maxf(maximum_protected, difference)
			if difference > float(peak.get("degrees", -1)): peak = {"bone_index": bone, "time": p.attack.elapsed, "degrees": difference}
		if p.attack.elapsed <= 0.63:
			maximum_hit_difference = maxf(maximum_hit_difference, pose_difference(current_pose, old_pose))
			check(p.attack.elapsed == old.attack.elapsed, "contact attack clock is unchanged")
		if multiplier == 1.0:
			maximum_default_difference = maxf(maximum_default_difference, pose_difference(current_pose, old_pose))
		if p.attack.remaining > 0.0:
			var mapped: float = p.attack.elapsed if p.attack.elapsed <= 0.63 else 0.63 + (p.attack.elapsed - 0.63) / multiplier
			maximum_time_error = maxf(maximum_time_error, absf(p.animation_player.current_animation_position - p.attack.elapsed))
			maximum_playback_rate_error = maxf(maximum_playback_rate_error, absf(p.animation_player.speed_scale - 1.0))
			for track in source_clip.get_track_count():
				if source_clip.track_get_type(track) == Animation.TYPE_ROTATION_3D:
					var original_q := source_clip.rotation_track_interpolate(track, mapped).normalized()
					var current_q := active_clip.rotation_track_interpolate(track, p.attack.elapsed).normalized()
					maximum_mapped_pose_error = maxf(maximum_mapped_pose_error, rad_to_deg(original_q.angle_to(current_q)))
		frames += 1
	check(maximum_hit_difference < 0.1, "authored pose is unchanged through the entire contact segment")
	check(maximum_time_error < 0.00002 and maximum_playback_rate_error == 0.0, "retimed resource plays at 1x without crossing idle/physics clock domains")
	check(maximum_mapped_pose_error < 0.1, "retimed resource preserves the original pose at the piecewise authored time")
	check(float(frames) * DT >= expected_duration and float(frames) * DT < expected_duration + DT, "attack ends on the first eligible physical frame")
	check(p.current_animation == "idle" and p.animation_player.speed_scale == 1.0, "recovery returns to ordinary idle playback")
	if multiplier == 1.0:
		check(maximum_default_difference < 0.1, "empty build preserves baseline poses for the whole attack")
	for repetition in 3:
		p.request_attack()
		p.animation_player.advance(0.0)
		check(p.attack.elapsed == 0.0 and p.animation_player.current_animation_position == 0.0, "repeated completed attacks restart the authored clip")
		while p.attack.elapsed < 0.60:
			step(p)
		check(p.attack.claim_hit(42, false) and not p.attack.claim_hit(42, false), "each repeated swing claims exactly one hit per target")
		while p.attack.remaining > 0.0:
			step(p)
	for at in [0.25, 0.60, 1.10]:
		p.request_attack()
		while p.attack.elapsed < at:
			step(p)
		p.cancel_actions()
		p.request_attack()
		p.animation_player.advance(0.0)
		check(p.attack.elapsed == 0.0 and p.animation_player.current_animation_position == 0.0 and p.animation_player.speed_scale == 1.0, "cancelled normal/upgraded windup/contact/recovery restarts at 1x with no stale clip offset")
		while p.attack.remaining > 0.0:
			step(p)
	print("RECOVERY_RANK ", JSON.stringify({"peak":peak,"protected21_max_deg":maximum_protected,"multiplier":multiplier,"duration":p.attack.duration,"hit_pose_deg":maximum_hit_difference,"default_pose_deg":maximum_default_difference,"mapped_time_error":maximum_time_error,"frames":frames}))
	p.free()
	old.free()

func run_checks() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down", "run"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	baseline = GDScript.new()
	baseline.source_code = FileAccess.get_file_as_string("res://../docs/qa/run-only-evidence/restored-20261002/player-baseline.gd.txt")
	if baseline.source_code.strip_edges().is_empty():
		printerr("FAIL: package is missing the preserved run-only baseline script")
		quit(1)
		return
	# Compare recovery behavior with the same current carry on both actors. The
	# user's later carry-only change intentionally changes anticipation/recovery
	# arm poses; the old player still supplies the original unretimed attack clock.
	baseline.source_code += "\nfunc get_attack_pose_time() -> float:\n\treturn attack.elapsed\nfunc get_attack_pose_duration() -> float:\n\treturn attack.duration\n"
	if baseline.reload() != OK:
		quit(1)
		return
	var p = actor(CURRENT)
	check(p.has_method("set_attack_recovery_multiplier"), "player exposes the approved recovery-only upgrade hook")
	if not p.has_method("set_attack_recovery_multiplier"):
		p.free()
		print("ATTACK_RECOVERY_UPGRADE: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	var authored_clip: Animation = p.animation_player.get_animation("attack_branch")
	var authored_keys := []
	for track in authored_clip.get_track_count():
		check(authored_clip.track_get_type(track) in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D], "current attack resource contains only verified pose-track types")
		check(authored_clip.track_get_interpolation_type(track) in [Animation.INTERPOLATION_LINEAR, Animation.INTERPOLATION_NEAREST], "current attack interpolation supports exact boundary splitting")
		var key_rows := []
		var static_values := true
		var linear_easing := true
		for key in authored_clip.track_get_key_count(track):
			key_rows.append([authored_clip.track_get_key_time(track, key), authored_clip.track_get_key_value(track, key)])
			static_values = static_values and authored_clip.track_get_key_value(track, key) == authored_clip.track_get_key_value(track, 0)
			linear_easing = linear_easing and authored_clip.track_get_key_transition(track, key) == 1.0
		check(authored_clip.track_get_interpolation_type(track) != Animation.INTERPOLATION_NEAREST or static_values, "nearest-neighbor pose tracks are static in the verified attack asset")
		check(linear_easing, "current attack keys have linear easing for exact boundary splitting")
		authored_keys.append(key_rows)
	p.set_attack_recovery_multiplier(0.8464)
	p.request_attack()
	step(p, 0.7)
	var frozen_duration: float = p.attack.duration
	var frozen_remaining: float = p.attack.remaining
	p.set_attack_recovery_multiplier(1.0)
	check(p.attack.duration == frozen_duration and p.attack.remaining == frozen_remaining, "changing equipment cannot retime an attack already in progress")
	p.cancel_actions()
	p.request_attack()
	check(absf(p.attack.duration - 1.5416667) < 0.0001 and p.animation_player.speed_scale == 1.0, "cancelled upgraded attack cleanly starts an unupgraded attack")
	p.cancel_actions()
	p.set_attack_recovery_multiplier(-1.0)
	check(absf(p.attack.duration - (0.63 + (1.5416667 - 0.63) * 0.8464)) < 0.0001, "invalid fast multiplier is clamped to the approved rank-two minimum")
	p.set_attack_recovery_multiplier(2.0)
	check(absf(p.attack.duration - 1.5416667) < 0.0001, "invalid slow multiplier cannot change baseline timing")
	p.free()
	for upgrade_before_cancel in [true, false]:
		p = actor(CURRENT)
		p.request_attack()
		step(p, 0.60)
		if upgrade_before_cancel:
			p.set_attack_recovery_multiplier(0.8464)
		p.cancel_actions()
		if not upgrade_before_cancel:
			p.set_attack_recovery_multiplier(0.8464)
		p.request_attack()
		p.animation_player.advance(0.0)
		check(p.attack.elapsed == 0.0 and p.animation_player.current_animation_position == 0.0, "a cancelled default swing starts an upgraded clip at zero, whether equipment changed before or after cancellation")
		p.free()
	for multiplier in [1.0, 0.92, 0.8464]:
		scenario(multiplier)
	p = actor(CURRENT)
	p.set_attack_recovery_multiplier(0.8464)
	p.request_attack()
	p.set_physics_process(true)
	for frame in 3:
		await physics_frame
	paused = true
	frozen_remaining = p.attack.remaining
	var frozen_clock: float = p.attack.elapsed
	for frame in 5:
		await physics_frame
	check(p.attack.elapsed == frozen_clock and p.attack.remaining == frozen_remaining, "tree pause freezes an upgraded attack's physical clock")
	paused = false
	p.free()
	var unchanged_keys := []
	for track in authored_clip.get_track_count():
		var key_rows := []
		for key in authored_clip.track_get_key_count(track):
			key_rows.append([authored_clip.track_get_key_time(track, key), authored_clip.track_get_key_value(track, key)])
		unchanged_keys.append(key_rows)
	check(authored_keys == unchanged_keys, "rank variants never mutate the original authored animation resource")
	print("ATTACK_RECOVERY_UPGRADE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
