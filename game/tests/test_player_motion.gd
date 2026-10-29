extends SceneTree
## Real player + imported clips. No mocked movement or animation player.
const Player = preload("res://scripts/cornfield/player.gd")
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "run"]
const LEG_BONES := ["LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg"]
var failures := 0
var checks := 0
var p

func _initialize() -> void:
	call_deferred("run_checks")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", description)
	else:
		print("PASS: ", description)

func clear_input() -> void:
	for action in ACTIONS:
		Input.action_release(action)

func reset() -> void:
	clear_input()
	p.reset_player()
	p.animation_player.stop()
	p.play_animation("idle")
	p.animation_player.advance(0.0)

func step(delta := 1.0 / 60.0) -> void:
	p._physics_process(delta)
	p.animation_player.advance(delta)

func horizontal_speed() -> float:
	return Vector2(p.velocity.x, p.velocity.z).length()

func leg_pose(clip: Animation, seconds: float) -> Dictionary:
	var result := {}
	for track in clip.get_track_count():
		if clip.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var path := clip.track_get_path(track)
		if path.get_subname_count() == 0:
			continue
		var bone := String(path.get_subname(path.get_subname_count() - 1))
		if bone in LEG_BONES:
			result[bone] = clip.rotation_track_interpolate(track, seconds)
	return result

func pose_error(source: Dictionary, target: Dictionary) -> float:
	var score := 0.0
	for bone in source:
		if target.has(bone):
			var a: Quaternion = source[bone]
			var b: Quaternion = target[bone]
			score += 1.0 - absf(a.dot(b))
	return score

func check_gait_switch(from: String, to: String, at: float) -> float:
	p.current_animation = from
	p.animation_player.play(p.animation_names[from], 0.0)
	p.animation_player.seek(at, true)
	var source: Dictionary = leg_pose(p.animation_player.get_animation(p.animation_names[from]), at)
	var target: Animation = p.animation_player.get_animation(p.animation_names[to])
	p.play_animation(to)
	p.animation_player.advance(0.0)
	var position: float = p.animation_player.current_animation_position
	var reset_error := pose_error(source, leg_pose(target, 0.0))
	var matched_error := pose_error(source, leg_pose(target, position))
	check(matched_error <= reset_error + 0.0001, "%s → %s keeps a leg pose at least as close as frame zero" % [from, to])
	print("GAIT from=%s to=%s source=%.3f target=%.3f reset_error=%.5f matched_error=%.5f" % [from, to, at, position, reset_error, matched_error])
	return reset_error - matched_error

