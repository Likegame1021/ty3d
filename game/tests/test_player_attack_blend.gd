extends SceneTree
## Real skeleton regression: entry cannot get sharper, exit must improve,
## and the attack contact pose/timeline must remain identical to baseline.
const CURRENT = preload("res://scripts/player.gd")
var original: GDScript
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _initialize():
	call_deferred("run_checks")
func make_player(script, start):
	var p = script.new()
	root.add_child(p)
	p.set_physics_process(false)
	p.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	p.animation_player.stop()
	p.current_animation = "run"
	p.animation_player.play("run", 0.0)
	p.animation_player.seek(start, true)
	p.animation_player.advance(0.0)
	return p
func pose(p):
	var skeleton = p.find_children("*", "Skeleton3D", true, false)[0]
	var result = []
	for i in skeleton.get_bone_count():
		result.append(skeleton.get_bone_pose_rotation(i))
	return result
func error(a, b):
	var worst = 0.0
	for i in a.size():
		worst = maxf(worst, a[i].angle_to(b[i]))
	return rad_to_deg(worst)
func scenario(start):
	var baseline = make_player(original, start)
	var current = make_player(CURRENT, start)
	baseline.request_attack()
	current.request_attack()
	var previous = [pose(baseline), pose(current)]
	var entry_max = [0.0, 0.0]
	var settled_max = 0.0
	for frame in 93:
		var index = 0
		for p in [baseline, current]:
			p.animation_player.advance(1.0 / 60.0)
			p.attack.tick(1.0 / 60.0, false)
			var actual = pose(p)
			if frame < 8:
				entry_max[index] = maxf(entry_max[index], error(previous[index], actual))
			previous[index] = actual
			index += 1
		if frame > 8:
			settled_max = maxf(settled_max, error(previous[0], previous[1]))
		if frame in [35, 36, 37]:
			check(error(previous[0], previous[1]) < 0.1, "contact pose stays unchanged at frame %d" % (frame + 1))
			check(is_equal_approx(baseline.attack.elapsed, current.attack.elapsed), "blend does not shift attack clock")
			print("ATTACK_HIT frame=", frame + 1, " max_pose_diff_deg=", error(previous[0], previous[1]), " elapsed=", [baseline.attack.elapsed, current.attack.elapsed], " animation_position=", [baseline.animation_player.current_animation_position, current.animation_player.current_animation_position])
	baseline.play_animation("walk")
	current.play_animation("walk")
	var exit_max = [0.0, 0.0]
	for frame in 12:
		var index = 0
		for p in [baseline, current]:
			p.animation_player.advance(1.0 / 60.0)
			var actual = pose(p)
			exit_max[index] = maxf(exit_max[index], error(previous[index], actual))
			previous[index] = actual
			index += 1
	print("ATTACK_SUMMARY entry_max_deg_baseline_current=", entry_max, " exit_max_deg_baseline_current=", exit_max, " settled_difference_deg=", settled_max)
	check(entry_max[1] <= entry_max[0] + 0.1, "attack entry is no sharper than baseline at run phase %.2f" % start)
	check(exit_max[1] < exit_max[0] - 0.5, "attack exit reduces worst per-frame pose change")
	check(settled_max < 0.1, "after the blend, original attack poses are preserved")
	baseline.free()
	current.free()
func run_checks():
	original = GDScript.new()
	original.source_code = FileAccess.get_file_as_string("res://../docs/qa/player-motion-evidence/player-before.gd.txt")
	if original.reload() != OK:
		quit(1)
		return
	for start in [0.12, 0.30, 0.60]:
		scenario(start)
	print("PLAYER_ATTACK_BLEND: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
