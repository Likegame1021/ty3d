extends SceneTree
## Compare actual blended skeleton output with the preserved pre-change player.
## Covers every-frame and interrupted Shift toggles, beyond raw clip matching.
const CURRENT = preload("res://scripts/player.gd")
var baseline: GDScript
var failures := 0
var checks := 0
const BONES = ["LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot", "Hips", "Spine", "LeftArm", "RightArm"]
func _initialize():
	call_deferred("run_checks")
func pose(skeleton):
	var result = {}
	for bone in BONES:
		var idx = skeleton.find_bone(bone)
		if idx >= 0:
			result[bone] = skeleton.get_bone_pose_rotation(idx)
	return result
func error(a, b):
	var worst = 0.0
	var name = ""
	for bone in a:
		var v = a[bone].angle_to(b[bone])
		if v > worst:
			worst = v
			name = bone
	return [rad_to_deg(worst), name]
func scenario(script, label, interval, start):
	var p = script.new()
	root.add_child(p)
	p.set_physics_process(false)
	p.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var skeleton = p.find_children("*", "Skeleton3D", true, false)[0]
	p.animation_player.stop()
	p.current_animation = "walk"
	p.animation_player.play("walk", 0.0)
	p.animation_player.seek(start, true)
	p.animation_player.advance(0.0)
	var max_jump = [0.0, ""]
	var max_frame = [0.0, ""]
	var before = pose(skeleton)
	for frame in 180:
		if frame % interval == 0:
			p.play_animation("run" if p.current_animation == "walk" else "walk")
			p.animation_player.advance(0.0)
			var after = pose(skeleton)
			var jump = error(before, after)
			if jump[0] > max_jump[0]:
				max_jump = jump
		p.animation_player.advance(1.0 / 60.0)
		var after_frame = pose(skeleton)
		var delta = error(before, after_frame)
		if delta[0] > max_frame[0]:
			max_frame = delta
		before = after_frame
	print("PROBE ", label, " every=", interval, " start=", start, " zero_dt_deg=", max_jump, " per_frame_deg=", max_frame)
	p.free()
	return max_frame[0]
func run_checks():
	baseline = GDScript.new()
	baseline.source_code = FileAccess.get_file_as_string("res://../docs/qa/player-motion-evidence/player-before.gd.txt")
	if baseline.reload() != OK:
		quit(1)
		return
	for action in ["move_left", "move_right", "move_up", "move_down", "run"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	for interval in [1, 3, 6, 12, 30]:
		for at in [0.35, 1.05, 2.2, 3.4]:
			var original_peak: float = scenario(baseline, "baseline", interval, at)
			var current_peak: float = scenario(CURRENT, "current", interval, at)
			checks += 1
			if current_peak >= original_peak * 0.98:
				failures += 1
				printerr("FAIL: repeated gait handoff should reduce actual skeleton frame delta: ", interval, " / ", at)
	print("PLAYER_GAIT_CONTINUITY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