func run_checks() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	root.add_child(floor_body)
	p = Player.new()
	root.add_child(p)
	p.set_physics_process(false)
	p.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	await physics_frame
	reset()
	Input.action_press("move_up")
	step()
	var first_speed := horizontal_speed()
	check(first_speed > 0.5 and first_speed < 2.2, "first input tick moves immediately without a full-speed snap")
	for frame in 3:
		step()
	check(is_equal_approx(horizontal_speed(), 3.0), "direction-only run reaches calibrated 3.0 m/s within 67 ms")
	Input.action_press("run")
	step()
	check(is_equal_approx(horizontal_speed(), 3.0), "Shift press leaves the single run speed unchanged")
	for frame in 4:
		step()
	check(is_equal_approx(horizontal_speed(), 3.0), "run stays at calibrated 3.0 m/s")
	Input.action_release("run")
	step()
	check(is_equal_approx(horizontal_speed(), 3.0), "Shift release leaves the single run speed unchanged")
	for frame in 3:
		step()
	check(is_equal_approx(horizontal_speed(), 3.0), "running continues after releasing Shift")
	Input.action_release("move_up")
	var before_stop: Vector3 = p.position
	step()
	check(is_zero_approx(horizontal_speed()), "release stops horizontal movement on the first tick")
	for frame in 10:
		step()
	check(Vector2(p.position.x, p.position.z).distance_to(Vector2(before_stop.x, before_stop.z)) < 0.0001, "idle pose blend never coasts the collision body")
	check(p.current_animation == "idle", "stopped character returns to idle")
	Input.action_press("move_up")
	for frame in 5:
		step()
	var old_direction: Vector3 = p.facing
	for reversal in 10:
		Input.action_release("move_up" if reversal % 2 == 0 else "move_down")
		Input.action_press("move_down" if reversal % 2 == 0 else "move_up")
		step()
		var expected: Vector3 = -old_direction if reversal % 2 == 0 else old_direction
		check(p.velocity.dot(expected) > 2.99, "rapid reversal %d changes movement immediately without old-direction drift" % reversal)
	reset()
	Input.action_press("move_right")
	for frame in 3:
		step(1.0 / 30.0)
	var turn_30: float = p.visual.rotation.y
	reset()
	Input.action_press("move_right")
	for frame in 12:
		step(1.0 / 120.0)
	check(absf(angle_difference(turn_30, p.visual.rotation.y)) < 0.0001, "visual turning matches at 30 and 120 Hz for equal elapsed time")
	check(absf(angle_difference(p.visual.rotation.y, atan2(p.facing.x, p.facing.z))) < 0.4, "turn reaches within 23 degrees after 100 ms")
	var improvement := 0.0
	for at in [0.35, 1.05, 2.2, 3.4]:
		improvement += check_gait_switch("walk", "run", at)
	for at in [0.12, 0.35, 0.60]:
		improvement += check_gait_switch("run", "walk", at)
	check(improvement > 0.1, "walk/run handoffs actually improve leg-pose continuity instead of restarting every clip")
	check(is_equal_approx(p.animation_player.get_blend_time("walk", "run"), 0.18), "gait changes use the longer 180 ms pose blend")
	check(is_equal_approx(p.animation_player.get_blend_time(p.animation_names["run"], p.animation_names["idle"]), 0.16), "stop uses a 160 ms visual settle without movement drift")
	check(is_equal_approx(p.animation_player.get_blend_time("run", "attack_branch"), 0.14), "attack entry uses a 140 ms pose blend without delaying the attack clock")
	check(is_equal_approx(p.animation_player.get_blend_time("attack_branch", "walk"), 0.14), "attack exit uses a 140 ms recovery blend")
	reset()
	Input.action_press("move_up")
	Input.action_press("run")
	for frame in 6:
		step()
	p.request_attack()
	check(p.current_animation == "attack_branch" and p.attack.elapsed == 0.0, "attack begins immediately from running")
	step()
	check(horizontal_speed() <= 3.0 * 0.28 + 0.0001, "attack movement penalty takes effect immediately without residual sprint speed")
	check(is_equal_approx(p.animation_player.speed_scale, 1.0), "attack clip remains at its original playback speed")
	var total: float = p.attack.duration
	check(absf(total - 1.5416667) < 0.005 and is_equal_approx(p.attack.active_start, 0.59) and is_equal_approx(p.attack.active_end, 0.63), "attack duration and measured hit window remain unchanged")
	for frame in 30:
		step()
	p.request_attack()
	check(p.attack.elapsed > 0.5, "repeated attack input cannot restart the committed attack")
	Input.action_release("move_up")
	step()
	check(is_zero_approx(horizontal_speed()) and p.current_animation == "attack_branch", "movement release stops the body without cancelling the attack")
	Input.action_press("move_down")
	while p.attack.remaining > 0.0:
		step()
	check(p.current_animation == "run" and horizontal_speed() > 0.0, "attack recovery returns to held locomotion without a dead-input frame")
	for frame in 6:
		step()
	check(is_equal_approx(horizontal_speed(), 3.0), "post-attack run recovers calibrated speed promptly")
	p.play_context_action("hurt")
	p.request_attack()
	check(p.context_remaining == 0.0 and p.attack.remaining > 0.0, "responsive hurt recovery and attack priority remain available")
	p.reset_player()
	clear_input()
	step()
	check(is_zero_approx(horizontal_speed()) and p.current_animation == "idle", "reset clears motion and one-shot animation state")
	p.queue_free()
	floor_body.queue_free()
	await process_frame
	print("PLAYER_MOTION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
