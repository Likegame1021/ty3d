extends SceneTree
## Final modifier invariants. Motion files remain independently review-gated.
const ARM := ["RightArm", "RightForeArm", "RightHand"]
const DT := 1.0 / 120.0
const GROUND := .029
var checks := 0
var failures := 0
var p
var sk: Skeleton3D
var vertices: PackedVector3Array
var summary := {}
func _initialize(): call_deferred("run_checks")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", label)
func transforms() -> Array:
	var result := []
	for bone in sk.get_bone_count(): result.append(sk.get_bone_pose(bone))
	return result
func apply_and_measure() -> Dictionary:
	var before := transforms()
	p.melee_hold_pose._process_modification()
	var after := transforms()
	var protected := 0.0
	var origins_scales := 0.0
	for bone in sk.get_bone_count():
		origins_scales = maxf(origins_scales, before[bone].origin.distance_to(after[bone].origin))
		origins_scales = maxf(origins_scales, before[bone].basis.get_scale().distance_to(after[bone].basis.get_scale()))
		if sk.get_bone_name(bone) not in ARM:
			for column in 3: protected = maxf(protected, (before[bone].basis[column] - after[bone].basis[column]).length())
	var hand: Transform3D = p.visual.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightHand"))
	var socket: Transform3D = hand * p.branch_pivot.transform
	var lowest := INF
	for vertex in vertices: lowest = minf(lowest, (socket * vertex).y)
	return {"protected": protected, "origins_scales": origins_scales, "tip": (socket * Vector3(0, .63, 0)).y, "surface": lowest}
func run_checks():
	for action in ["move_left", "move_right", "move_up", "move_down", "run"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	p = load("res://scripts/cornfield/player.gd").new(); root.add_child(p)
	p.set_physics_process(false); p.position = Vector3.ZERO; p.visual.rotation = Vector3.ZERO
	p.melee_hold_pose.active = false; p.corn_hold_pose.active = false; p.cancel_pose.active = false
	p.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	sk = p.melee_hold_pose.get_skeleton()
	vertices = p.branch_pivot.get_node("Branch").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for action in ["idle", "run", "hurt"]:
		p.reset_player(); p.position = Vector3.ZERO; p.visual.rotation = Vector3.ZERO
		if action == "hurt": p.play_context_action("hurt")
		else: p.play_animation(action)
		p.current_animation = action
		p.velocity = Vector3(0, 0, .84) if action == "run" else Vector3.ZERO
		p.animation_player.advance(0); p.melee_hold_pose.advance_state(1)
		var clip: Animation = p.animation_player.get_animation(p.animation_player.current_animation)
		var tip := INF; var surface := INF; var protected := 0.0; var origins_scales := 0.0
		for frame in int(ceil(clip.length / DT)) + 1:
			p.animation_player.seek(minf(frame * DT, clip.length - .000001), true)
			var measured := apply_and_measure()
			tip = minf(tip, measured.tip); surface = minf(surface, measured.surface)
			protected = maxf(protected, measured.protected); origins_scales = maxf(origins_scales, measured.origins_scales)
		check(protected < .000001 and origins_scales < .000001, action + " preserves all 21 protected local rotations and all 24 origins/scales")
		check(surface > GROUND, action + " complete shaft clears .029 m visual ground: %.6f" % surface)
		if action != "hurt": check(tip > (.10 if action == "run" else .05), action + " retains existing tip guard: %.6f" % tip)
		summary[action] = {"tip_min": tip, "surface_min": surface, "protected_error": protected, "origin_scale_error": origins_scales}
	for rank in [1.0, .92, .8464]:
		p.reset_player(); p.position = Vector3.ZERO; p.visual.rotation = Vector3.ZERO
		p.set_attack_recovery_multiplier(rank); p.request_attack()
		var surface := INF; var protected := 0.0; var origins_scales := 0.0; var mapped := 0.0; var min_time := -1.0
		var times: Array = [.59, .60, .61, .62, .63, 1.5416666269302368]
		for frame in 185: times.append(frame * DT)
		times.sort()
		for time in times:
			p.attack.elapsed = time if time <= .63 else .63 + (time - .63) * rank
			p.attack.remaining = maxf(.000001, p.attack.duration - p.attack.elapsed)
			p.animation_player.seek(p.attack.elapsed, true)
			mapped = maxf(mapped, absf(p.get_attack_pose_time() - time))
			var measured := apply_and_measure()
			if measured.surface < surface: min_time = time
			surface = minf(surface, measured.surface); protected = maxf(protected, measured.protected); origins_scales = maxf(origins_scales, measured.origins_scales)
		check(mapped < .000001, "attack profile consumes original source-clock mapping rank %.4f" % rank)
		check(protected < .000001 and origins_scales < .000001, "attack preserves 21 protected rotations and all origins/scales rank %.4f" % rank)
		check(surface > GROUND, "full attack shaft clears visual ground rank %.4f: %.6f" % [rank, surface])
		summary[str(rank)] = {"surface_min": surface, "protected_error": protected, "origin_scale_error": origins_scales, "clock_error": mapped, "surface_min_time": min_time}
	p.free()
	print("REFERENCE_GRIP_MOTION ", JSON.stringify({"checks": checks, "failures": failures, "measurements": summary}))
	quit(1 if failures else 0)
